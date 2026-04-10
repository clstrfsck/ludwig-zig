const builtin = @import("builtin");
const std = @import("std");
const line_ops = @import("../core/line.zig");
const state = @import("../core/state.zig");
const types = @import("../core/types.zig");
const highlight = @import("../highlight/runtime.zig");
const syntax_colors = @import("./syntax_colors.zig");
const terminal = @import("../ui/terminal/ncurses.zig");
pub const testing = @import("./interactive_io_testing.zig");

const pause_message = "Pausing until RETURN pressed: ";
const verify_choices_message = "Reply Y(es),N(o),A(lways),Q(uit),M(ore)";
const verify_start_height: isize = 4;

pub const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
});

pub const Dimensions = struct {
    name: []const u8 = "",
    width: isize = 80,
    height: isize = 24,
};

pub const Session = struct {
    active: bool = false,
    pending_input_key: ?isize = null,
};

pub const PromptReadOptions = struct {
    editor: ?*state.Editor = null,
    frame: ?*types.FrameObject = null,
    max_tp: isize = 1,
    this_tp: isize = 1,
    max_len: usize = types.MaxStrLen,
    terminate_on_space: bool = false,
};

pub const LineStyle = terminal.TextStyle;

var active_session: ?*Session = null;
var pending_status_buffer: [2048]u8 = undefined;
var pending_status_len: usize = 0;
var test_beep_count: usize = 0;
var last_drawn_status_bottom_row: isize = 0;
var last_drawn_status_rows: usize = 0;

pub fn terminalWidthForEditor(editor: *const state.Editor) isize {
    const width = @min(editor.TerminalInfo.Width, @as(isize, types.MaxScrCols));
    return if (width > 0) width else 1;
}

pub fn terminalHeightForEditor(editor: *const state.Editor) isize {
    const height = @min(editor.TerminalInfo.Height, @as(isize, types.MaxScrRows));
    return if (height > 0) height else 1;
}

pub fn frameDisplayHeight(editor: *const state.Editor, frame: *const types.FrameObject) isize {
    var height = terminalHeightForEditor(editor);
    if (frame.ScrHeight > 0 and frame.ScrHeight < height) {
        height = frame.ScrHeight;
    }
    return if (height > 0) height else 1;
}

fn frameHiddenAbove(editor: *const state.Editor, frame: *const types.FrameObject) bool {
    return editor.Screen.Frame == frame and editor.Screen.TopLine != null and editor.Screen.TopLine.?.BLink != null;
}

fn frameHiddenBelow(editor: *const state.Editor, frame: *const types.FrameObject) bool {
    return editor.Screen.Frame == frame and editor.Screen.BotLine != null and editor.Screen.BotLine.?.FLink != null;
}

pub fn visibleContentTopRow(editor: *const state.Editor, frame: *const types.FrameObject) isize {
    const terminal_height = terminalHeightForEditor(editor);
    const frame_height = frameDisplayHeight(editor, frame);
    if (frame_height >= terminal_height) {
        return 1;
    }

    const hidden_above = frameHiddenAbove(editor, frame);
    const hidden_below = frameHiddenBelow(editor, frame);
    if (hidden_above and hidden_below and frame_height <= terminal_height - 2) {
        return 2;
    }
    if (hidden_above and frame_height <= terminal_height - 1) {
        return 2;
    }
    return 1;
}

pub fn absoluteScreenRow(editor: *const state.Editor, frame: *const types.FrameObject, relative_row: isize) isize {
    return visibleContentTopRow(editor, frame) + relative_row - 1;
}

pub fn topMarkerRow(editor: *const state.Editor, frame: *const types.FrameObject) isize {
    if (!frameHiddenAbove(editor, frame)) {
        return 0;
    }
    const top_line = editor.Screen.TopLine orelse return 0;
    const row = absoluteScreenRow(editor, frame, top_line.ScrRowNr);
    return if (row > 1) row - 1 else 0;
}

