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

pub fn LineEOPCreate(
    allocator: std.mem.Allocator,
    inframe: *types.FrameObject,
) !*types.GroupObject {
    const new_line = try allocator.create(types.LineHdrObject);
    new_line.* = .{};

    const new_group = try allocator.create(types.GroupObject);
    new_group.* = .{
        .Frame = inframe,
        .FirstLine = new_line,
        .LastLine = new_line,
        .FirstLineNr = 1,
        .NrLines = 1,
    };
    new_line.Group = new_group;

    return new_group;
}

pub fn LinesCreate(
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
            .BLink = prev_line,
        };
        if (top_line == null) {
            top_line = this_line;
        }
        if (prev_line) |line| {
            line.FLink = this_line;
        }
        prev_line = this_line;
        last_line = this_line;
    }

    return .{
        .first = top_line.?,
        .last = last_line.?,
    };
}

pub fn LinesInject(
    allocator: std.mem.Allocator,
    first_line: *types.LineHdrObject,
    last_line: *types.LineHdrObject,
    before_line: *types.LineHdrObject,
) !void {
    var nr_new_lines: isize = 0;
    var space: isize = 0;
    var scan_line: ?*types.LineHdrObject = first_line;
    while (scan_line) |line| {
        space += line.Len();
        nr_new_lines += 1;
        scan_line = line.FLink;
    }

    const top_line = before_line.BLink;
    const end_group = before_line.Group.?;
    const top_group = end_group.BLink;
    const this_frame = end_group.Frame;

    const nr_free_lines_end = types.MaxGroupLines - end_group.NrLines;
    const nr_free_lines_top = if (top_group) |group| types.MaxGroupLines - group.NrLines else 0;
    const nr_free_lines = nr_free_lines_end + nr_free_lines_top;
    var line_nr = end_group.FirstLineNr;

    var adjust_group: ?*types.GroupObject = null;
    if (nr_new_lines > nr_free_lines) {
        const nr_new_groups = @divFloor(nr_new_lines - nr_free_lines - 1, types.MaxGroupLines) + 1;
        var first_group: ?*types.GroupObject = null;
        var last_group: ?*types.GroupObject = null;

        var group_nr: isize = 1;
        while (group_nr <= nr_new_groups) : (group_nr += 1) {
            const this_group = try allocator.create(types.GroupObject);
            this_group.* = .{
                .BLink = last_group,
                .Frame = this_frame,
                .FirstLineNr = line_nr,
            };

            if (first_group == null) {
                first_group = this_group;
            }
            if (last_group) |group| {
                group.FLink = this_group;
            }
            last_group = this_group;
        }

        last_group.?.FLink = end_group;
        end_group.BLink = last_group;
        if (top_group) |group| {
            group.FLink = first_group.?;
            adjust_group = group;
        } else {
            this_frame.FirstGroup = first_group.?;
            adjust_group = first_group.?;
        }
        first_group.?.BLink = top_group;
    } else if (nr_new_lines > nr_free_lines_end) {
        adjust_group = top_group.?;
    } else {
        adjust_group = end_group;
    }

    last_line.FLink = before_line;
    before_line.BLink = last_line;
    if (before_line.OffsetNr == 0) {
        end_group.FirstLine = first_line;
    }
    if (top_line) |line| {
        line.FLink = first_line;
    }
    first_line.BLink = top_line;

    var nr_lines_to_adjust = nr_new_lines;
    var adjust_line: *types.LineHdrObject = undefined;

    if (nr_new_lines > nr_free_lines_end) {
        adjust_line = end_group.FirstLine.?;
        nr_lines_to_adjust += before_line.OffsetNr;
        end_group.NrLines = 0;
    } else {
        adjust_line = first_line;
        end_group.NrLines = before_line.OffsetNr;
    }
    const end_group_last_line = end_group.LastLine.?;

    while (nr_lines_to_adjust > 0) {
        const group = adjust_group.?;
        const nr_lines_to_adjust_here = @min(types.MaxGroupLines - group.NrLines, nr_lines_to_adjust);
        if (group.NrLines == 0) {
            group.FirstLine = adjust_line;
            group.FirstLineNr = line_nr;
        }

        var offset = group.NrLines;
        while (offset < group.NrLines + nr_lines_to_adjust_here) : (offset += 1) {
            adjust_line.Group = group;
            adjust_line.OffsetNr = offset;
            adjust_line = adjust_line.FLink.?;
        }

        group.LastLine = adjust_line.BLink;
        group.NrLines += nr_lines_to_adjust_here;
        line_nr = group.FirstLineNr + group.NrLines;
        nr_lines_to_adjust -= nr_lines_to_adjust_here;
        adjust_group = group.FLink;
    }

    const next_group_first_line = end_group_last_line.FLink;
    var offset = end_group.NrLines;
    var tail_line: ?*types.LineHdrObject = adjust_line;
    while (true) {
        tail_line.?.OffsetNr = offset;
        offset += 1;
        tail_line = tail_line.?.FLink;
        if (tail_line == next_group_first_line) {
            break;
        }
    }

    end_group.LastLine = end_group_last_line;
    if (adjust_group == end_group) {
        end_group.FirstLineNr = line_nr;
        end_group.FirstLine = before_line;
    }
    end_group.NrLines = offset;

    var shift_group = end_group.FLink;
    while (shift_group) |group| {
        group.FirstLineNr += nr_new_lines;
        shift_group = group.FLink;
    }

    this_frame.SpaceLeft -= space;
}

