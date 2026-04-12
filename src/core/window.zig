const std = @import("std");
const frame_ops = @import("frame.zig");
const highlight = @import("../highlight/runtime.zig");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const interactive_io = @import("../platform/interactive_io.zig");
const state = @import("state.zig");
const types = @import("types.zig");

fn moveDotTo(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    target_line: *types.LineHdrObject,
) !bool {
    if (frame.dot == null) {
        return false;
    }
    try mark_ops.markCreate(allocator, target_line, frame.dot.?.Col, &frame.dot);
    return true;
}

fn changeFrameSize(
    editor: *state.Editor,
    frame: *types.FrameObject,
    band: isize,
    half_screen: isize,
) void {
    if (frame.scr_height == editor.initial_scr_height or frame.scr_height > editor.terminal_info.height) {
        frame.scr_height = editor.terminal_info.height;
    }
    if (frame.scr_width == editor.initial_scr_width or frame.scr_width > editor.terminal_info.width) {
        frame.scr_width = editor.terminal_info.width;
    }
    if (frame.margin_top == editor.initial_margin_top or frame.margin_top >= half_screen) {
        frame.margin_top = band;
    }
    if (frame.margin_bottom == editor.initial_margin_bottom or frame.margin_bottom >= half_screen) {
        frame.margin_bottom = band;
    }
    if (frame.margin_left > editor.terminal_info.width) {
        frame.margin_left = 1;
    }
    if (frame.margin_right == editor.initial_margin_right or frame.margin_right > editor.terminal_info.width) {
        frame.margin_right = editor.terminal_info.width;
    }

    const max_offset = @max(@as(isize, 0), types.max_str_len_p1 - frame.scr_width);
    if (frame.scr_offset > max_offset) {
        frame.scr_offset = max_offset;
    }
    if (frame.dot) |dot| {
        if (dot.Col <= frame.scr_offset) {
            dot.Col = frame.scr_offset + 1;
        }
        if (dot.Col > frame.scr_offset + frame.scr_width) {
            dot.Col = frame.scr_offset + frame.scr_width;
        }
    }
}

fn resizeWindow(editor: *state.Editor) void {
    const dimensions = interactive_io.detectDimensions();
    editor.tt_win_changed = false;
    editor.terminal_info.width = dimensions.width;
    editor.terminal_info.height = dimensions.height;
    editor.screen.msg_row = dimensions.height + 1;

    const band = @divTrunc(dimensions.height, 6);
    const half_screen = @divTrunc(dimensions.height, 2);
    var span = editor.first_span;
    while (span) |current_span| : (span = current_span.f_link) {
        if (current_span.frame) |span_frame| {
            changeFrameSize(editor, span_frame, band, half_screen);
        }
    }

    editor.initial_margin_right = dimensions.width;
    editor.initial_margin_top = band;
    editor.initial_margin_bottom = band;
    editor.initial_scr_width = dimensions.width;
    editor.initial_scr_height = dimensions.height;

    editor.screen.frame = null;
    editor.screen.top_line = null;
    editor.screen.bot_line = null;
}

fn terminalHeight(editor: *const state.Editor) isize {
    return interactive_io.terminalHeightForEditor(editor);
}

fn terminalWidth(editor: *const state.Editor) isize {
    return interactive_io.terminalWidthForEditor(editor);
}

fn displayHeight(editor: *const state.Editor, frame: *const types.FrameObject) isize {
    return interactive_io.frameDisplayHeight(editor, frame);
}

fn displayWidth(editor: *const state.Editor, frame: *const types.FrameObject) isize {
    var width = terminalWidth(editor);
    if (frame.scr_width > 0 and frame.scr_width < width) {
        width = frame.scr_width;
    }
    return if (width > 0) width else 1;
}

fn clearVisibleRows(editor: *state.Editor) void {
    var line = editor.screen.top_line;
    const bot_line = editor.screen.bot_line;
    while (line) |current| {
        current.scr_row_num = 0;
        if (bot_line != null and current == bot_line.?) {
            break;
        }
        line = current.f_link;
    }
}

fn clampTopLine(frame: *types.FrameObject, top_number: isize, height: isize) isize {
    const last_number = line_ops.lineToNumber(frame.last_group.?.last_line.?);
    const max_top = @max(@as(isize, 1), last_number - height + 1);
    return @min(@max(top_number, 1), max_top);
}

