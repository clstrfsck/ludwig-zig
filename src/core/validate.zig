const std = @import("std");
const line_ops = @import("line.zig");
const frame_ops = @import("frame.zig");
const mark_ops = @import("mark.zig");
const state = @import("state.zig");
const span_ops = @import("span.zig");
const types = @import("types.zig");

pub fn validateCommand(
    editor: *state.Editor,
    current_frame: *types.FrameObject,
    special_frames: *types.SpecialFrames,
) bool {
    _ = current_frame;
    if (special_frames.Oops == null or special_frames.Cmd == null or special_frames.Heap == null) {
        return false;
    }
    if (editor.first_span == null) {
        return false;
    }

    var saw_oops = false;
    var saw_cmd = false;
    var saw_heap = false;
    var prev_span: ?*types.SpanObject = null;
    var span = editor.first_span;
    while (span) |this_span| {
        if (this_span.b_link != prev_span) {
            return false;
        }
        if (this_span.mark_one == null or this_span.mark_two == null) {
            return false;
        }
        if (this_span.code != null and this_span.code.?.Ref == 0) {
            return false;
        }

        if (this_span.frame) |this_frame| {
            if (this_frame == special_frames.Cmd.?) saw_cmd = true;
            if (this_frame == special_frames.Oops.?) saw_oops = true;
            if (this_frame == special_frames.Heap.?) saw_heap = true;

            line_ops.validateFrameShape(this_frame) catch return false;
            if (this_frame.dot == null) {
                return false;
            }
            if (this_frame.dot.?.Line.group == null or this_frame.dot.?.Line.group.?.frame != this_frame) {
                return false;
            }
            for (this_frame.marks) |maybe_mark| {
                if (maybe_mark) |mark| {
                    if (mark.Line.group == null or mark.Line.group.?.frame != this_frame) {
                        return false;
                    }
                }
            }
            if (this_frame.scr_height <= 0) {
                return false;
            }
            if (editor.terminal_info.height > 0 and this_frame.scr_height > editor.terminal_info.height) {
                return false;
            }
            if (this_frame.scr_width <= 0) {
                return false;
            }
            if (editor.terminal_info.width > 0 and this_frame.scr_width > editor.terminal_info.width) {
                return false;
            }
            if (this_frame.span != this_span) {
                return false;
            }
            if (this_frame.margin_left >= this_frame.margin_right) {
                return false;
            }
            if (this_span.mark_one.?.Line.group == null or this_span.mark_two.?.Line.group == null) {
                return false;
            }
            if (this_span.mark_one.?.Line.group.?.frame != this_frame or this_span.mark_two.?.Line.group.?.frame != this_frame) {
                return false;
            }
        } else {
            if (this_span.mark_one.?.Line.group == null or this_span.mark_two.?.Line.group == null) {
                return false;
            }
            if (this_span.mark_one.?.Line.group.?.frame != this_span.mark_two.?.Line.group.?.frame) {
                return false;
            }
        }

        prev_span = this_span;
        span = this_span.f_link;
    }

    return saw_cmd and saw_oops and saw_heap;
}

fn makeSpecialFrame(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    current: *types.FrameObject,
    name: []const u8,
) !*types.FrameObject {
    const frame = (try frame_ops.frameEdit(editor, allocator, current, name)).?;
    frame.options.specialFrame = true;
    return frame;
}

test "validate command accepts healthy special frames and spans" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.terminal_info = .{ .width = 160, .height = 48 };
    const allocator = editor.allocator();

    const root_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const current = (try frame_ops.frameEdit(&editor, allocator, root_fixture.frame, "MAIN")).?;
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
    try mark_ops.markCreate(allocator, current.first_group.?.first_line.?, 1, &span_mark_one);
    try mark_ops.markCreate(allocator, current.last_group.?.last_line.?, 1, &span_mark_two);
    try std.testing.expect(try span_ops.spanCreate(&editor, allocator, "WORK", span_mark_one.?, span_mark_two.?));

    try std.testing.expect(validateCommand(&editor, current, &special_frames));
}

test "validate command rejects missing special frames" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.terminal_info = .{ .width = 160, .height = 48 };
    const allocator = editor.allocator();

    const root_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const current = (try frame_ops.frameEdit(&editor, allocator, root_fixture.frame, "MAIN")).?;
    var special_frames: types.SpecialFrames = .{};
    try std.testing.expect(!validateCommand(&editor, current, &special_frames));
}

test "validate command rejects spans with marks in different frames" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.terminal_info = .{ .width = 160, .height = 48 };
    const allocator = editor.allocator();

    const root_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const current = (try frame_ops.frameEdit(&editor, allocator, root_fixture.frame, "MAIN")).?;
    const other = (try frame_ops.frameEdit(&editor, allocator, current, "OTHER")).?;
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
    try mark_ops.markCreate(allocator, current.first_group.?.first_line.?, 1, &mark_one);
    try mark_ops.markCreate(allocator, other.first_group.?.first_line.?, 1, &mark_two);
    span.* = .{
        .name = "BROKEN",
        .mark_one = mark_one,
        .mark_two = mark_two,
        .b_link = editor.first_span,
    };
    if (editor.first_span) |first| {
        first.f_link = span;
    } else {
        editor.first_span = span;
    }

    try std.testing.expect(!validateCommand(&editor, current, &special_frames));
}