pub fn bottomMarkerRow(editor: *const state.Editor, frame: *const types.FrameObject) isize {
    if (!frameHiddenBelow(editor, frame)) {
        return 0;
    }
    const bot_line = editor.Screen.BotLine orelse return 0;
    const row = absoluteScreenRow(editor, frame, bot_line.ScrRowNr);
    const terminal_height = terminalHeightForEditor(editor);
    return if (row < terminal_height) row + 1 else 0;
}

pub fn frameLineStyle(line: *const types.LineHdrObject) LineStyle {
    if (line.FLink == null) {
        return .dim;
    }
    return .normal;
}

fn traceEnabled() bool {
    return !builtin.is_test and c.getenv("LUDWIG_TRACE_IO") != null;
}

fn traceKey(source: []const u8, key: u8) void {
    if (!traceEnabled()) {
        return;
    }
    std.debug.print("[io:{s}] key={d} '{c}'\n", .{ source, key, if (key >= 32 and key <= 126) key else '.' });
}

fn isControlByte(key: isize) bool {
    return (key >= 0 and key <= 31) or key == 127;
}

pub fn stdinIsTty() bool {
    return c.isatty(c.STDIN_FILENO) == 1;
}

pub fn stdoutIsTty() bool {
    return c.isatty(c.STDOUT_FILENO) == 1;
}

pub fn interactiveAvailable() bool {
    return stdinIsTty() and stdoutIsTty();
}

pub fn detectDimensions() Dimensions {
    var info: Dimensions = .{};
    if (c.getenv("TERM")) |term_name| {
        info.name = std.mem.span(term_name);
    }

    if (builtin.is_test) {
        if (testing.getDimensionsOverride()) |override| {
            info.width = override.width;
            info.height = override.height;
            return info;
        }
    }

    var winsize: c.struct_winsize = std.mem.zeroes(c.struct_winsize);
    if (c.ioctl(c.STDOUT_FILENO, c.TIOCGWINSZ, &winsize) == 0) {
        if (winsize.ws_col > 0) {
            info.width = @intCast(winsize.ws_col);
        }
        if (winsize.ws_row > 0) {
            info.height = @intCast(winsize.ws_row);
        }
    }
    return info;
}

pub fn activate(session: *Session) !void {
    if (active_session != null) {
        return error.SessionAlreadyActive;
    }
    if (!interactiveAvailable()) {
        return error.NotATerminal;
    }
    _ = try terminal.init();
    syntax_colors.init();

    session.active = true;
    session.pending_input_key = null;
    active_session = session;
}

pub fn deactivate(session: *Session) void {
    if (!session.active) {
        return;
    }
    terminal.deinit();
    session.active = false;
    session.pending_input_key = null;
    last_drawn_status_bottom_row = 0;
    last_drawn_status_rows = 0;
    syntax_colors.reset();
    highlight.deinit();
    if (active_session == session) {
        active_session = null;
    }
    pending_status_len = 0;
}

pub fn takeBackInputKey(key: isize) void {
    if (testing.isActive()) {
        testing.takeBackInputKey(key);
        return;
    }
    if (active_session) |session| {
        session.pending_input_key = key;
    }
}

pub fn readKey() !?u8 {
    if (testing.isActive()) {
        return testing.readKey();
    }

    if (active_session == null) {
        return error.NoActiveSession;
    }

    while (true) {
        const input = terminal.readKey() orelse return null;
        if (input == types.TerminalKeyCodes.DeleteChar) {
            traceKey("live", 127);
            return 127;
        }
        if (input < 0 or input > std.math.maxInt(u8)) {
            continue;
        }
        const key: u8 = @intCast(input);
        traceKey("live", key);
        return key;
    }
}