fn setViewport(
    editor: *state.Editor,
    frame: *types.FrameObject,
    top_number: isize,
    height: isize,
) void {
    clearVisibleRows(editor);

    const top_line = line_ops.lineFromNumber(frame, top_number) orelse frame.first_group.?.first_line.?;
    var current = top_line;
    var row: isize = 1;
    var bot_line = top_line;
    while (true) {
        current.scr_row_num = row;
        bot_line = current;
        if (row >= height or current.f_link == null) {
            break;
        }
        current = current.f_link.?;
        row += 1;
    }

    editor.screen.frame = frame;
    editor.screen.top_line = top_line;
    editor.screen.bot_line = bot_line;
    frame.scr_dot_line = frame.dot.?.Line.scr_row_num;
}

fn loadViewport(editor: *state.Editor, frame: *types.FrameObject) void {
    const height = displayHeight(editor, frame);
    const dot_number = line_ops.lineToNumber(frame.dot.?.Line);
    const last_number = line_ops.lineToNumber(frame.last_group.?.last_line.?);

    var desired_row = frame.scr_dot_line;
    if (desired_row < 1) {
        desired_row = 1;
    }
    if (desired_row > height) {
        desired_row = height;
    }

    const remaining = last_number - dot_number;
    if (remaining < height - desired_row) {
        desired_row = height - remaining;
    }
    if (dot_number < desired_row) {
        desired_row = dot_number;
    }

    setViewport(editor, frame, clampTopLine(frame, dot_number - desired_row + 1, height), height);
}

fn positionViewport(editor: *state.Editor, frame: *types.FrameObject) void {
    const height = displayHeight(editor, frame);
    var top_number = if (editor.screen.top_line) |top_line| line_ops.lineToNumber(top_line) else @as(isize, 1);
    const dot_number = line_ops.lineToNumber(frame.dot.?.Line);
    const bottom_limit = @max(@as(isize, 1), height - frame.margin_bottom);

    top_number = clampTopLine(frame, top_number, height);
    const dot_row = dot_number - top_number + 1;
    if (dot_row <= frame.margin_top and top_number > 1) {
        top_number = dot_number - frame.margin_top;
    } else if (dot_row > bottom_limit) {
        top_number = dot_number - bottom_limit + 1;
    }

    setViewport(editor, frame, clampTopLine(frame, top_number, height), height);
}

fn ensureHorizontalVisibility(editor: *const state.Editor, frame: *types.FrameObject) void {
    const width = displayWidth(editor, frame);
    const max_offset = @max(@as(isize, 0), types.max_str_len_p1 - width);

    if (frame.scr_offset < 0) {
        frame.scr_offset = 0;
    }
    if (frame.dot.?.Col <= frame.scr_offset) {
        frame.scr_offset = frame.dot.?.Col - 1;
    } else if (frame.dot.?.Col > frame.scr_offset + width) {
        frame.scr_offset = frame.dot.?.Col - width;
    }
    if (frame.scr_offset < 0) {
        frame.scr_offset = 0;
    }
    if (frame.scr_offset > max_offset) {
        frame.scr_offset = max_offset;
    }
}

fn syncViewport(editor: *state.Editor, frame: *types.FrameObject) void {
    ensureHorizontalVisibility(editor, frame);
    if (editor.screen.frame != frame or editor.screen.top_line == null or editor.screen.bot_line == null) {
        loadViewport(editor, frame);
    } else {
        positionViewport(editor, frame);
    }
}

fn invalidateViewport(editor: *state.Editor) void {
    clearVisibleRows(editor);
    editor.screen.frame = null;
    editor.screen.top_line = null;
    editor.screen.bot_line = null;
}

fn scrollViewport(editor: *state.Editor, frame: *types.FrameObject, count: isize) void {
    syncViewport(editor, frame);
    const top_number = if (editor.screen.top_line) |top_line| line_ops.lineToNumber(top_line) else @as(isize, 1);
    const height = displayHeight(editor, frame);
    setViewport(editor, frame, clampTopLine(frame, top_number + count, height), height);
}

const CursorPosition = struct {
    row: isize,
    col: isize,
};

fn visibleCursorPosition(editor: *const state.Editor, frame: *const types.FrameObject) CursorPosition {
    const height = terminalHeight(editor);
    const width = displayWidth(editor, frame);
    var cursor_row = interactive_io.absoluteScreenRow(editor, frame, frame.dot.?.Line.scr_row_num);
    var cursor_col = frame.dot.?.Col - frame.scr_offset;
    if (cursor_row < 1) {
        cursor_row = 1;
    }
    if (cursor_row > height) {
        cursor_row = height;
    }
    if (cursor_col < 1) {
        cursor_col = 1;
    }
    if (cursor_col > width) {
        cursor_col = width;
    }
    return .{ .row = cursor_row, .col = cursor_col };
}

