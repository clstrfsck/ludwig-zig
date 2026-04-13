const std = @import("std");
const types = @import("types.zig");
const str_object = @import("str_object.zig");
const mark = @import("mark.zig");

pub const LineRange = struct {
    first: *types.LineHdrObject,
    last: *types.LineHdrObject,
};

pub const FrameFixture = struct {
    frame: *types.FrameObject,
    content_lines: []*types.LineHdrObject,
    sentinel_line: *types.LineHdrObject,
};

pub fn lineEOPCreate(
    allocator: std.mem.Allocator,
    inframe: *types.FrameObject,
) !*types.GroupObject {
    const new_line = try allocator.create(types.LineHdrObject);
    new_line.* = .{};

    const new_group = try allocator.create(types.GroupObject);
    new_group.* = .{
        .frame = inframe,
        .first_line = new_line,
        .last_line = new_line,
        .first_line_num = 1,
        .num_lines = 1,
    };
    new_line.group = new_group;

    return new_group;
}

pub fn linesCreate(
    allocator: std.mem.Allocator,
    line_count: usize,
) !LineRange {
    var top_line: ?*types.LineHdrObject = null;
    var prev_line: ?*types.LineHdrObject = null;
    var last_line: ?*types.LineHdrObject = null;

    var line_nr: usize = 0;
    while (line_nr < line_count) : (line_nr += 1) {
        const this_line = try allocator.create(types.LineHdrObject);
        this_line.* = .{
            .b_link = prev_line,
        };
        if (top_line == null) {
            top_line = this_line;
        }
        if (prev_line) |line| {
            line.f_link = this_line;
        }
        prev_line = this_line;
        last_line = this_line;
    }

    return .{
        .first = top_line.?,
        .last = last_line.?,
    };
}