pub fn readInputKey() !?isize {
    if (testing.isActive()) {
        return testing.readInputKey();
    }
    if (active_session) |session| {
        if (session.pending_input_key) |key| {
            session.pending_input_key = null;
            return key;
        }
        return terminal.readKey();
    }
    return error.NoActiveSession;
}

pub fn printLine(message: []const u8) void {
    if (builtin.is_test) {
        return;
    }
    std.fs.File.stdout().deprecatedWriter().print("{s}\r\n", .{message}) catch {};
}

pub fn queueStatusMessage(message: []const u8) void {
    const keep = @min(message.len, pending_status_buffer.len);
    @memcpy(pending_status_buffer[0..keep], message[0..keep]);
    pending_status_len = keep;
    if (builtin.is_test or active_session == null or keep == 0) {
        return;
    }

    const dims = detectDimensions();
    _ = drawStatusMessage(dims.height, @max(dims.width, 1), pending_status_buffer[0..keep]);
    refresh();
}

pub fn takeStatusMessage() ?[]const u8 {
    if (pending_status_len == 0) {
        return null;
    }
    const len = pending_status_len;
    pending_status_len = 0;
    return pending_status_buffer[0..len];
}

pub fn clearStatusMessage() void {
    pending_status_len = 0;
}

fn writeText(message: []const u8) void {
    if (builtin.is_test) {
        return;
    }
    if (active_session == null) {
        return;
    }
    terminal.writeText(message);
    terminal.refresh();
}

fn writeByte(byte: u8) void {
    if (builtin.is_test) {
        return;
    }
    if (active_session == null) {
        return;
    }
    terminal.writeByte(byte);
    terminal.refresh();
}

pub fn showBanner(message: []const u8) void {
    writeText(message);
}

pub fn beep() void {
    if (builtin.is_test) {
        test_beep_count += 1;
        return;
    }
    if (active_session == null) {
        return;
    }
    terminal.beep();
}

pub fn resetTestBeepCount() void {
    if (builtin.is_test) {
        test_beep_count = 0;
    }
}

pub fn getTestBeepCount() usize {
    return if (builtin.is_test) test_beep_count else 0;
}

fn statusChunkWidth(width: isize) usize {
    const usable_width = if (width > 1) width - 1 else 1;
    return @intCast(@max(usable_width, 1));
}

fn statusRowCount(width: isize, message_len: usize) usize {
    if (message_len == 0 or width < 1) {
        return 0;
    }
    const chunk_width = statusChunkWidth(width);
    return (message_len + chunk_width - 1) / chunk_width;
}

fn statusChunk(message: []const u8, width: isize, chunk_index: usize) []const u8 {
    const chunk_width = statusChunkWidth(width);
    const start = @min(chunk_index * chunk_width, message.len);
    const end = @min(start + chunk_width, message.len);
    return message[start..end];
}

fn clearStatusRows(bottom_row: isize, rows: usize) void {
    if (rows == 0) {
        return;
    }
    const start_row = @max(@as(isize, 1), bottom_row - @as(isize, @intCast(rows)) + 1);
    var row = start_row;
    while (row <= bottom_row) : (row += 1) {
        drawLine(row, "");
    }
}

pub fn drawStatusMessage(row: isize, width: isize, message: []const u8) isize {
    if (row < 1 or width < 1 or message.len == 0) {
        return row + 1;
    }

    const rows_needed = statusRowCount(width, message.len);
    const rows_to_clear = if (last_drawn_status_bottom_row == row)
        @max(last_drawn_status_rows, rows_needed)
    else
        rows_needed;
    clearStatusRows(row, rows_to_clear);

    const start_row = @max(@as(isize, 1), row - @as(isize, @intCast(rows_needed)) + 1);
    var current_row = start_row;
    var chunk_index: usize = 0;
    while (current_row <= row and chunk_index < rows_needed) : ({
        current_row += 1;
        chunk_index += 1;
    }) {
        drawStyledLine(current_row, statusChunk(message, width, chunk_index), .bold);
    }

    last_drawn_status_bottom_row = row;
    last_drawn_status_rows = rows_needed;
    return start_row;
}

