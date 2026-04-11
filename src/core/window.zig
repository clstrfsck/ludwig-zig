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
    if (frame.Dot == null) {
        return false;
    }
    try mark_ops.markCreate(allocator, target_line, frame.Dot.?.Col, &frame.Dot);
    return true;
}

fn changeFrameSize(
    editor: *state.Editor,
    frame: *types.FrameObject,
    band: isize,
    half_screen: isize,
) void {
    if (frame.ScrHeight == editor.InitialScrHeight or frame.ScrHeight > editor.TerminalInfo.Height) {
        frame.ScrHeight = editor.TerminalInfo.Height;
    }
    if (frame.ScrWidth == editor.InitialScrWidth or frame.ScrWidth > editor.TerminalInfo.Width) {
        frame.ScrWidth = editor.TerminalInfo.Width;
    }
    if (frame.MarginTop == editor.InitialMarginTop or frame.MarginTop >= half_screen) {
        frame.MarginTop = band;
    }
    if (frame.MarginBottom == editor.InitialMarginBottom or frame.MarginBottom >= half_screen) {
        frame.MarginBottom = band;
    }
    if (frame.MarginLeft > editor.TerminalInfo.Width) {
        frame.MarginLeft = 1;
    }
    if (frame.MarginRight == editor.InitialMarginRight or frame.MarginRight > editor.TerminalInfo.Width) {
        frame.MarginRight = editor.TerminalInfo.Width;
    }

    const max_offset = @max(@as(isize, 0), types.MaxStrLenP - frame.ScrWidth);
    if (frame.ScrOffset > max_offset) {
        frame.ScrOffset = max_offset;
    }
    if (frame.Dot) |dot| {
        if (dot.Col <= frame.ScrOffset) {
            dot.Col = frame.ScrOffset + 1;
        }
        if (dot.Col > frame.ScrOffset + frame.ScrWidth) {
            dot.Col = frame.ScrOffset + frame.ScrWidth;
        }
    }
}

fn resizeWindow(editor: *state.Editor) void {
    const dimensions = interactive_io.detectDimensions();
    editor.TtWinChanged = false;
    editor.TerminalInfo.Width = dimensions.width;
    editor.TerminalInfo.Height = dimensions.height;
    editor.Screen.MsgRow = dimensions.height + 1;

    const band = @divTrunc(dimensions.height, 6);
    const half_screen = @divTrunc(dimensions.height, 2);
    var span = editor.FirstSpan;
    while (span) |current_span| : (span = current_span.FLink) {
        if (current_span.Frame) |span_frame| {
            changeFrameSize(editor, span_frame, band, half_screen);
        }
    }

    editor.InitialMarginRight = dimensions.width;
    editor.InitialMarginTop = band;
    editor.InitialMarginBottom = band;
    editor.InitialScrWidth = dimensions.width;
    editor.InitialScrHeight = dimensions.height;

    editor.Screen.Frame = null;
    editor.Screen.TopLine = null;
    editor.Screen.BotLine = null;
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
    if (frame.ScrWidth > 0 and frame.ScrWidth < width) {
        width = frame.ScrWidth;
    }
    return if (width > 0) width else 1;
}

fn clearVisibleRows(editor: *state.Editor) void {
    var line = editor.Screen.TopLine;
    const bot_line = editor.Screen.BotLine;
    while (line) |current| {
        current.ScrRowNr = 0;
        if (bot_line != null and current == bot_line.?) {
            break;
        }
        line = current.FLink;
    }
}

fn clampTopLine(frame: *types.FrameObject, top_number: isize, height: isize) isize {
    const last_number = line_ops.lineToNumber(frame.LastGroup.?.LastLine.?);
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

    const top_line = line_ops.lineFromNumber(frame, top_number) orelse frame.FirstGroup.?.FirstLine.?;
    var current = top_line;
    var row: isize = 1;
    var bot_line = top_line;
    while (true) {
        current.ScrRowNr = row;
        bot_line = current;
        if (row >= height or current.FLink == null) {
            break;
        }
        current = current.FLink.?;
        row += 1;
    }

    editor.Screen.Frame = frame;
    editor.Screen.TopLine = top_line;
    editor.Screen.BotLine = bot_line;
    frame.ScrDotLine = frame.Dot.?.Line.ScrRowNr;
}