pub fn LinesExtract(
    first_line: *types.LineHdrObject,
    last_line: *types.LineHdrObject,
) void {
    const top_line = first_line.BLink;
    const end_line = last_line.FLink.?;

    var first_group = first_line.Group.?;
    var last_group = last_line.Group.?;
    var top_group: ?*types.GroupObject = null;
    if (top_line) |line| {
        top_group = line.Group.?;
    }
    var end_group = end_line.Group.?;
    const this_frame = end_group.Frame;

    const first_line_offset_nr = first_line.OffsetNr;
    const first_line_nr = first_group.FirstLineNr + first_line_offset_nr;
    var nr_lines_to_remove = last_group.FirstLineNr + last_line.OffsetNr - first_line_nr + 1;

    if (top_line) |line| {
        line.FLink = end_line;
    }
    first_line.BLink = null;
    last_line.FLink = null;
    end_line.BLink = top_line;

    var space: isize = 0;
    var this_line: ?*types.LineHdrObject = first_line;
    var line_nr: isize = 1;
    while (line_nr <= nr_lines_to_remove) : (line_nr += 1) {
        space += this_line.?.Len();
        this_line = this_line.?.FLink;
    }
    this_frame.SpaceLeft += space;

    if (top_group != end_group) {
        if (top_group) |group| {
            group.LastLine = top_line;
        }
        end_group.FirstLine = end_line;
        end_group.FirstLineNr = first_line_nr;
    }

    var renumber_group = end_group.FLink;
    while (renumber_group) |group| {
        group.FirstLineNr -= nr_lines_to_remove;
        renumber_group = group.FLink;
    }

    if (first_group == top_group) {
        nr_lines_to_remove -= first_group.NrLines - first_line_offset_nr;
        first_group.NrLines = first_line_offset_nr;
        if (first_group != last_group) {
            first_group = first_group.FLink.?;
        }
    }

    var consume_group: ?*types.GroupObject = first_group;
    while (nr_lines_to_remove > 0) {
        const group = consume_group.?;
        nr_lines_to_remove -= group.NrLines;
        group.NrLines = 0;
        consume_group = group.FLink;
    }

    if (nr_lines_to_remove < 0) {
        var offset: isize = undefined;
        if (top_group == end_group) {
            offset = first_line_offset_nr;
            end_group.NrLines = offset - nr_lines_to_remove;
        } else {
            offset = 0;
            end_group.NrLines = -nr_lines_to_remove;
        }

        this_line = end_line;
        while (offset < end_group.NrLines) : (offset += 1) {
            this_line.?.OffsetNr = offset;
            this_line = this_line.?.FLink;
        }
    }

    if (first_group.NrLines == 0) {
        last_group = first_group;
        end_group = last_group.FLink.?;
        while (end_group.NrLines == 0) {
            last_group = end_group;
            end_group = end_group.FLink.?;
        }

        top_group = first_group.BLink;
        if (top_group) |group| {
            group.FLink = end_group;
        } else {
            this_frame.FirstGroup = end_group;
        }
        first_group.BLink = null;
        last_group.FLink = null;
        end_group.BLink = top_group;
    }
}