fn redrawScreenNow(editor: *state.Editor, frame: *types.FrameObject) void {
    if (editor.ludwig_mode != .LudwigScreen) {
        return;
    }

    highlight.applyDirty(editor, frame);
    const height = terminalHeight(editor);
    const top_marker_row = interactive_io.topMarkerRow(editor, frame);
    const bottom_marker_row = interactive_io.bottomMarkerRow(editor, frame);
    interactive_io.clearScreen();

    var row: isize = 1;
    var line = editor.screen.top_line;
    while (row <= height) : (row += 1) {
        if (row == top_marker_row) {
            interactive_io.drawStyledLine(row, "<TOP>", .bold);
        } else if (row == bottom_marker_row) {
            interactive_io.drawStyledLine(row, "<BOTTOM>", .bold);
        } else if (line) |current| {
            const line_row = interactive_io.absoluteScreenRow(editor, frame, current.scr_row_num);
            if (line_row == row) {
                interactive_io.drawFrameLine(editor, frame, row, current);
                if (editor.screen.bot_line != null and current == editor.screen.bot_line.?) {
                    line = null;
                } else {
                    line = current.f_link;
                }
            } else {
                interactive_io.drawLine(row, "");
            }
        } else {
            interactive_io.drawLine(row, "");
        }
    }

    editor.screen.msg_row = height + 1;
    const cursor = visibleCursorPosition(editor, frame);
    interactive_io.moveCursor(cursor.col, cursor.row);
    interactive_io.refresh();
}

fn dotVisible(editor: *const state.Editor, frame: *const types.FrameObject) bool {
    const dot = frame.dot orelse return false;
    const width = displayWidth(editor, frame);
    return dot.Line.scr_row_num != 0 and dot.Col > frame.scr_offset and dot.Col <= frame.scr_offset + width;
}

pub fn windowCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    command: types.Commands,
    rept: types.LeadParam,
    count: isize,
    from_span: bool,
) !bool {
    if (frame.first_group == null or frame.last_group == null) {
        return false;
    }

    return switch (command) {
        .CmdWindowBackward => blk: {
            if (frame.dot == null or count < 0) break :blk false;
            const step = frame.scr_height * count;
            const current_nr = line_ops.lineToNumber(frame.dot.?.Line);
            const target_nr = if (current_nr <= step) @as(isize, 1) else current_nr - step;
            const target_line = line_ops.lineFromNumber(frame, target_nr) orelse frame.first_group.?.first_line.?;
            break :blk try moveDotTo(allocator, frame, target_line);
        },
        .CmdWindowEnd => try moveDotTo(allocator, frame, frame.last_group.?.last_line.?),
        .CmdWindowForward => blk: {
            if (frame.dot == null or count < 0) break :blk false;
            const step = frame.scr_height * count;
            const current_nr = line_ops.lineToNumber(frame.dot.?.Line);
            const last_nr = line_ops.lineToNumber(frame.last_group.?.last_line.?);
            const target_nr = @min(last_nr, current_nr + step);
            const target_line = line_ops.lineFromNumber(frame, target_nr) orelse frame.last_group.?.last_line.?;
            break :blk try moveDotTo(allocator, frame, target_line);
        },
        .CmdWindowLeft => blk: {
            if (frame.dot == null) break :blk false;
            if (editor.screen.frame != frame) break :blk true;
            var delta = if (rept == .LeadParamNone) @divTrunc(frame.scr_width, 2) else count;
            if (delta < 0) break :blk false;
            if (frame.scr_offset < delta) {
                delta = frame.scr_offset;
            }
            frame.scr_offset -= delta;
            if (frame.scr_offset + frame.scr_width < frame.dot.?.Col) {
                frame.dot.?.Col = frame.scr_offset + frame.scr_width;
            }
            break :blk true;
        },
        .CmdWindowMiddle => blk: {
            if (editor.screen.frame == frame) {
                frame.scr_dot_line = @divTrunc(displayHeight(editor, frame) + 1, 2);
                loadViewport(editor, frame);
                redrawScreenNow(editor, frame);
            }
            break :blk true;
        },
        .CmdWindowNew => blk: {
            if (editor.screen.frame == frame) {
                const top_number = if (editor.screen.top_line) |top_line| line_ops.lineToNumber(top_line) else line_ops.lineToNumber(frame.dot.?.Line);
                invalidateViewport(editor);
                const height = displayHeight(editor, frame);
                setViewport(editor, frame, clampTopLine(frame, top_number, height), height);
                redrawScreenNow(editor, frame);
            }
            break :blk true;
        },
        .CmdWindowScroll => blk: {
            if (editor.screen.frame == frame) {
                syncViewport(editor, frame);
                redrawScreenNow(editor, frame);

                var scroll_rept = rept;
                var scroll_count = count;
                while (true) {
                    switch (scroll_rept) {
                        .LeadParamPIndef => scroll_count = @max(frame.dot.?.Line.scr_row_num - 1, 0),
                        .LeadParamNIndef => scroll_count = frame.dot.?.Line.scr_row_num - frame.scr_height,
                        else => {},
                    }

                    if (scroll_rept != .LeadParamNone and scroll_count != 0) {
                        scrollViewport(editor, frame, scroll_count);
                        redrawScreenNow(editor, frame);
                    }

                    if (from_span or editor.ludwig_mode != .LudwigScreen or !dotVisible(editor, frame)) {
                        break;
                    }

                    const key = (try interactive_io.readInputKey()) orelse break;
                    if (key == 3) {
                        editor.tt_control_c = true;
                        break;
                    }
                    switch (key) {
                        types.terminal_key_codes.up_arrow => {
                            scroll_rept = .LeadParamPInt;
                            scroll_count = 1;
                        },
                        types.terminal_key_codes.down_arrow => {
                            scroll_rept = .LeadParamNInt;
                            scroll_count = -1;
                        },
                        else => {
                            interactive_io.takeBackInputKey(key);
                            break;
                        },
                    }
                }
            }
            break :blk true;
        },
        .CmdWindowUpdate => blk: {
            if (editor.ludwig_mode == .LudwigScreen) {
                syncViewport(editor, frame);
                redrawScreenNow(editor, frame);
            }
            break :blk true;
        },
        .CmdResizeWindow => blk: {
            resizeWindow(editor);
            break :blk true;
        },
        .CmdWindowRight => blk: {
            if (frame.dot == null) break :blk false;
            if (editor.screen.frame != frame) break :blk true;
            var delta = if (rept == .LeadParamNone) @divTrunc(frame.scr_width, 2) else count;
            if (delta < 0) break :blk false;
            const max_delta = types.max_str_len_p1 - (frame.scr_offset + frame.scr_width);
            if (max_delta < delta) {
                delta = max_delta;
            }
            if (delta < 0) {
                delta = 0;
            }
            frame.scr_offset += delta;
            if (frame.dot.?.Col <= frame.scr_offset) {
                frame.dot.?.Col = frame.scr_offset + 1;
            }
            break :blk true;
        },
        .CmdWindowSetHeight => blk: {
            const target_height = if (rept == .LeadParamNone) editor.terminal_info.height else count;
            break :blk frame_ops.frameSetHeight(editor, frame, target_height, false);
        },
        .CmdWindowTop => try moveDotTo(allocator, frame, frame.first_group.?.first_line.?),
        else => false,
    };
}