fn loadViewport(editor: *state.Editor, frame: *types.FrameObject) void {
    const height = displayHeight(editor, frame);
    const dot_number = line_ops.lineToNumber(frame.Dot.?.Line);
    const last_number = line_ops.lineToNumber(frame.LastGroup.?.LastLine.?);

    var desired_row = frame.ScrDotLine;
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
    var top_number = if (editor.Screen.TopLine) |top_line| line_ops.lineToNumber(top_line) else @as(isize, 1);
    const dot_number = line_ops.lineToNumber(frame.Dot.?.Line);
    const bottom_limit = @max(@as(isize, 1), height - frame.MarginBottom);

    top_number = clampTopLine(frame, top_number, height);
    const dot_row = dot_number - top_number + 1;
    if (dot_row <= frame.MarginTop and top_number > 1) {
        top_number = dot_number - frame.MarginTop;
    } else if (dot_row > bottom_limit) {
        top_number = dot_number - bottom_limit + 1;
    }

    setViewport(editor, frame, clampTopLine(frame, top_number, height), height);
}

fn ensureHorizontalVisibility(editor: *const state.Editor, frame: *types.FrameObject) void {
    const width = displayWidth(editor, frame);
    const max_offset = @max(@as(isize, 0), types.MaxStrLenP - width);

    if (frame.ScrOffset < 0) {
        frame.ScrOffset = 0;
    }
    if (frame.Dot.?.Col <= frame.ScrOffset) {
        frame.ScrOffset = frame.Dot.?.Col - 1;
    } else if (frame.Dot.?.Col > frame.ScrOffset + width) {
        frame.ScrOffset = frame.Dot.?.Col - width;
    }
    if (frame.ScrOffset < 0) {
        frame.ScrOffset = 0;
    }
    if (frame.ScrOffset > max_offset) {
        frame.ScrOffset = max_offset;
    }
}

fn syncViewport(editor: *state.Editor, frame: *types.FrameObject) void {
    ensureHorizontalVisibility(editor, frame);
    if (editor.Screen.Frame != frame or editor.Screen.TopLine == null or editor.Screen.BotLine == null) {
        loadViewport(editor, frame);
    } else {
        positionViewport(editor, frame);
    }
}

fn invalidateViewport(editor: *state.Editor) void {
    clearVisibleRows(editor);
    editor.Screen.Frame = null;
    editor.Screen.TopLine = null;
    editor.Screen.BotLine = null;
}

fn scrollViewport(editor: *state.Editor, frame: *types.FrameObject, count: isize) void {
    syncViewport(editor, frame);
    const top_number = if (editor.Screen.TopLine) |top_line| line_ops.lineToNumber(top_line) else @as(isize, 1);
    const height = displayHeight(editor, frame);
    setViewport(editor, frame, clampTopLine(frame, top_number + count, height), height);
}

fn visibleLineSlice(frame: *const types.FrameObject, line: *const types.LineHdrObject, width: isize) []const u8 {
    const eop_line = line.FLink == null;
    const content = line_ops.getDisplayLineContent(line);
    const offset: usize = if (eop_line) 0 else @intCast(@max(@as(isize, 0), frame.ScrOffset));
    if (offset >= content.len) {
        return "";
    }
    const width_usize: usize = @intCast(width);
    const end = @min(content.len, offset + width_usize);
    return content[offset..end];
}

const CursorPosition = struct {
    row: isize,
    col: isize,
};

fn visibleCursorPosition(editor: *const state.Editor, frame: *const types.FrameObject) CursorPosition {
    const height = terminalHeight(editor);
    const width = displayWidth(editor, frame);
    var cursor_row = interactive_io.absoluteScreenRow(editor, frame, frame.Dot.?.Line.ScrRowNr);
    var cursor_col = frame.Dot.?.Col - frame.ScrOffset;
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
    if (editor.LudwigMode != .LudwigScreen) {
        return;
    }

    highlight.applyDirty(editor, frame);
    const height = terminalHeight(editor);
    const top_marker_row = interactive_io.topMarkerRow(editor, frame);
    const bottom_marker_row = interactive_io.bottomMarkerRow(editor, frame);
    interactive_io.clearScreen();

    var row: isize = 1;
    var line = editor.Screen.TopLine;
    while (row <= height) : (row += 1) {
        if (row == top_marker_row) {
            interactive_io.drawStyledLine(row, "<TOP>", .bold);
        } else if (row == bottom_marker_row) {
            interactive_io.drawStyledLine(row, "<BOTTOM>", .bold);
        } else if (line) |current| {
            const line_row = interactive_io.absoluteScreenRow(editor, frame, current.ScrRowNr);
            if (line_row == row) {
                interactive_io.drawFrameLine(editor, frame, row, current);
                if (editor.Screen.BotLine != null and current == editor.Screen.BotLine.?) {
                    line = null;
                } else {
                    line = current.FLink;
                }
            } else {
                interactive_io.drawLine(row, "");
            }
        } else {
            interactive_io.drawLine(row, "");
        }
    }

    editor.Screen.MsgRow = height + 1;
    const cursor = visibleCursorPosition(editor, frame);
    interactive_io.moveCursor(cursor.col, cursor.row);
    interactive_io.refresh();
}

