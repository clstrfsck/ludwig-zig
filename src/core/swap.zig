const std = @import("std");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const text = @import("text.zig");
const types = @import("types.zig");

pub fn swapLine(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    const this_line = frame.dot.?.line;
    const dot_col = frame.dot.?.col;
    const next_line = this_line.f_link orelse return false;

    var top_mark: ?*types.MarkObject = null;
    var end_mark: ?*types.MarkObject = null;
    var dest_mark: ?*types.MarkObject = null;
    defer mark_ops.markDestroy(allocator, &top_mark);
    defer mark_ops.markDestroy(allocator, &end_mark);
    defer mark_ops.markDestroy(allocator, &dest_mark);

    var dest_line: *types.LineHdrObject = undefined;
    switch (rept) {
        .lead_param_none, .lead_param_plus, .lead_param_p_int => {
            dest_line = next_line;
            var i: isize = 1;
            while (i <= count) : (i += 1) {
                dest_line = dest_line.f_link orelse return false;
            }
        },
        .lead_param_minus, .lead_param_n_int => {
            dest_line = this_line;
            var i: isize = -1;
            while (i >= count) : (i -= 1) {
                dest_line = dest_line.b_link orelse return false;
            }
        },
        .lead_param_p_indef => dest_line = frame.last_group.?.last_line.?,
        .lead_param_n_indef => dest_line = frame.first_group.?.first_line.?,
        .lead_param_marker => {
            const slot: usize = @intCast(count);
            dest_line = frame.marks[slot].?.line;
        },
    }

    try mark_ops.markCreate(allocator, this_line, 1, &top_mark);
    try mark_ops.markCreate(allocator, next_line, 1, &end_mark);
    try mark_ops.markCreate(allocator, dest_line, 1, &dest_mark);
    if (!try text.textMove(allocator, false, 1, top_mark.?, end_mark.?, dest_mark.?, &frame.dot, &top_mark)) {
        return false;
    }
    frame.text_modified = true;
    frame.dot.?.col = dot_col;
    try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col, &frame.marks[types.mark_modified]);
    return true;
}

fn collectLineContents(
    allocator: std.mem.Allocator,
    start: *types.LineHdrObject,
) ![]const []const u8 {
    var results: std.ArrayList([]const u8) = .{};
    defer results.deinit(allocator);
    var line: ?*types.LineHdrObject = start;
    while (line != null and line.?.f_link != null) {
        try results.append(allocator, try allocator.dupe(u8, line_ops.getLineContent(line)));
        line = line.?.f_link;
    }
    return results.toOwnedSlice(allocator);
}

test "swap line handles forward backward and indefinite moves" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const forward_fixture = try line_ops.setupLinkedLines(allocator, 5);
    try line_ops.setLineContent(forward_fixture.content_lines[0], "first");
    try line_ops.setLineContent(forward_fixture.content_lines[1], "second");
    try line_ops.setLineContent(forward_fixture.content_lines[2], "third");
    try line_ops.setLineContent(forward_fixture.content_lines[3], "fourth");
    try line_ops.setLineContent(forward_fixture.content_lines[4], "fifth");
    forward_fixture.frame.dot = try allocator.create(types.MarkObject);
    forward_fixture.frame.dot.?.* = .{ .line = forward_fixture.content_lines[0], .col = 1 };
    try std.testing.expect(try swapLine(allocator, forward_fixture.frame, .lead_param_none, 1));
    var contents = try collectLineContents(allocator, forward_fixture.frame.first_group.?.first_line.?);
    try std.testing.expectEqualStrings("second", contents[0]);
    try std.testing.expectEqualStrings("first", contents[1]);

    const backward_fixture = try line_ops.setupLinkedLines(allocator, 5);
    try line_ops.setLineContent(backward_fixture.content_lines[0], "first");
    try line_ops.setLineContent(backward_fixture.content_lines[1], "second");
    try line_ops.setLineContent(backward_fixture.content_lines[2], "third");
    try line_ops.setLineContent(backward_fixture.content_lines[3], "fourth");
    try line_ops.setLineContent(backward_fixture.content_lines[4], "fifth");
    backward_fixture.frame.dot = try allocator.create(types.MarkObject);
    backward_fixture.frame.dot.?.* = .{ .line = backward_fixture.content_lines[3], .col = 1 };
    try std.testing.expect(try swapLine(allocator, backward_fixture.frame, .lead_param_n_int, -1));
    contents = try collectLineContents(allocator, backward_fixture.frame.first_group.?.first_line.?);
    try std.testing.expectEqualStrings("fourth", contents[2]);
    try std.testing.expect(backward_fixture.frame.text_modified);

    const pindef_fixture = try line_ops.setupLinkedLines(allocator, 5);
    try line_ops.setLineContent(pindef_fixture.content_lines[0], "first");
    try line_ops.setLineContent(pindef_fixture.content_lines[1], "second");
    try line_ops.setLineContent(pindef_fixture.content_lines[2], "third");
    try line_ops.setLineContent(pindef_fixture.content_lines[3], "fourth");
    try line_ops.setLineContent(pindef_fixture.content_lines[4], "fifth");
    pindef_fixture.frame.dot = try allocator.create(types.MarkObject);
    pindef_fixture.frame.dot.?.* = .{ .line = pindef_fixture.content_lines[0], .col = 1 };
    try std.testing.expect(try swapLine(allocator, pindef_fixture.frame, .lead_param_p_indef, 0));
    contents = try collectLineContents(allocator, pindef_fixture.frame.first_group.?.first_line.?);
    try std.testing.expectEqualStrings("first", contents[contents.len - 1]);
}

test "swap line supports marker destination and preserves dot column" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try line_ops.setupLinkedLines(allocator, 5);
    try line_ops.setLineContent(fixture.content_lines[0], "first");
    try line_ops.setLineContent(fixture.content_lines[1], "second");
    try line_ops.setLineContent(fixture.content_lines[2], "third");
    try line_ops.setLineContent(fixture.content_lines[3], "fourth");
    try line_ops.setLineContent(fixture.content_lines[4], "fifth");
    fixture.frame.dot = try allocator.create(types.MarkObject);
    fixture.frame.dot.?.* = .{ .line = fixture.content_lines[0], .col = 7 };
    try mark_ops.markCreate(allocator, fixture.content_lines[3], 1, &fixture.frame.marks[types.mark_equals]);

    try std.testing.expect(try swapLine(allocator, fixture.frame, .lead_param_marker, types.mark_equals));
    try std.testing.expectEqual(@as(isize, 7), fixture.frame.dot.?.col);
    try std.testing.expect(fixture.frame.marks[types.mark_modified] != null);
}