test "window command moves dot by screen height and clamps" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
        "three",
        "four",
        "five",
    });
    fixture.frame.scr_height = 2;
    try mark_ops.markCreate(allocator, fixture.content_lines[2], 1, &fixture.frame.dot);

    try std.testing.expect(try windowCommand(&editor, allocator, fixture.frame, .CmdWindowForward, .LeadParamNone, 1, false));
    try std.testing.expect(fixture.frame.dot.?.Line == fixture.content_lines[4]);

    try std.testing.expect(try windowCommand(&editor, allocator, fixture.frame, .CmdWindowBackward, .LeadParamPInt, 2, false));
    try std.testing.expect(fixture.frame.dot.?.Line == fixture.content_lines[0]);

    try std.testing.expect(try windowCommand(&editor, allocator, fixture.frame, .CmdWindowEnd, .LeadParamNone, 1, false));
    try std.testing.expect(fixture.frame.dot.?.Line == fixture.sentinel_line);

    try std.testing.expect(try windowCommand(&editor, allocator, fixture.frame, .CmdWindowTop, .LeadParamNone, 1, false));
    try std.testing.expect(fixture.frame.dot.?.Line == fixture.content_lines[0]);
}

test "window command adjusts horizontal offset on active screen frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});
    fixture.frame.scr_width = 10;
    fixture.frame.scr_offset = 5;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 20, &fixture.frame.dot);
    editor.screen.frame = fixture.frame;

    try std.testing.expect(try windowCommand(&editor, allocator, fixture.frame, .CmdWindowLeft, .LeadParamNone, 1, false));
    try std.testing.expectEqual(@as(isize, 0), fixture.frame.scr_offset);
    try std.testing.expectEqual(@as(isize, 10), fixture.frame.dot.?.Col);

    try mark_ops.markCreate(allocator, fixture.content_lines[0], 4, &fixture.frame.dot);
    try std.testing.expect(try windowCommand(&editor, allocator, fixture.frame, .CmdWindowRight, .LeadParamNone, 1, false));
    try std.testing.expectEqual(@as(isize, 5), fixture.frame.scr_offset);
    try std.testing.expectEqual(@as(isize, 6), fixture.frame.dot.?.Col);
}