fn dotVisible(editor: *const state.Editor, frame: *const types.FrameObject) bool {
    const dot = frame.Dot orelse return false;
    const width = displayWidth(editor, frame);
    return dot.Line.ScrRowNr != 0 and dot.Col > frame.ScrOffset and dot.Col <= frame.ScrOffset + width;
}

pub fn WindowCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    command: types.Commands,
    rept: types.LeadParam,
    count: isize,
    from_span: bool,
) !bool {
    if (frame.FirstGroup == null or frame.LastGroup == null) {
        return false;
    }

    return switch (command) {
        .CmdWindowBackward => blk: {
            if (frame.Dot == null or count < 0) break :blk false;
            const step = frame.ScrHeight * count;
            const current_nr = line_ops.lineToNumber(frame.Dot.?.Line);
            const target_nr = if (current_nr <= step) @as(isize, 1) else current_nr - step;
            const target_line = line_ops.lineFromNumber(frame, target_nr) orelse frame.FirstGroup.?.FirstLine.?;
            break :blk try moveDotTo(allocator, frame, target_line);
        },
        .CmdWindowEnd => try moveDotTo(allocator, frame, frame.LastGroup.?.LastLine.?),
        .CmdWindowForward => blk: {
            if (frame.Dot == null or count < 0) break :blk false;
            const step = frame.ScrHeight * count;
            const current_nr = line_ops.lineToNumber(frame.Dot.?.Line);
            const last_nr = line_ops.lineToNumber(frame.LastGroup.?.LastLine.?);
            const target_nr = @min(last_nr, current_nr + step);
            const target_line = line_ops.lineFromNumber(frame, target_nr) orelse frame.LastGroup.?.LastLine.?;
            break :blk try moveDotTo(allocator, frame, target_line);
        },
        .CmdWindowLeft => blk: {
            if (frame.Dot == null) break :blk false;
            if (editor.Screen.Frame != frame) break :blk true;
            var delta = if (rept == .LeadParamNone) @divTrunc(frame.ScrWidth, 2) else count;
            if (delta < 0) break :blk false;
            if (frame.ScrOffset < delta) {
                delta = frame.ScrOffset;
            }
            frame.ScrOffset -= delta;
            if (frame.ScrOffset + frame.ScrWidth < frame.Dot.?.Col) {
                frame.Dot.?.Col = frame.ScrOffset + frame.ScrWidth;
            }
            break :blk true;
        },
        .CmdWindowMiddle => blk: {
            if (editor.Screen.Frame == frame) {
                frame.ScrDotLine = @divTrunc(displayHeight(editor, frame) + 1, 2);
                loadViewport(editor, frame);
                redrawScreenNow(editor, frame);
            }
            break :blk true;
        },
        .CmdWindowNew => blk: {
            if (editor.Screen.Frame == frame) {
                const top_number = if (editor.Screen.TopLine) |top_line| line_ops.lineToNumber(top_line) else line_ops.lineToNumber(frame.Dot.?.Line);
                invalidateViewport(editor);
                const height = displayHeight(editor, frame);
                setViewport(editor, frame, clampTopLine(frame, top_number, height), height);
                redrawScreenNow(editor, frame);
            }
            break :blk true;
        },
        .CmdWindowScroll => blk: {
            if (editor.Screen.Frame == frame) {
                syncViewport(editor, frame);
                redrawScreenNow(editor, frame);

                var scroll_rept = rept;
                var scroll_count = count;
                while (true) {
                    switch (scroll_rept) {
                        .LeadParamPIndef => scroll_count = @max(frame.Dot.?.Line.ScrRowNr - 1, 0),
                        .LeadParamNIndef => scroll_count = frame.Dot.?.Line.ScrRowNr - frame.ScrHeight,
                        else => {},
                    }

                    if (scroll_rept != .LeadParamNone and scroll_count != 0) {
                        scrollViewport(editor, frame, scroll_count);
                        redrawScreenNow(editor, frame);
                    }

                    if (from_span or editor.LudwigMode != .LudwigScreen or !dotVisible(editor, frame)) {
                        break;
                    }

                    const key = (try interactive_io.readInputKey()) orelse break;
                    if (key == 3) {
                        editor.TtControlC = true;
                        break;
                    }
                    switch (key) {
                        types.TerminalKeyCodes.UpArrow => {
                            scroll_rept = .LeadParamPInt;
                            scroll_count = 1;
                        },
                        types.TerminalKeyCodes.DownArrow => {
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
            if (editor.LudwigMode == .LudwigScreen) {
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
            if (frame.Dot == null) break :blk false;
            if (editor.Screen.Frame != frame) break :blk true;
            var delta = if (rept == .LeadParamNone) @divTrunc(frame.ScrWidth, 2) else count;
            if (delta < 0) break :blk false;
            const max_delta = types.MaxStrLenP - (frame.ScrOffset + frame.ScrWidth);
            if (max_delta < delta) {
                delta = max_delta;
            }
            if (delta < 0) {
                delta = 0;
            }
            frame.ScrOffset += delta;
            if (frame.Dot.?.Col <= frame.ScrOffset) {
                frame.Dot.?.Col = frame.ScrOffset + 1;
            }
            break :blk true;
        },
        .CmdWindowSetHeight => blk: {
            const target_height = if (rept == .LeadParamNone) editor.TerminalInfo.Height else count;
            break :blk frame_ops.FrameSetHeight(editor, frame, target_height, false);
        },
        .CmdWindowTop => try moveDotTo(allocator, frame, frame.FirstGroup.?.FirstLine.?),
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
    fixture.frame.ScrHeight = 2;
    try mark_ops.markCreate(allocator, fixture.content_lines[2], 1, &fixture.frame.Dot);

    try std.testing.expect(try WindowCommand(&editor, allocator, fixture.frame, .CmdWindowForward, .LeadParamNone, 1, false));
    try std.testing.expect(fixture.frame.Dot.?.Line == fixture.content_lines[4]);

    try std.testing.expect(try WindowCommand(&editor, allocator, fixture.frame, .CmdWindowBackward, .LeadParamPInt, 2, false));
    try std.testing.expect(fixture.frame.Dot.?.Line == fixture.content_lines[0]);

    try std.testing.expect(try WindowCommand(&editor, allocator, fixture.frame, .CmdWindowEnd, .LeadParamNone, 1, false));
    try std.testing.expect(fixture.frame.Dot.?.Line == fixture.sentinel_line);

    try std.testing.expect(try WindowCommand(&editor, allocator, fixture.frame, .CmdWindowTop, .LeadParamNone, 1, false));
    try std.testing.expect(fixture.frame.Dot.?.Line == fixture.content_lines[0]);
}

test "window command adjusts horizontal offset on active screen frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});
    fixture.frame.ScrWidth = 10;
    fixture.frame.ScrOffset = 5;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 20, &fixture.frame.Dot);
    editor.Screen.Frame = fixture.frame;

    try std.testing.expect(try WindowCommand(&editor, allocator, fixture.frame, .CmdWindowLeft, .LeadParamNone, 1, false));
    try std.testing.expectEqual(@as(isize, 0), fixture.frame.ScrOffset);
    try std.testing.expectEqual(@as(isize, 10), fixture.frame.Dot.?.Col);

    try mark_ops.markCreate(allocator, fixture.content_lines[0], 4, &fixture.frame.Dot);
    try std.testing.expect(try WindowCommand(&editor, allocator, fixture.frame, .CmdWindowRight, .LeadParamNone, 1, false));
    try std.testing.expectEqual(@as(isize, 5), fixture.frame.ScrOffset);
    try std.testing.expectEqual(@as(isize, 6), fixture.frame.Dot.?.Col);
}

test "window set height uses terminal height by default" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.TerminalInfo = .{ .Width = 120, .Height = 24 };
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});
    try std.testing.expect(try WindowCommand(&editor, allocator, fixture.frame, .CmdWindowSetHeight, .LeadParamNone, 1, false));
    try std.testing.expectEqual(@as(isize, 24), fixture.frame.ScrHeight);
    try std.testing.expectEqual(@as(isize, 4), fixture.frame.MarginTop);
    try std.testing.expectEqual(@as(isize, 4), fixture.frame.MarginBottom);
}

test "window resize updates terminal dimensions and frame sizing" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    editor.TerminalInfo = .{ .Width = 80, .Height = 24 };
    editor.InitialScrWidth = 80;
    editor.InitialScrHeight = 24;
    editor.InitialMarginRight = 80;
    editor.InitialMarginTop = 4;
    editor.InitialMarginBottom = 4;

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});
    fixture.frame.ScrWidth = 80;
    fixture.frame.ScrHeight = 24;
    fixture.frame.MarginTop = 4;
    fixture.frame.MarginBottom = 4;
    fixture.frame.MarginRight = 80;
    fixture.frame.ScrOffset = 70;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 90, &fixture.frame.Dot);

    const span = try allocator.create(types.SpanObject);
    span.* = .{
        .Name = "LUDWIG",
        .Frame = fixture.frame,
    };
    fixture.frame.Span = span;
    editor.FirstSpan = span;

    interactive_io.testing.setDimensionsOverride(100, 40);
    defer interactive_io.testing.clearInput();

    try std.testing.expect(try WindowCommand(&editor, allocator, fixture.frame, .CmdResizeWindow, .LeadParamNone, 1, false));
    try std.testing.expectEqual(@as(isize, 100), editor.TerminalInfo.Width);
    try std.testing.expectEqual(@as(isize, 40), editor.TerminalInfo.Height);
    try std.testing.expectEqual(@as(isize, 100), fixture.frame.ScrWidth);
    try std.testing.expectEqual(@as(isize, 40), fixture.frame.ScrHeight);
    try std.testing.expectEqual(@as(isize, 6), fixture.frame.MarginTop);
    try std.testing.expectEqual(@as(isize, 6), fixture.frame.MarginBottom);
    try std.testing.expectEqual(@as(isize, 100), fixture.frame.MarginRight);
    try std.testing.expectEqual(@as(isize, 70), fixture.frame.ScrOffset);
    try std.testing.expectEqual(@as(isize, 90), fixture.frame.Dot.?.Col);
}