pub fn moveCursor(col: isize, row: isize) void {
    if (builtin.is_test or col < 1 or row < 1) {
        return;
    }
    if (active_session == null) {
        return;
    }
    terminal.moveCursor(col, row);
}

pub fn clearScreen() void {
    if (builtin.is_test) {
        return;
    }
    if (active_session == null) {
        return;
    }
    last_drawn_status_bottom_row = 0;
    last_drawn_status_rows = 0;
    terminal.clearScreen();
}

pub fn clearLine() void {
    if (builtin.is_test) {
        return;
    }
    if (active_session == null) {
        return;
    }
    terminal.clearLine();
}

pub fn drawLine(row: isize, text: []const u8) void {
    drawStyledLine(row, text, .normal);
}

pub fn drawStyledLine(row: isize, text: []const u8, style: LineStyle) void {
    if (builtin.is_test) {
        return;
    }
    if (active_session == null) {
        return;
    }
    terminal.writeLineAtStyled(row, text, style);
}

pub fn refresh() void {
    if (builtin.is_test) {
        return;
    }
    if (active_session == null) {
        return;
    }
    terminal.refresh();
}

fn showPrompt(prompt: []const u8) void {
    const dims = detectDimensions();
    _ = showPromptAt(dims.height, prompt, @intCast(@max(dims.width, 1)));
}

fn showPromptAt(row: isize, prompt: []const u8, width: usize) usize {
    const visible_prompt = truncateToWidth(prompt, width);
    drawLine(row, visible_prompt);
    moveCursor(@intCast(visible_prompt.len + 1), row);
    refresh();
    return visible_prompt.len;
}

fn renderPromptBufferAt(row: isize, prompt: []const u8, reply: []const u8, width: usize) void {
    const prompt_len = showPromptAt(row, prompt, width);
    if (reply.len == 0 or prompt_len >= width) {
        return;
    }
    writeText(truncateToWidth(reply, width - prompt_len));
}

fn truncateToWidth(text: []const u8, width: usize) []const u8 {
    return text[0..@min(text.len, width)];
}

fn frameDisplayWidth(editor: *const state.Editor, frame: *const types.FrameObject) isize {
    var width = terminalWidthForEditor(editor);
    if (frame.ScrWidth > 0 and frame.ScrWidth < width) {
        width = frame.ScrWidth;
    }
    return if (width > 0) width else 1;
}

fn clampTopLine(frame: *const types.FrameObject, top_number: isize, height: isize) isize {
    const last_number = line_ops.LineToNumber(frame.LastGroup.?.LastLine.?);
    const max_top = @max(@as(isize, 1), last_number - height + 1);
    return @min(@max(top_number, 1), max_top);
}

const VisibleLineRange = struct {
    content: []const u8,
    start: usize,
    end: usize,
};

fn visibleLineRange(frame: *const types.FrameObject, line: *const types.LineHdrObject, width: isize) VisibleLineRange {
    const eop_line = line.FLink == null;
    const content = line_ops.getDisplayLineContent(line);
    const offset: usize = if (eop_line) 0 else @intCast(@max(@as(isize, 0), frame.ScrOffset));
    if (offset >= content.len) {
        return .{ .content = content, .start = content.len, .end = content.len };
    }
    const width_usize: usize = @intCast(width);
    const end = @min(content.len, offset + width_usize);
    return .{ .content = content, .start = offset, .end = end };
}

fn visibleLineSlice(frame: *const types.FrameObject, line: *const types.LineHdrObject, width: isize) []const u8 {
    const range = visibleLineRange(frame, line, width);
    return range.content[range.start..range.end];
}