test "window set height uses terminal height by default" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.terminal_info = .{ .width = 120, .height = 24 };
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});
    try std.testing.expect(try windowCommand(&editor, allocator, fixture.frame, .CmdWindowSetHeight, .LeadParamNone, 1, false));
    try std.testing.expectEqual(@as(isize, 24), fixture.frame.scr_height);
    try std.testing.expectEqual(@as(isize, 4), fixture.frame.margin_top);
    try std.testing.expectEqual(@as(isize, 4), fixture.frame.margin_bottom);
}

test "window resize updates terminal dimensions and frame sizing" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    editor.terminal_info = .{ .width = 80, .height = 24 };
    editor.initial_scr_width = 80;
    editor.initial_scr_height = 24;
    editor.initial_margin_right = 80;
    editor.initial_margin_top = 4;
    editor.initial_margin_bottom = 4;

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});
    fixture.frame.scr_width = 80;
    fixture.frame.scr_height = 24;
    fixture.frame.margin_top = 4;
    fixture.frame.margin_bottom = 4;
    fixture.frame.margin_right = 80;
    fixture.frame.scr_offset = 70;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 90, &fixture.frame.dot);

    const span = try allocator.create(types.SpanObject);
    span.* = .{
        .name = "LUDWIG",
        .frame = fixture.frame,
    };
    fixture.frame.span = span;
    editor.first_span = span;

    interactive_io.testing.setDimensionsOverride(100, 40);
    defer interactive_io.testing.clearInput();

    try std.testing.expect(try windowCommand(&editor, allocator, fixture.frame, .CmdResizeWindow, .LeadParamNone, 1, false));
    try std.testing.expectEqual(@as(isize, 100), editor.terminal_info.width);
    try std.testing.expectEqual(@as(isize, 40), editor.terminal_info.height);
    try std.testing.expectEqual(@as(isize, 100), fixture.frame.scr_width);
    try std.testing.expectEqual(@as(isize, 40), fixture.frame.scr_height);
    try std.testing.expectEqual(@as(isize, 6), fixture.frame.margin_top);
    try std.testing.expectEqual(@as(isize, 6), fixture.frame.margin_bottom);
    try std.testing.expectEqual(@as(isize, 100), fixture.frame.margin_right);
    try std.testing.expectEqual(@as(isize, 70), fixture.frame.scr_offset);
    try std.testing.expectEqual(@as(isize, 90), fixture.frame.dot.?.Col);
}

test "window middle recenters the dot on the active screen" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.ludwig_mode = .LudwigScreen;
    editor.terminal_info = .{ .width = 80, .height = 10 };
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12",
    });
    try mark_ops.markCreate(allocator, fixture.content_lines[8], 1, &fixture.frame.dot);
    fixture.frame.scr_height = 10;
    setViewport(&editor, fixture.frame, 1, displayHeight(&editor, fixture.frame));

    try std.testing.expect(try windowCommand(&editor, allocator, fixture.frame, .CmdWindowMiddle, .LeadParamNone, 1, false));
    try std.testing.expectEqual(@as(isize, 6), fixture.frame.dot.?.Line.scr_row_num);
    try std.testing.expectEqual(@as(isize, 6), fixture.frame.scr_dot_line);
}

test "window scroll supports stay-behind up and takeback" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.ludwig_mode = .LudwigScreen;
    editor.terminal_info = .{ .width = 80, .height = 5 };
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "1", "2", "3", "4", "5", "6", "7",
    });
    try mark_ops.markCreate(allocator, fixture.content_lines[2], 1, &fixture.frame.dot);
    fixture.frame.scr_height = 5;
    setViewport(&editor, fixture.frame, 1, displayHeight(&editor, fixture.frame));

    interactive_io.testing.installInput("\x1b[AQ");
    defer interactive_io.testing.clearInput();

    try std.testing.expect(try windowCommand(&editor, allocator, fixture.frame, .CmdWindowScroll, .LeadParamNone, 1, false));
    try std.testing.expectEqualStrings("2", editor.screen.top_line.?.str.?.slice(1, 1));
    try std.testing.expectEqual(@as(isize, 2), fixture.frame.dot.?.Line.scr_row_num);
    try std.testing.expectEqual(@as(?isize, 'Q'), interactive_io.testing.readInputKey());
}