/// Inject `first_line` through `last_line` before `before_line`.
pub fn linesInject(
    allocator: std.mem.Allocator,
    first_line: *types.LineHdrObject,
    last_line: *types.LineHdrObject,
    before_line: *types.LineHdrObject,
) !void {
    var nr_new_lines: isize = 0;
    var space: isize = 0;
    var scan_line: ?*types.LineHdrObject = first_line;
    while (scan_line) |line| {
        space += line.len();
        nr_new_lines += 1;
        scan_line = line.f_link;
    }

    const top_line = before_line.b_link;
    const end_group = before_line.group.?;
    const top_group = end_group.b_link;
    const this_frame = end_group.frame;

    const nr_free_lines_end = types.max_group_lines - end_group.num_lines;
    const nr_free_lines_top = if (top_group) |group| types.max_group_lines - group.num_lines else 0;
    const nr_free_lines = nr_free_lines_end + nr_free_lines_top;
    var line_nr = end_group.first_line_num;

    var adjust_group: ?*types.GroupObject = null;
    if (nr_new_lines > nr_free_lines) {
        const nr_new_groups = @divFloor(nr_new_lines - nr_free_lines - 1, types.max_group_lines) + 1;
        var first_group: ?*types.GroupObject = null;
        var last_group: ?*types.GroupObject = null;

        var group_nr: isize = 1;
        while (group_nr <= nr_new_groups) : (group_nr += 1) {
            const this_group = try allocator.create(types.GroupObject);
            this_group.* = .{
                .b_link = last_group,
                .frame = this_frame,
                .first_line_num = line_nr,
            };

            if (first_group == null) {
                first_group = this_group;
            }
            if (last_group) |group| {
                group.f_link = this_group;
            }
            last_group = this_group;
        }

        last_group.?.f_link = end_group;
        end_group.b_link = last_group;
        if (top_group) |group| {
            group.f_link = first_group.?;
            adjust_group = group;
        } else {
            this_frame.first_group = first_group.?;
            adjust_group = first_group.?;
        }
        first_group.?.b_link = top_group;
    } else if (nr_new_lines > nr_free_lines_end) {
        adjust_group = top_group.?;
    } else {
        adjust_group = end_group;
    }

    last_line.f_link = before_line;
    before_line.b_link = last_line;
    if (before_line.offset_num == 0) {
        end_group.first_line = first_line;
    }
    if (top_line) |line| {
        line.f_link = first_line;
    }
    first_line.b_link = top_line;

    var nr_lines_to_adjust = nr_new_lines;
    var adjust_line: *types.LineHdrObject = undefined;

    if (nr_new_lines > nr_free_lines_end) {
        adjust_line = end_group.first_line.?;
        nr_lines_to_adjust += before_line.offset_num;
        end_group.num_lines = 0;
    } else {
        adjust_line = first_line;
        end_group.num_lines = before_line.offset_num;
    }
    const end_group_last_line = end_group.last_line.?;

    while (nr_lines_to_adjust > 0) {
        const group = adjust_group.?;
        const nr_lines_to_adjust_here = @min(types.max_group_lines - group.num_lines, nr_lines_to_adjust);
        if (group.num_lines == 0) {
            group.first_line = adjust_line;
            group.first_line_num = line_nr;
        }

        var offset = group.num_lines;
        while (offset < group.num_lines + nr_lines_to_adjust_here) : (offset += 1) {
            adjust_line.group = group;
            adjust_line.offset_num = offset;
            adjust_line = adjust_line.f_link.?;
        }

        group.last_line = adjust_line.b_link;
        group.num_lines += nr_lines_to_adjust_here;
        line_nr = group.first_line_num + group.num_lines;
        nr_lines_to_adjust -= nr_lines_to_adjust_here;
        adjust_group = group.f_link;
    }

    const next_group_first_line = end_group_last_line.f_link;
    var offset = end_group.num_lines;
    var tail_line: ?*types.LineHdrObject = adjust_line;
    while (true) {
        tail_line.?.offset_num = offset;
        offset += 1;
        tail_line = tail_line.?.f_link;
        if (tail_line == next_group_first_line) {
            break;
        }
    }

    end_group.last_line = end_group_last_line;
    if (adjust_group == end_group) {
        end_group.first_line_num = line_nr;
        end_group.first_line = before_line;
    }
    end_group.num_lines = offset;

    var shift_group = end_group.f_link;
    while (shift_group) |group| {
        group.first_line_num += nr_new_lines;
        shift_group = group.f_link;
    }

    this_frame.space_left -= space;
}