fn drawHighlightedLine(
    row: isize,
    visible_text: []const u8,
    visible_start: usize,
    entries: []const types.HighlightMatchEntry,
) void {
    if (builtin.is_test or active_session == null) {
        return;
    }
    if (visible_text.len == 0) {
        drawLine(row, "");
        return;
    }

    var segments: [types.MaxStrLenP + 1]terminal.TextSegment = undefined;
    var segment_count: usize = 0;
    var current_pair: u16 = 0;
    var current_offset: usize = 0;
    const visible_end = visible_start + visible_text.len;

    for (entries) |entry| {
        if (entry.Position <= visible_start) {
            current_pair = entry.Pair;
            continue;
        }
        if (entry.Position >= visible_end) {
            break;
        }
        const segment_end = entry.Position - visible_start;
        if (segment_end > current_offset) {
            segments[segment_count] = .{
                .text = visible_text[current_offset..segment_end],
                .color_pair = current_pair,
            };
            segment_count += 1;
        }
        current_pair = entry.Pair;
        current_offset = segment_end;
    }

    if (current_offset < visible_text.len or segment_count == 0) {
        segments[segment_count] = .{
            .text = visible_text[current_offset..],
            .color_pair = current_pair,
        };
        segment_count += 1;
    }

    terminal.writeSegmentsAt(row, segments[0..segment_count]);
}

pub fn drawFrameLine(editor: *const state.Editor, frame: *const types.FrameObject, row: isize, line: *const types.LineHdrObject) void {
    const width = frameDisplayWidth(editor, frame);
    const range = visibleLineRange(frame, line, width);
    const visible_text = range.content[range.start..range.end];
    if (line.FLink == null or line.HlMatch.items.len == 0) {
        drawStyledLine(row, visible_text, frameLineStyle(line));
        return;
    }
    drawHighlightedLine(row, visible_text, range.start, line.HlMatch.items);
}

fn lineAtVisibleRow(
    editor: *const state.Editor,
    frame: *const types.FrameObject,
    top_line: *types.LineHdrObject,
    bot_line: *types.LineHdrObject,
    row: isize,
) ?*types.LineHdrObject {
    const relative_row = row - visibleContentTopRow(editor, frame) + 1;
    if (relative_row < top_line.ScrRowNr or relative_row > bot_line.ScrRowNr) {
        return null;
    }
    var current = top_line;
    while (current.ScrRowNr < relative_row) {
        current = current.FLink orelse return null;
    }
    return if (current.ScrRowNr == relative_row) current else null;
}

fn computePromptPosition(editor: *state.Editor, frame: *types.FrameObject, max_tp: isize, this_tp: isize) isize {
    const dims = detectDimensions();
    const height = @max(dims.height, 1);
    const max_tp_clamped = @max(max_tp, 1);
    const this_tp_clamped = @max(this_tp, 1);
    const region = &editor.PromptRegion[@intCast(this_tp_clamped)];
    region.* = .{};

    const top_row = this_tp_clamped;
    const bottom_row = @max(@as(isize, 1), height - max_tp_clamped + this_tp_clamped);
    region.LineNr = bottom_row;

    if (editor.Screen.Frame != frame or editor.Screen.TopLine == null or editor.Screen.BotLine == null) {
        return region.LineNr;
    }

    const top_line = editor.Screen.TopLine.?;
    const bot_line = editor.Screen.BotLine.?;
    const top_line_row = absoluteScreenRow(editor, frame, top_line.ScrRowNr);
    const bot_line_row = absoluteScreenRow(editor, frame, bot_line.ScrRowNr);
    const msg_row = if (editor.Screen.MsgRow > 0 and editor.Screen.MsgRow < types.MaxInt)
        editor.Screen.MsgRow
    else
        height + 1;

    region.LineNr = top_row;
    if (top_line_row > max_tp_clamped) {
        return region.LineNr;
    }
    if (bot_line_row < msg_row - max_tp_clamped) {
        region.LineNr = bottom_row;
        return region.LineNr;
    }

    if (frame.Dot != null and absoluteScreenRow(editor, frame, frame.Dot.?.Line.ScrRowNr) <= 2) {
        region.LineNr = bottom_row;
        region.Redraw = lineAtVisibleRow(editor, frame, top_line, bot_line, bottom_row);
        return region.LineNr;
    }

    region.Redraw = lineAtVisibleRow(editor, frame, top_line, bot_line, top_row);
    return region.LineNr;
}