test "window middle recenters the dot on the active screen" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.LudwigMode = .LudwigScreen;
    editor.TerminalInfo = .{ .Width = 80, .Height = 10 };
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12",
    });
    try mark_ops.markCreate(allocator, fixture.content_lines[8], 1, &fixture.frame.Dot);
    fixture.frame.ScrHeight = 10;
    setViewport(&editor, fixture.frame, 1, displayHeight(&editor, fixture.frame));

    try std.testing.expect(try WindowCommand(&editor, allocator, fixture.frame, .CmdWindowMiddle, .LeadParamNone, 1, false));
    try std.testing.expectEqual(@as(isize, 6), fixture.frame.Dot.?.Line.ScrRowNr);
    try std.testing.expectEqual(@as(isize, 6), fixture.frame.ScrDotLine);
}

test "window scroll supports stay-behind up and takeback" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.LudwigMode = .LudwigScreen;
    editor.TerminalInfo = .{ .Width = 80, .Height = 5 };
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "1", "2", "3", "4", "5", "6", "7",
    });
    try mark_ops.markCreate(allocator, fixture.content_lines[2], 1, &fixture.frame.Dot);
    fixture.frame.ScrHeight = 5;
    setViewport(&editor, fixture.frame, 1, displayHeight(&editor, fixture.frame));

    interactive_io.testing.installInput("\x1b[AQ");
    defer interactive_io.testing.clearInput();

    try std.testing.expect(try WindowCommand(&editor, allocator, fixture.frame, .CmdWindowScroll, .LeadParamNone, 1, false));
    try std.testing.expectEqualStrings("2", editor.Screen.TopLine.?.Str.?.slice(1, 1));
    try std.testing.expectEqual(@as(isize, 2), fixture.frame.Dot.?.Line.ScrRowNr);
    try std.testing.expectEqual(@as(?isize, 'Q'), interactive_io.testing.readInputKey());
}