pub fn linesExtract(
    first_line: *types.LineHdrObject,
    last_line: *types.LineHdrObject,
) void {
    const top_line = first_line.b_link;
    const end_line = last_line.f_link.?;

    var first_group = first_line.group.?;
    var last_group = last_line.group.?;
    var top_group: ?*types.GroupObject = null;
    if (top_line) |line| {
        top_group = line.group.?;
    }
    var end_group = end_line.group.?;
    const this_frame = end_group.frame;

    const first_line_offset_nr = first_line.offset_num;
    const first_line_nr = first_group.first_line_num + first_line_offset_nr;
    var nr_lines_to_remove = last_group.first_line_num + last_line.offset_num - first_line_nr + 1;

    if (top_line) |line| {
        line.f_link = end_line;
    }
    first_line.b_link = null;
    last_line.f_link = null;
    end_line.b_link = top_line;

    var space: isize = 0;
    var this_line: ?*types.LineHdrObject = first_line;
    var line_nr: isize = 1;
    while (line_nr <= nr_lines_to_remove) : (line_nr += 1) {
        space += this_line.?.len();
        this_line = this_line.?.f_link;
    }
    this_frame.space_left += space;

    if (top_group != end_group) {
        if (top_group) |group| {
            group.last_line = top_line;
        }
        end_group.first_line = end_line;
        end_group.first_line_num = first_line_nr;
    }

    var renumber_group = end_group.f_link;
    while (renumber_group) |group| {
        group.first_line_num -= nr_lines_to_remove;
        renumber_group = group.f_link;
    }

    if (first_group == top_group) {
        nr_lines_to_remove -= first_group.num_lines - first_line_offset_nr;
        first_group.num_lines = first_line_offset_nr;
        if (first_group != last_group) {
            first_group = first_group.f_link.?;
        }
    }

    var consume_group: ?*types.GroupObject = first_group;
    while (nr_lines_to_remove > 0) {
        const group = consume_group.?;
        nr_lines_to_remove -= group.num_lines;
        group.num_lines = 0;
        consume_group = group.f_link;
    }

    if (nr_lines_to_remove < 0) {
        var offset: isize = undefined;
        if (top_group == end_group) {
            offset = first_line_offset_nr;
            end_group.num_lines = offset - nr_lines_to_remove;
        } else {
            offset = 0;
            end_group.num_lines = -nr_lines_to_remove;
        }

        this_line = end_line;
        while (offset < end_group.num_lines) : (offset += 1) {
            this_line.?.offset_num = offset;
            this_line = this_line.?.f_link;
        }
    }

    if (first_group.num_lines == 0) {
        last_group = first_group;
        end_group = last_group.f_link.?;
        while (end_group.num_lines == 0) {
            last_group = end_group;
            end_group = end_group.f_link.?;
        }

        top_group = first_group.b_link;
        if (top_group) |group| {
            group.f_link = end_group;
        } else {
            this_frame.first_group = end_group;
        }
        first_group.b_link = null;
        last_group.f_link = null;
        end_group.b_link = top_group;
    }
}

pub fn lineChangeLength(
    allocator: std.mem.Allocator,
    line: *types.LineHdrObject,
    new_length: isize,
) !void {
    const old_length = line.len();
    var adjusted_length = new_length;
    var new_str: ?*str_object.StrObject = null;

    if (adjusted_length > 0) {
        if (adjusted_length < types.max_str_len - 10) {
            adjusted_length = (@divTrunc(adjusted_length, 10) + 1) * 10;
        } else {
            adjusted_length = types.max_str_len;
        }

        if (line.str) |old_str| {
            new_str = try str_object.newStrObjectCopy(allocator, old_str, 1, @intCast(old_str.len()), adjusted_length);
        } else {
            new_str = try str_object.newBlankStrObject(allocator, @intCast(adjusted_length));
        }
    }

    if (line.group) |group| {
        group.frame.space_left += old_length - adjusted_length;
    }

    if (line.str) |old_str| {
        old_str.destroy();
    }
    line.str = new_str;
}

pub fn lineToNumber(line: *const types.LineHdrObject) isize {
    return line.group.?.first_line_num + line.offset_num;
}

pub fn lineFromNumber(frame: *const types.FrameObject, number: isize) ?*types.LineHdrObject {
    var this_group = frame.last_group orelse return null;

    if (number >= this_group.first_line_num + this_group.num_lines or number < 1) {
        return null;
    }
    while (this_group.first_line_num > number) {
        this_group = this_group.b_link orelse return null;
    }

    var this_line = this_group.first_line orelse return null;
    var line_nr: isize = 0;
    while (line_nr < number - this_group.first_line_num) : (line_nr += 1) {
        this_line = this_line.f_link orelse return null;
    }
    return this_line;
}