fn restorePromptLines(editor: *state.Editor, frame: *types.FrameObject, max_tp: isize) void {
    var index: isize = 1;
    const count = @max(max_tp, 1);
    while (index <= count) : (index += 1) {
        const region = &editor.PromptRegion[@intCast(index)];
        if (region.Redraw) |line| {
            drawFrameLine(editor, frame, region.LineNr, line);
        } else if (region.LineNr != 0) {
            drawLine(region.LineNr, "");
        }
        region.* = .{};
    }

    if (frame.Dot != null and frame.Dot.?.Line.ScrRowNr > 0) {
        const width = frameDisplayWidth(editor, frame);
        const cursor_col = @min(@max(frame.Dot.?.Col - frame.ScrOffset, 1), width);
        moveCursor(cursor_col, absoluteScreenRow(editor, frame, frame.Dot.?.Line.ScrRowNr));
    }
    refresh();
}

fn initialVerifyTopLine(frame: *const types.FrameObject, height: isize) isize {
    const dot_number = line_ops.LineToNumber(frame.Dot.?.Line);
    const desired_row = if (height > 1) @as(isize, 2) else 1;
    return clampTopLine(frame, dot_number - desired_row + 1, height);
}

fn expandVerifyViewport(
    frame: *const types.FrameObject,
    top_number: *isize,
    height: *isize,
    delta: isize,
    max_height: isize,
) void {
    const last_number = line_ops.LineToNumber(frame.LastGroup.?.LastLine.?);
    const target_height = @min(max_height, height.* + delta);
    var top = top_number.*;
    var current_height = height.*;
    var can_grow_down = true;
    var can_grow_up = true;

    while (current_height < target_height and (can_grow_down or can_grow_up)) {
        if (can_grow_down) {
            can_grow_down = false;
            const bottom = top + current_height - 1;
            if (bottom < last_number) {
                current_height += 1;
                can_grow_down = true;
            }
        }
        if (current_height < target_height and can_grow_up) {
            can_grow_up = false;
            if (top > 1) {
                top -= 1;
                current_height += 1;
                can_grow_up = true;
            }
        }
    }

    top_number.* = clampTopLine(frame, top, current_height);
    height.* = current_height;
}

fn drawVerifyViewport(
    editor: *const state.Editor,
    frame: *const types.FrameObject,
    top_number: isize,
    height: isize,
    prompt: []const u8,
) void {
    const dims = detectDimensions();
    const terminal_height = @max(dims.height, 1);
    const width = frameDisplayWidth(editor, frame);

    clearScreen();
    var row: isize = 1;
    var line: ?*types.LineHdrObject = line_ops.LineFromNumber(frame, top_number) orelse frame.FirstGroup.?.FirstLine.?;
    while (row <= height and row < terminal_height) : (row += 1) {
        if (line) |current| {
            drawFrameLine(editor, frame, row, current);
            line = current.FLink;
        } else {
            drawLine(row, "");
        }
    }
    while (row < terminal_height) : (row += 1) {
        drawLine(row, "");
    }

    drawLine(terminal_height, prompt);

    const dot_number = line_ops.LineToNumber(frame.Dot.?.Line);
    const cursor_row = @min(@max(dot_number - top_number + 1, 1), @min(height, terminal_height));
    const cursor_col = @min(@max(frame.Dot.?.Col - frame.ScrOffset, 1), width);
    moveCursor(cursor_col, cursor_row);
    refresh();
}