pub fn LineChangeLength(
    allocator: std.mem.Allocator,
    line: *types.LineHdrObject,
    new_length: isize,
) !void {
    const old_length = line.Len();
    var adjusted_length = new_length;
    var new_str: ?*str_object.StrObject = null;

    if (adjusted_length > 0) {
        if (adjusted_length < types.MaxStrLen - 10) {
            adjusted_length = (@divTrunc(adjusted_length, 10) + 1) * 10;
        } else {
            adjusted_length = types.MaxStrLen;
        }

        if (line.Str) |old_str| {
            new_str = try str_object.NewStrObjectCopy(allocator, old_str, 1, @intCast(old_str.Len()), adjusted_length);
        } else {
            new_str = try str_object.NewBlankStrObject(allocator, @intCast(adjusted_length));
        }
    }

    if (line.Group) |group| {
        group.Frame.SpaceLeft += old_length - adjusted_length;
    }

    if (line.Str) |old_str| {
        old_str.destroy();
    }
    line.Str = new_str;
}

pub fn LineToNumber(line: *const types.LineHdrObject) isize {
    return line.Group.?.FirstLineNr + line.OffsetNr;
}

pub fn LineFromNumber(frame: *const types.FrameObject, number: isize) ?*types.LineHdrObject {
    var this_group = frame.LastGroup orelse return null;

    if (number >= this_group.FirstLineNr + this_group.NrLines or number < 1) {
        return null;
    }
    while (this_group.FirstLineNr > number) {
        this_group = this_group.BLink orelse return null;
    }

    var this_line = this_group.FirstLine orelse return null;
    var line_nr: isize = 0;
    while (line_nr < number - this_group.FirstLineNr) : (line_nr += 1) {
        this_line = this_line.FLink orelse return null;
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
        .SpaceLeft = types.MaxSpace,
        .SpaceLimit = types.MaxSpace,
        .ScrWidth = 80,
        .MarginLeft = 1,
        .MarginRight = types.MaxStrLen,
    };

    const group = try allocator.create(types.GroupObject);
    group.* = .{
        .Frame = frame,
        .FirstLineNr = 1,
        .NrLines = @intCast(contents.len),
    };

    const text_lines = try allocator.alloc(*types.LineHdrObject, contents.len);
    var prev_line: ?*types.LineHdrObject = null;
    var first_line: ?*types.LineHdrObject = null;
    for (contents, 0..) |content, index| {
        const line = try allocator.create(types.LineHdrObject);
        line.* = .{
            .Group = group,
            .OffsetNr = @intCast(index),
            .Used = @intCast(content.len),
            .Str = try str_object.NewBlankStrObject(allocator, types.MaxStrLen),
        };
        try line.Str.?.Assign(content);
        text_lines[index] = line;

        if (prev_line) |previous| {
            previous.FLink = line;
            line.BLink = previous;
        } else {
            first_line = line;
        }
        prev_line = line;
    }

    const null_line = try allocator.create(types.LineHdrObject);
    null_line.* = .{
        .Group = group,
        .OffsetNr = @intCast(contents.len),
        .BLink = prev_line,
    };
    prev_line.?.FLink = null_line;

    group.FirstLine = first_line;
    group.LastLine = null_line;
    frame.FirstGroup = group;
    frame.LastGroup = group;
    try mark.MarkCreate(allocator, first_line.?, 1, &frame.Dot);

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
    try line.Str.?.Assign(content);
    line.Used = @intCast(content.len);
    if (line.Len() > line.Used) {
        line.Str.?.FillN(' ', line.Len() - line.Used, line.Used + 1);
    }
}

pub fn setSentinelDisplayContent(
    allocator: std.mem.Allocator,
    line: *types.LineHdrObject,
    prefix: []const u8,
    frame_name: []const u8,
) !void {
    const min_len = @as(isize, @intCast(prefix.len + types.NameLen));
    if (line.Len() < min_len) {
        try LineChangeLength(allocator, line, min_len);
    }
    if (line.Str == null) {
        return error.MissingSentinelStorage;
    }

    const storage_len: isize = @intCast(line.Len());
    line.Str.?.FillCopyBytes(prefix, 1, storage_len, ' ');
    if (frame_name.len > 0) {
        line.Str.?.FillCopyBytes(frame_name, @intCast(prefix.len + 1), storage_len - @as(isize, @intCast(prefix.len)), ' ');
    }
    line.Used = 0;
}

pub fn getLineContent(line: ?*const types.LineHdrObject) []const u8 {
    if (line == null or line.?.Str == null or line.?.Used <= 0) {
        return "";
    }
    return line.?.Str.?.Slice(1, line.?.Used);
}