pub fn createContentFrame(
    allocator: std.mem.Allocator,
    contents: []const []const u8,
) !FrameFixture {
    if (contents.len == 0) {
        @panic("Must have at least one line");
    }

    const frame = try allocator.create(types.FrameObject);
    frame.* = .{
        .space_left = types.max_space,
        .space_limit = types.max_space,
        .scr_width = 80,
        .margin_left = 1,
        .margin_right = types.max_str_len,
    };

    const group = try allocator.create(types.GroupObject);
    group.* = .{
        .frame = frame,
        .first_line_num = 1,
        .num_lines = @intCast(contents.len),
    };

    const text_lines = try allocator.alloc(*types.LineHdrObject, contents.len);
    var prev_line: ?*types.LineHdrObject = null;
    var first_line: ?*types.LineHdrObject = null;
    for (contents, 0..) |content, index| {
        const line = try allocator.create(types.LineHdrObject);
        line.* = .{
            .group = group,
            .offset_num = @intCast(index),
            .used = @intCast(content.len),
            .str = try str_object.newBlankStrObject(allocator, types.max_str_len),
        };
        try line.str.?.assign(content);
        text_lines[index] = line;

        if (prev_line) |previous| {
            previous.f_link = line;
            line.b_link = previous;
        } else {
            first_line = line;
        }
        prev_line = line;
    }

    const null_line = try allocator.create(types.LineHdrObject);
    null_line.* = .{
        .group = group,
        .offset_num = @intCast(contents.len),
        .b_link = prev_line,
    };
    prev_line.?.f_link = null_line;

    group.first_line = first_line;
    group.last_line = null_line;
    frame.first_group = group;
    frame.last_group = group;
    try mark.markCreate(allocator, first_line.?, 1, &frame.dot);

    return .{
        .frame = frame,
        .content_lines = text_lines,
        .sentinel_line = null_line,
    };
}

pub fn setupLinkedLines(
    allocator: std.mem.Allocator,
    count: usize,
) !FrameFixture {
    const contents = try allocator.alloc([]const u8, count);
    defer allocator.free(contents);
    for (contents) |*entry| {
        entry.* = "";
    }
    return createContentFrame(allocator, contents);
}

pub fn setLineContent(line: *types.LineHdrObject, content: []const u8) !void {
    try line.str.?.assign(content);
    line.used = @intCast(content.len);
    if (line.len() > line.used) {
        line.str.?.fillN(' ', line.len() - line.used, line.used + 1);
    }
}

pub fn setSentinelDisplayContent(
    allocator: std.mem.Allocator,
    line: *types.LineHdrObject,
    prefix: []const u8,
    frame_name: []const u8,
) !void {
    const min_len = @as(isize, @intCast(prefix.len + types.name_len));
    if (line.len() < min_len) {
        try lineChangeLength(allocator, line, min_len);
    }
    if (line.str == null) {
        return error.MissingSentinelStorage;
    }

    const storage_len: isize = @intCast(line.len());
    line.str.?.fillCopyBytes(prefix, 1, storage_len, ' ');
    if (frame_name.len > 0) {
        line.str.?.fillCopyBytes(frame_name, @intCast(prefix.len + 1), storage_len - @as(isize, @intCast(prefix.len)), ' ');
    }
    line.used = 0;
}

pub fn getLineContent(line: ?*const types.LineHdrObject) []const u8 {
    if (line == null or line.?.str == null or line.?.used <= 0) {
        return "";
    }
    return line.?.str.?.slice(1, line.?.used);
}

pub fn getDisplayLineContent(line: ?*const types.LineHdrObject) []const u8 {
    if (line == null or line.?.str == null) {
        return "";
    }
    if (line.?.f_link == null) {
        const str = line.?.str.?;
        const trimmed_len = str.trimmedLen(' ', @intCast(str.len()));
        if (trimmed_len <= 0) {
            return "";
        }
        return str.slice(1, trimmed_len);
    }
    return getLineContent(line);
}

