const std = @import("std");
const mark_ops = @import("mark.zig");
const line_ops = @import("line.zig");
const str_object = @import("str_object.zig");
const types = @import("types.zig");

fn contains(char_set: *const [types.MaxSetRange + 1]bool, invert: bool, ch: u8) bool {
    const in_set = char_set[@intCast(ch)];
    return if (invert) !in_set else in_set;
}

pub fn searchForward(
    char_set: *const [types.MaxSetRange + 1]bool,
    invert: bool,
    line: ?*types.LineHdrObject,
    col: isize,
) struct { ?*types.LineHdrObject, isize } {
    var this_line = line;
    var start_col = col;
    while (this_line) |current_line| {
        var i = start_col;
        while (i <= current_line.Used) : (i += 1) {
            if (contains(char_set, invert, current_line.Str.?.get(i))) {
                return .{ current_line, i };
            }
        }
        if (contains(char_set, invert, ' ') and i == current_line.Used + 1) {
            return .{ current_line, i };
        }
        this_line = current_line.FLink;
        start_col = 1;
    }
    return .{ null, 0 };
}

pub fn searchBackward(
    char_set: *const [types.MaxSetRange + 1]bool,
    invert: bool,
    line: ?*types.LineHdrObject,
    col: isize,
    bridge: bool,
) struct { ?*types.LineHdrObject, isize } {
    var this_line = line;
    var start_col = col;
    while (this_line) |current_line| {
        if (current_line.Used < start_col) {
            if (contains(char_set, invert, ' ')) {
                return .{ current_line, start_col };
            }
            start_col = current_line.Used;
        }
        var j = start_col;
        while (j >= 1) : (j -= 1) {
            if (contains(char_set, invert, current_line.Str.?.get(j))) {
                return .{ current_line, j };
            }
            if (j == 1) break;
        }
        if (current_line.BLink) |back| {
            this_line = back;
            start_col = back.Used + 1;
        } else if (bridge) {
            return .{ current_line, start_col };
        } else {
            return .{ null, 0 };
        }
    }
    return .{ null, 0 };
}

fn buildCharSet(
    allocator: std.mem.Allocator,
    tpar: *types.TParObject,
) !*[types.MaxSetRange + 1]bool {
    const buffer = try allocator.create([types.MaxSetRange + 1]bool);
    buffer.* = [_]bool{false} ** (types.MaxSetRange + 1);
    const str = tpar.Str.?;
    var i: isize = 1;
    while (i <= tpar.Len) {
        const ch1 = str.get(i);
        var ch2 = ch1;
        i += 1;
        if (i + 2 <= tpar.Len and str.get(i) == '.' and str.get(i + 1) == '.') {
            ch2 = str.get(i + 2);
            i += 3;
        }
        var ch = ch1;
        while (ch <= ch2) : (ch += 1) {
            buffer[@intCast(ch)] = true;
            if (ch == 255) break;
        }
    }
    return buffer;
}

pub fn NextbridgeCommand(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    count: isize,
    tpar: *types.TParObject,
    bridge: bool,
) !bool {
    const char_set = try buildCharSet(allocator, tpar);
    defer allocator.destroy(char_set);

    var new_line = frame.Dot.?.Line;
    var new_col: isize = undefined;
    var count_mut = count;

    if (count_mut > 0) {
        new_col = frame.Dot.?.Col;
        if (!bridge) {
            new_col += 1;
        }
        while (true) {
            const result = searchForward(char_set, bridge, new_line, new_col);
            new_line = result.@"0" orelse return false;
            new_col = result.@"1";
            new_col += 1;
            count_mut -= 1;
            if (count_mut == 0) break;
        }
        new_col -= 1;
        try mark_ops.markCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkEquals]);
    } else if (count_mut < 0) {
        new_col = frame.Dot.?.Col - 1;
        if (!bridge) {
            new_col -= 1;
        }
        while (true) {
            const result = searchBackward(char_set, bridge, new_line, new_col, bridge);
            new_line = result.@"0" orelse return false;
            new_col = result.@"1";
            new_col -= 1;
            count_mut += 1;
            if (count_mut == 0) break;
        }
        new_col += 2;
        try mark_ops.markCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkEquals]);
    } else {
        try mark_ops.markCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkEquals]);
        return true;
    }

    try mark_ops.markCreate(allocator, new_line, new_col, &frame.Dot);
    return true;
}

test "search forward and backward scan across lines and eol space" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try line_ops.setupLinkedLines(allocator, 2);
    try line_ops.setLineContent(fixture.content_lines[0], "aaa");
    try line_ops.setLineContent(fixture.content_lines[1], "bbb");

    const b = try str_object.newStrObjectFrom(allocator, "b");
    var b_tpar = types.TParObject{ .Str = b, .Len = 1 };
    const forward_set = try buildCharSet(allocator, &b_tpar);
    defer allocator.destroy(forward_set);
    const forward = searchForward(forward_set, false, fixture.content_lines[0], 1);
    try std.testing.expect(forward.@"0" == fixture.content_lines[1]);
    try std.testing.expectEqual(@as(isize, 1), forward.@"1");

    const sp = try str_object.newStrObjectFrom(allocator, " ");
    var sp_tpar = types.TParObject{ .Str = sp, .Len = 1 };
    const space_set = try buildCharSet(allocator, &sp_tpar);
    defer allocator.destroy(space_set);
    const backward = searchBackward(space_set, false, fixture.content_lines[0], 5, false);
    try std.testing.expect(backward.@"0" == fixture.content_lines[0]);
    try std.testing.expectEqual(@as(isize, 5), backward.@"1");
}

test "nextbridge command supports forward backward bridge and ranges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const forward_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"hello world"});
    const space = try str_object.newStrObjectFrom(allocator, " ");
    var space_tpar = types.TParObject{ .Str = space, .Len = 1 };
    try std.testing.expect(try NextbridgeCommand(allocator, forward_fixture.frame, 1, &space_tpar, false));
    try std.testing.expectEqual(@as(isize, 6), forward_fixture.frame.Dot.?.Col);
    try std.testing.expectEqual(@as(isize, 1), forward_fixture.frame.Marks[types.MarkEquals].?.Col);

    try mark_ops.markCreate(allocator, forward_fixture.content_lines[0], 8, &forward_fixture.frame.Dot);
    try std.testing.expect(try NextbridgeCommand(allocator, forward_fixture.frame, -1, &space_tpar, false));
    try std.testing.expectEqual(@as(isize, 7), forward_fixture.frame.Dot.?.Col);

    const bridge_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"hello"});
    try mark_ops.markCreate(allocator, bridge_fixture.content_lines[0], 2, &bridge_fixture.frame.Dot);
    const vowels = try str_object.newStrObjectFrom(allocator, "aeiou");
    var vowels_tpar = types.TParObject{ .Str = vowels, .Len = 5 };
    try std.testing.expect(try NextbridgeCommand(allocator, bridge_fixture.frame, 1, &vowels_tpar, true));
    try std.testing.expectEqual(@as(isize, 3), bridge_fixture.frame.Dot.?.Col);

    const range_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"HELLO world"});
    const lower = try str_object.newStrObjectFrom(allocator, "a..z");
    var lower_tpar = types.TParObject{ .Str = lower, .Len = 4 };
    try std.testing.expect(try NextbridgeCommand(allocator, range_fixture.frame, 1, &lower_tpar, false));
    try std.testing.expectEqual(@as(isize, 7), range_fixture.frame.Dot.?.Col);
}