pub fn showTemporaryLines(lines: []const []const u8) void {
    if (builtin.is_test or active_session == null) {
        return;
    }

    const dims = detectDimensions();
    const width: usize = @intCast(@max(dims.width, 1));
    const body_height: isize = @max(dims.height - 1, 1);

    clearScreen();
    var row: isize = 1;
    while (row <= body_height) : (row += 1) {
        const index: usize = @intCast(row - 1);
        if (index < lines.len) {
            drawLine(row, truncateToWidth(lines[index], width));
        } else {
            drawLine(row, "");
        }
    }

    refresh();
}

pub fn showTemporaryReport(
    allocator: std.mem.Allocator,
    lines: []const []const u8,
) !void {
    showTemporaryLines(lines);
    _ = try readPromptLine(allocator, pause_message);
}

pub fn readPromptLine(allocator: std.mem.Allocator, prompt: []const u8) ![]u8 {
    return readPromptLineWithOptions(allocator, prompt, .{});
}

pub fn readPromptLineWithOptions(
    allocator: std.mem.Allocator,
    prompt: []const u8,
    options: PromptReadOptions,
) ![]u8 {
    const dims = detectDimensions();
    const width: usize = @intCast(@max(dims.width, 1));
    const row = if (options.editor != null and options.frame != null)
        computePromptPosition(options.editor.?, options.frame.?, options.max_tp, options.this_tp)
    else
        dims.height;
    const prompt_len = showPromptAt(row, prompt, width);
    if (traceEnabled()) {
        std.debug.print("[io:prompt-line] prompt={s}\n", .{prompt});
    }

    var buffer: std.ArrayListUnmanaged(u8) = .{};
    errdefer buffer.deinit(allocator);
    const max_len = @min(options.max_len, width - @min(prompt_len, width));

    read_loop: while (buffer.items.len < max_len) {
        const key = (try readInputKey()) orelse break;
        switch (key) {
            '\r', '\n' => break :read_loop,
            8, 127 => {
                if (buffer.items.len > 0) {
                    _ = buffer.pop();
                    renderPromptBufferAt(row, prompt, buffer.items, width);
                } else {
                    beep();
                }
            },
            else => {
                if (key < 0 or key > std.math.maxInt(u8) or isControlByte(key)) {
                    beep();
                    continue;
                }
                try buffer.append(allocator, @intCast(key));
                renderPromptBufferAt(row, prompt, buffer.items, width);
                if (options.terminate_on_space and key == ' ') {
                    break :read_loop;
                }
            },
        }
    }

    if (options.editor != null and options.frame != null) {
        if (buffer.items.len == 0) {
            var index = options.this_tp + 1;
            while (index <= options.max_tp) : (index += 1) {
                options.editor.?.PromptRegion[@intCast(index)] = .{};
            }
        }
        if (options.this_tp >= options.max_tp or buffer.items.len == 0) {
            restorePromptLines(options.editor.?, options.frame.?, options.max_tp);
        }
    }

    return buffer.toOwnedSlice(allocator);
}

pub fn readVerifyKey(prompt: []const u8) !?u8 {
    showPrompt(prompt);
    if (traceEnabled()) {
        std.debug.print("[io:prompt-verify] prompt={s}\n", .{prompt});
    }
    while (true) {
        const raw_key = (try readInputKey()) orelse return null;
        if (raw_key < 0 or raw_key > std.math.maxInt(u8)) {
            beep();
            continue;
        }
        var key: u8 = @intCast(raw_key);
        if (key >= 'a' and key <= 'z') {
            key = key - 'a' + 'A';
        }
        if (key == '\r' or key == '\n') {
            key = 'N';
        }
        return key;
    }
}