pub fn validateFrameShape(frame: *const types.FrameObject) !void {
    if (frame.first_group == null or frame.last_group == null) {
        return error.InvalidGroupPtr;
    }
    if (frame.first_group.?.b_link != null) {
        return error.InvalidBlink;
    }
    if (frame.last_group.?.f_link != null) {
        return error.InvalidBlink;
    }

    var prev_group: ?*types.GroupObject = null;
    var group = frame.first_group;
    while (group) |current_group| {
        if (current_group.b_link != prev_group) {
            return error.InvalidBlink;
        }
        if (current_group.frame != frame) {
            return error.InvalidFramePtr;
        }
        if (current_group.first_line == null or current_group.last_line == null) {
            return error.InvalidLinePtr;
        }
        var line = current_group.first_line.?;
        var prev_line: ?*types.LineHdrObject = if (prev_group) |group_before| group_before.last_line else null;
        var offset: isize = 0;
        while (true) {
            if (line.b_link != prev_line) {
                return error.InvalidBlink;
            }
            if (line.group != current_group) {
                return error.InvalidGroupPtr;
            }
            if (line.offset_num != offset) {
                return error.InvalidOffsetNr;
            }
            prev_line = line;
            if (line == current_group.last_line.?) {
                break;
            }
            line = line.f_link orelse return error.InvalidLinePtr;
            offset += 1;
        }

        prev_group = current_group;
        group = current_group.f_link;
    }
}

test "line eop create returns a single sentinel line group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const frame = try allocator.create(types.FrameObject);
    frame.* = .{};

    const group = try lineEOPCreate(allocator, frame);
    try std.testing.expect(group.frame == frame);
    try std.testing.expect(group.first_line == group.last_line);
    try std.testing.expectEqual(@as(isize, 1), group.first_line_num);
    try std.testing.expectEqual(@as(isize, 1), group.num_lines);
    try std.testing.expect(group.first_line.?.group == group);
    try std.testing.expect(group.first_line.?.f_link == null);
}

test "lines create links first to last with nil tail" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const range = try linesCreate(allocator, 3);
    try std.testing.expect(range.first != range.last);
    try std.testing.expect(range.first.b_link == null);
    try std.testing.expect(range.first.f_link != null);
    try std.testing.expect(range.last.f_link == null);
    try std.testing.expect(range.last.b_link != null);
}

test "line to number and from number follow group numbering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try createContentFrame(allocator, &[_][]const u8{ "alpha", "beta", "gamma" });
    try std.testing.expectEqual(@as(isize, 1), lineToNumber(fixture.content_lines[0]));
    try std.testing.expectEqual(@as(isize, 3), lineToNumber(fixture.content_lines[2]));
    try std.testing.expect(lineFromNumber(fixture.frame, 2) == fixture.content_lines[1]);
    try std.testing.expect(lineFromNumber(fixture.frame, 4) == null);
}

test "line change length quantizes and adjusts frame space" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try createContentFrame(allocator, &[_][]const u8{""});
    const line = fixture.content_lines[0];
    const original_space = fixture.frame.space_left;
    const old_length = line.len();

    try lineChangeLength(allocator, line, 13);
    try std.testing.expect(line.str != null);
    try std.testing.expectEqual(@as(isize, 20), line.len());
    try std.testing.expectEqual(original_space + old_length - 20, fixture.frame.space_left);
}

test "content frame helper creates sentinel null line and dot mark" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try createContentFrame(allocator, &[_][]const u8{ "one", "two" });
    try std.testing.expect(fixture.frame.dot != null);
    try std.testing.expect(fixture.frame.dot.?.line == fixture.content_lines[0]);
    try std.testing.expect(fixture.sentinel_line.f_link == null);
    try std.testing.expectEqual(@as(isize, 2), fixture.frame.last_group.?.num_lines);
    try std.testing.expect(fixture.frame.last_group.?.last_line == fixture.sentinel_line);
}

test "sentinel display content includes frame name while logical content stays empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try createContentFrame(allocator, &[_][]const u8{"one"});
    try setSentinelDisplayContent(allocator, fixture.sentinel_line, "<End of File>   ", "LUDWIG");

    try std.testing.expectEqualStrings("", getLineContent(fixture.sentinel_line));
    try std.testing.expectEqualStrings("<End of File>   LUDWIG", getDisplayLineContent(fixture.sentinel_line));
}
