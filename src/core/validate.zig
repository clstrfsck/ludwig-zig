const std = @import("std");
const line_ops = @import("line.zig");
const frame_ops = @import("frame.zig");
const mark_ops = @import("mark.zig");
const state = @import("state.zig");
const span_ops = @import("span.zig");
const types = @import("types.zig");

pub fn ValidateCommand(
    editor: *state.Editor,
    current_frame: *types.FrameObject,
    special_frames: *types.SpecialFrames,
) bool {
    _ = current_frame;
    if (special_frames.Oops == null or special_frames.Cmd == null or special_frames.Heap == null) {
        return false;
    }
    if (editor.FirstSpan == null) {
        return false;
    }

    var saw_oops = false;
    var saw_cmd = false;
    var saw_heap = false;
    var prev_span: ?*types.SpanObject = null;
    var span = editor.FirstSpan;
    while (span) |this_span| {
        if (this_span.BLink != prev_span) {
            return false;
        }
        if (this_span.MarkOne == null or this_span.MarkTwo == null) {
            return false;
        }
        if (this_span.Code != null and this_span.Code.?.Ref == 0) {
            return false;
        }

        if (this_span.Frame) |this_frame| {
            if (this_frame == special_frames.Cmd.?) saw_cmd = true;
            if (this_frame == special_frames.Oops.?) saw_oops = true;
            if (this_frame == special_frames.Heap.?) saw_heap = true;

            line_ops.validateFrameShape(this_frame) catch return false;
            if (this_frame.Dot == null) {
                return false;
            }
            if (this_frame.Dot.?.Line.Group == null or this_frame.Dot.?.Line.Group.?.Frame != this_frame) {
                return false;
            }
            for (this_frame.Marks) |maybe_mark| {
                if (maybe_mark) |mark| {
                    if (mark.Line.Group == null or mark.Line.Group.?.Frame != this_frame) {
                        return false;
                    }
                }
            }
            if (this_frame.ScrHeight <= 0) {
                return false;
            }
            if (editor.TerminalInfo.Height > 0 and this_frame.ScrHeight > editor.TerminalInfo.Height) {
                return false;
            }
            if (this_frame.ScrWidth <= 0) {
                return false;
            }
            if (editor.TerminalInfo.Width > 0 and this_frame.ScrWidth > editor.TerminalInfo.Width) {
                return false;
            }
            if (this_frame.Span != this_span) {
                return false;
            }
            if (this_frame.MarginLeft >= this_frame.MarginRight) {
                return false;
            }
            if (this_span.MarkOne.?.Line.Group == null or this_span.MarkTwo.?.Line.Group == null) {
                return false;
            }
            if (this_span.MarkOne.?.Line.Group.?.Frame != this_frame or this_span.MarkTwo.?.Line.Group.?.Frame != this_frame) {
                return false;
            }
        } else {
            if (this_span.MarkOne.?.Line.Group == null or this_span.MarkTwo.?.Line.Group == null) {
                return false;
            }
            if (this_span.MarkOne.?.Line.Group.?.Frame != this_span.MarkTwo.?.Line.Group.?.Frame) {
                return false;
            }
        }

        prev_span = this_span;
        span = this_span.FLink;
    }

    return saw_cmd and saw_oops and saw_heap;
}

fn makeSpecialFrame(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    current: *types.FrameObject,
    name: []const u8,
) !*types.FrameObject {
    const frame = (try frame_ops.FrameEdit(editor, allocator, current, name)).?;
    frame.Options.specialFrame = true;
    return frame;
}

test "validate command accepts healthy special frames and spans" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.TerminalInfo = .{ .Width = 160, .Height = 48 };
    const allocator = editor.allocator();

    const root_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const current = (try frame_ops.FrameEdit(&editor, allocator, root_fixture.frame, "MAIN")).?;
    const cmd = try makeSpecialFrame(&editor, allocator, current, "COMMAND");
    const oops = try makeSpecialFrame(&editor, allocator, current, "OOPS");
    const heap = try makeSpecialFrame(&editor, allocator, current, "HEAP");
    var special_frames: types.SpecialFrames = .{
        .Cmd = cmd,
        .Oops = oops,
        .Heap = heap,
    };

    var span_mark_one: ?*types.MarkObject = null;
    var span_mark_two: ?*types.MarkObject = null;
    try mark_ops.MarkCreate(allocator, current.FirstGroup.?.FirstLine.?, 1, &span_mark_one);
    try mark_ops.MarkCreate(allocator, current.LastGroup.?.LastLine.?, 1, &span_mark_two);
    try std.testing.expect(try span_ops.SpanCreate(&editor, allocator, "WORK", span_mark_one.?, span_mark_two.?));

    try std.testing.expect(ValidateCommand(&editor, current, &special_frames));
}

test "validate command rejects missing special frames" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.TerminalInfo = .{ .Width = 160, .Height = 48 };
    const allocator = editor.allocator();

    const root_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const current = (try frame_ops.FrameEdit(&editor, allocator, root_fixture.frame, "MAIN")).?;
    var special_frames: types.SpecialFrames = .{};
    try std.testing.expect(!ValidateCommand(&editor, current, &special_frames));
}

test "validate command rejects spans with marks in different frames" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.TerminalInfo = .{ .Width = 160, .Height = 48 };
    const allocator = editor.allocator();

    const root_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const current = (try frame_ops.FrameEdit(&editor, allocator, root_fixture.frame, "MAIN")).?;
    const other = (try frame_ops.FrameEdit(&editor, allocator, current, "OTHER")).?;
    const cmd = try makeSpecialFrame(&editor, allocator, current, "COMMAND");
    const oops = try makeSpecialFrame(&editor, allocator, current, "OOPS");
    const heap = try makeSpecialFrame(&editor, allocator, current, "HEAP");
    var special_frames: types.SpecialFrames = .{
        .Cmd = cmd,
        .Oops = oops,
        .Heap = heap,
    };

    const span = try allocator.create(types.SpanObject);
    var mark_one: ?*types.MarkObject = null;
    var mark_two: ?*types.MarkObject = null;
    try mark_ops.MarkCreate(allocator, current.FirstGroup.?.FirstLine.?, 1, &mark_one);
    try mark_ops.MarkCreate(allocator, other.FirstGroup.?.FirstLine.?, 1, &mark_two);
    span.* = .{
        .Name = "BROKEN",
        .MarkOne = mark_one,
        .MarkTwo = mark_two,
        .BLink = editor.FirstSpan,
    };
    if (editor.FirstSpan) |first| {
        first.FLink = span;
    } else {
        editor.FirstSpan = span;
    }

    try std.testing.expect(!ValidateCommand(&editor, current, &special_frames));
}
