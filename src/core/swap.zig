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
    const this_line = frame.Dot.?.Line;
    const dot_col = frame.Dot.?.Col;
    const next_line = this_line.FLink orelse return false;

    var top_mark: ?*types.MarkObject = null;
    var end_mark: ?*types.MarkObject = null;
    var dest_mark: ?*types.MarkObject = null;
    defer mark_ops.markDestroy(allocator, &top_mark);
    defer mark_ops.markDestroy(allocator, &end_mark);
    defer mark_ops.markDestroy(allocator, &dest_mark);

    var dest_line: *types.LineHdrObject = undefined;
    switch (rept) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            dest_line = next_line;
            var i: isize = 1;
            while (i <= count) : (i += 1) {
                dest_line = dest_line.FLink orelse return false;
            }
        },
        .LeadParamMinus, .LeadParamNInt => {
            dest_line = this_line;
            var i: isize = -1;
            while (i >= count) : (i -= 1) {
                dest_line = dest_line.BLink orelse return false;
            }
        },
        .LeadParamPIndef => dest_line = frame.LastGroup.?.LastLine.?,
        .LeadParamNIndef => dest_line = frame.FirstGroup.?.FirstLine.?,
        .LeadParamMarker => {
            const slot: usize = @intCast(count);
            dest_line = frame.Marks[slot].?.Line;
        },
    }

    try mark_ops.markCreate(allocator, this_line, 1, &top_mark);
    try mark_ops.markCreate(allocator, next_line, 1, &end_mark);
    try mark_ops.markCreate(allocator, dest_line, 1, &dest_mark);
    if (!try text.textMove(allocator, false, 1, top_mark.?, end_mark.?, dest_mark.?, &frame.Dot, &top_mark)) {
        return false;
    }
    frame.TextModified = true;
    frame.Dot.?.Col = dot_col;
    try mark_ops.markCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkModified]);
    return true;
}

fn collectLineContents(
    allocator: std.mem.Allocator,
    start: *types.LineHdrObject,
) ![]const []const u8 {
    var results: std.ArrayList([]const u8) = .{};
    defer results.deinit(allocator);
    var line: ?*types.LineHdrObject = start;
    while (line != null and line.?.FLink != null) {
        try results.append(allocator, try allocator.dupe(u8, line_ops.getLineContent(line)));
        line = line.?.FLink;
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
    forward_fixture.frame.Dot = try allocator.create(types.MarkObject);
    forward_fixture.frame.Dot.?.* = .{ .Line = forward_fixture.content_lines[0], .Col = 1 };
    try std.testing.expect(try swapLine(allocator, forward_fixture.frame, .LeadParamNone, 1));
    var contents = try collectLineContents(allocator, forward_fixture.frame.FirstGroup.?.FirstLine.?);
    try std.testing.expectEqualStrings("second", contents[0]);
    try std.testing.expectEqualStrings("first", contents[1]);

    const backward_fixture = try line_ops.setupLinkedLines(allocator, 5);
    try line_ops.setLineContent(backward_fixture.content_lines[0], "first");
    try line_ops.setLineContent(backward_fixture.content_lines[1], "second");
    try line_ops.setLineContent(backward_fixture.content_lines[2], "third");
    try line_ops.setLineContent(backward_fixture.content_lines[3], "fourth");
    try line_ops.setLineContent(backward_fixture.content_lines[4], "fifth");
    backward_fixture.frame.Dot = try allocator.create(types.MarkObject);
    backward_fixture.frame.Dot.?.* = .{ .Line = backward_fixture.content_lines[3], .Col = 1 };
    try std.testing.expect(try swapLine(allocator, backward_fixture.frame, .LeadParamNInt, -1));
    contents = try collectLineContents(allocator, backward_fixture.frame.FirstGroup.?.FirstLine.?);
    try std.testing.expectEqualStrings("fourth", contents[2]);
    try std.testing.expect(backward_fixture.frame.TextModified);

    const pindef_fixture = try line_ops.setupLinkedLines(allocator, 5);
    try line_ops.setLineContent(pindef_fixture.content_lines[0], "first");
    try line_ops.setLineContent(pindef_fixture.content_lines[1], "second");
    try line_ops.setLineContent(pindef_fixture.content_lines[2], "third");
    try line_ops.setLineContent(pindef_fixture.content_lines[3], "fourth");
    try line_ops.setLineContent(pindef_fixture.content_lines[4], "fifth");
    pindef_fixture.frame.Dot = try allocator.create(types.MarkObject);
    pindef_fixture.frame.Dot.?.* = .{ .Line = pindef_fixture.content_lines[0], .Col = 1 };
    try std.testing.expect(try swapLine(allocator, pindef_fixture.frame, .LeadParamPIndef, 0));
    contents = try collectLineContents(allocator, pindef_fixture.frame.FirstGroup.?.FirstLine.?);
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
    fixture.frame.Dot = try allocator.create(types.MarkObject);
    fixture.frame.Dot.?.* = .{ .Line = fixture.content_lines[0], .Col = 7 };
    try mark_ops.markCreate(allocator, fixture.content_lines[3], 1, &fixture.frame.Marks[types.MarkEquals]);

    try std.testing.expect(try swapLine(allocator, fixture.frame, .LeadParamMarker, types.MarkEquals));
    try std.testing.expectEqual(@as(isize, 7), fixture.frame.Dot.?.Col);
    try std.testing.expect(fixture.frame.Marks[types.MarkModified] != null);
}