pub fn readVerifyReply(
    editor: *state.Editor,
    frame: *types.FrameObject,
    prompt: []const u8,
) !?u8 {
    const dims = detectDimensions();
    const max_height = @max(@min(dims.height, editor.TerminalInfo.Height), 1);
    var view_height = @min(if (frame.ScrHeight > verify_start_height) verify_start_height else frame.ScrHeight, max_height);
    if (view_height < 1) {
        view_height = @min(verify_start_height, max_height);
    }
    var top_number = initialVerifyTopLine(frame, view_height);
    var use_prompt = true;

    while (true) {
        drawVerifyViewport(editor, frame, top_number, view_height, if (use_prompt) prompt else verify_choices_message);
        const raw_key = (try readInputKey()) orelse return null;
        if (raw_key == 3) {
            editor.TtControlC = true;
            return null;
        }
        if (raw_key < 0 or raw_key > std.math.maxInt(u8)) {
            beep();
            use_prompt = false;
            continue;
        }

        var key: u8 = @intCast(raw_key);
        if (key >= 'a' and key <= 'z') {
            key = key - 'a' + 'A';
        }
        if (key == '\r' or key == '\n') {
            key = 'N';
        }

        switch (key) {
            ' ', 'Y', 'N', 'A', 'Q' => return key,
            '1'...'9' => {
                expandVerifyViewport(frame, &top_number, &view_height, key - '0', max_height);
                use_prompt = true;
            },
            'M' => {
                expandVerifyViewport(frame, &top_number, &view_height, 1, max_height);
                use_prompt = true;
            },
            else => {
                beep();
                use_prompt = false;
            },
        }
    }
}

test "interactive io prompts consume test harness input" {
    testing.installInput("ab\rQ");
    defer testing.clearInput();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const line = try readPromptLine(allocator, "Prompt:");
    try std.testing.expectEqualStrings("ab", line);
    try std.testing.expectEqual(@as(?u8, 'Q'), try readVerifyKey("Verify?"));
}

test "interactive io prompt reader ignores control keys and respects help options" {
    testing.installInput("\x01ab \r");
    defer testing.clearInput();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    resetTestBeepCount();
    const line = try readPromptLineWithOptions(allocator, "Topic:", .{
        .max_len = types.KeyLen,
        .terminate_on_space = true,
    });
    try std.testing.expectEqualStrings("ab ", line);
    try std.testing.expectEqual(@as(usize, 1), getTestBeepCount());
}

test "interactive io verify reply handles invalid keys and more context" {
    testing.installInput("\x01MQ");
    defer testing.clearInput();

    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.LudwigMode = .LudwigScreen;
    editor.TerminalInfo = .{ .Width = 40, .Height = 6 };

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
    });

    resetTestBeepCount();
    try std.testing.expectEqual(@as(?u8, 'Q'), try readVerifyReply(&editor, fixture.frame, "Verify ?"));
    try std.testing.expectEqual(@as(usize, 1), getTestBeepCount());
}

test "interactive io status message helpers wrap across rows" {
    const message = "abcdefghijklmnopqrs";
    last_drawn_status_bottom_row = 0;
    last_drawn_status_rows = 0;
    try std.testing.expectEqual(@as(usize, 3), statusRowCount(10, message.len));
    try std.testing.expectEqualStrings("abcdefghi", statusChunk(message, 10, 0));
    try std.testing.expectEqualStrings("jklmnopqr", statusChunk(message, 10, 1));
    try std.testing.expectEqualStrings("s", statusChunk(message, 10, 2));
    try std.testing.expectEqual(@as(isize, 4), drawStatusMessage(6, 10, message));
}

test "interactive io frame line styles keep eof dimmed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"alpha"});
    try fixture.content_lines[0].HlMatch.append(std.testing.allocator, .{ .Position = 0, .Pair = 1 });
    defer fixture.content_lines[0].HlMatch.deinit(std.testing.allocator);

    try std.testing.expectEqual(LineStyle.normal, frameLineStyle(fixture.content_lines[0]));
    try std.testing.expectEqual(LineStyle.dim, frameLineStyle(fixture.sentinel_line));
}