pub fn getDisplayLineContent(line: ?*const types.LineHdrObject) []const u8 {
    if (line == null or line.?.Str == null) {
        return "";
    }
    if (line.?.FLink == null) {
        const str = line.?.Str.?;
        const trimmed_len = str.TrimmedLen(' ', @intCast(str.Len()));
        if (trimmed_len <= 0) {
            return "";
        }
        return str.Slice(1, trimmed_len);
    }
    return getLineContent(line);
}

pub fn validateFrameShape(frame: *const types.FrameObject) !void {
    if (frame.FirstGroup == null or frame.LastGroup == null) {
        return error.InvalidGroupPtr;
    }
    if (frame.FirstGroup.?.BLink != null) {
        return error.InvalidBlink;
    }
    if (frame.LastGroup.?.FLink != null) {
        return error.InvalidBlink;
    }

    var prev_group: ?*types.GroupObject = null;
    var group = frame.FirstGroup;
    while (group) |current_group| {
        if (current_group.BLink != prev_group) {
            return error.InvalidBlink;
        }
        if (current_group.Frame != frame) {
            return error.InvalidFramePtr;
        }
        if (current_group.FirstLine == null or current_group.LastLine == null) {
            return error.InvalidLinePtr;
        }
        var line = current_group.FirstLine.?;
        var prev_line: ?*types.LineHdrObject = if (prev_group) |group_before| group_before.LastLine else null;
        var offset: isize = 0;
        while (true) {
            if (line.BLink != prev_line) {
                return error.InvalidBlink;
            }
            if (line.Group != current_group) {
                return error.InvalidGroupPtr;
            }
            if (line.OffsetNr != offset) {
                return error.InvalidOffsetNr;
            }
            prev_line = line;
            if (line == current_group.LastLine.?) {
                break;
            }
            line = line.FLink orelse return error.InvalidLinePtr;
            offset += 1;
        }

        prev_group = current_group;
        group = current_group.FLink;
    }
}

test "line eop create returns a single sentinel line group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const frame = try allocator.create(types.FrameObject);
    frame.* = .{};

    const group = try LineEOPCreate(allocator, frame);
    try std.testing.expect(group.Frame == frame);
    try std.testing.expect(group.FirstLine == group.LastLine);
    try std.testing.expectEqual(@as(isize, 1), group.FirstLineNr);
    try std.testing.expectEqual(@as(isize, 1), group.NrLines);
    try std.testing.expect(group.FirstLine.?.Group == group);
    try std.testing.expect(group.FirstLine.?.FLink == null);
}

test "lines create links first to last with nil tail" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const range = try LinesCreate(allocator, 3);
    try std.testing.expect(range.first != range.last);
    try std.testing.expect(range.first.BLink == null);
    try std.testing.expect(range.first.FLink != null);
    try std.testing.expect(range.last.FLink == null);
    try std.testing.expect(range.last.BLink != null);
}

test "line to number and from number follow group numbering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try createContentFrame(allocator, &[_][]const u8{ "alpha", "beta", "gamma" });
    try std.testing.expectEqual(@as(isize, 1), LineToNumber(fixture.content_lines[0]));
    try std.testing.expectEqual(@as(isize, 3), LineToNumber(fixture.content_lines[2]));
    try std.testing.expect(LineFromNumber(fixture.frame, 2) == fixture.content_lines[1]);
    try std.testing.expect(LineFromNumber(fixture.frame, 4) == null);
}

test "line change length quantizes and adjusts frame space" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try createContentFrame(allocator, &[_][]const u8{""});
    const line = fixture.content_lines[0];
    const original_space = fixture.frame.SpaceLeft;
    const old_length = line.Len();

    try LineChangeLength(allocator, line, 13);
    try std.testing.expect(line.Str != null);
    try std.testing.expectEqual(@as(isize, 20), line.Len());
    try std.testing.expectEqual(original_space + old_length - 20, fixture.frame.SpaceLeft);
}

test "content frame helper creates sentinel null line and dot mark" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try createContentFrame(allocator, &[_][]const u8{ "one", "two" });
    try std.testing.expect(fixture.frame.Dot != null);
    try std.testing.expect(fixture.frame.Dot.?.Line == fixture.content_lines[0]);
    try std.testing.expect(fixture.sentinel_line.FLink == null);
    try std.testing.expectEqual(@as(isize, 2), fixture.frame.LastGroup.?.NrLines);
    try std.testing.expect(fixture.frame.LastGroup.?.LastLine == fixture.sentinel_line);
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
