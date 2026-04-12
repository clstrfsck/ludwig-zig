const std = @import("std");

const chars = @import("../core/chars.zig");
const code_ops = @import("../core/code.zig");
const defaults = @import("../core/defaults.zig");
const file_ops = @import("../core/file.zig");
const frame_ops = @import("../core/frame.zig");
const highlight = @import("../highlight/runtime.zig");
const interactive_io = @import("../platform/interactive_io.zig");
const line_ops = @import("../core/line.zig");
const mark_ops = @import("../core/mark.zig");
const state = @import("../core/state.zig");
const str_object = @import("../core/str_object.zig");
const text = @import("../core/text.zig");
const types = @import("../core/types.zig");
const user_ops = @import("../core/user.zig");

const command_span_name = "L. Wittgenstein und Sohn.";
const no_output_file_quit_message = "This frame has no output file--are you sure you want to QUIT? ";
const startup_loading_message = "Copyright (C) 1981, 1987, University of Adelaide.";

fn traceEnabled() bool {
    return interactive_io.c.getenv("LUDWIG_TRACE_IO") != null;
}

fn trace(comptime fmt: []const u8, args: anytype) void {
    if (!traceEnabled()) {
        return;
    }
    std.debug.print(fmt, args);
}

pub const Session = struct {
    current_frame: *types.FrameObject,
    special_frames: types.SpecialFrames,
    command_span: *types.SpanObject,
    terminal: interactive_io.Session = .{},
};

fn configureInteractiveTerminal(editor: *state.Editor) void {
    const info = interactive_io.detectDimensions();
    const band = @divTrunc(info.height, 6);
    editor.ludwig_mode = .LudwigScreen;
    editor.terminal_info = .{
        .Name = info.name,
        .Width = info.width,
        .Height = info.height,
    };
    editor.initial_scr_width = info.width;
    editor.initial_scr_height = info.height;
    editor.initial_margin_right = info.width;
    editor.initial_margin_top = band;
    editor.initial_margin_bottom = band;
    editor.screen.MsgRow = info.height + 1;
}

fn makeSpecialFrame(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    name: []const u8,
) !*types.FrameObject {
    const frame = (try frame_ops.frameEdit(editor, allocator, null, name)).?;
    frame.Options.specialFrame = true;
    return frame;
}

fn attachStartupFiles(
    editor: *state.Editor,
    current_frame: *types.FrameObject,
    input: ?*types.FileObject,
    output: ?*types.FileObject,
) void {
    if (input) |input_file| {
        editor.files[1] = input_file;
        editor.files_frames[1] = current_frame;
        current_frame.InputFile = 1;
    }
    if (output) |output_file| {
        editor.files[2] = output_file;
        editor.files_frames[2] = current_frame;
        current_frame.OutputFile = 2;
    }
}

fn executeCommandFrameFile(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    current_frame: *types.FrameObject,
    special_frames: *types.SpecialFrames,
    file_name: []const u8,
) !code_ops.InterpretResult {
    const cmd_frame = special_frames.Cmd orelse return error.MissingCommandFrame;
    const cmd_span = cmd_frame.Span orelse return error.MissingCommandSpan;
    if (!try file_ops.loadBufferedFileIntoFrameByName(editor, allocator, cmd_frame, file_name)) {
        return .{ .frame = current_frame, .ok = false };
    }
    if (!try code_ops.codeCompile(editor, allocator, current_frame, cmd_span, true)) {
        return .{ .frame = current_frame, .ok = false };
    }
    return code_ops.codeInterpretFrame(
        editor,
        allocator,
        current_frame,
        special_frames,
        .LeadParamNone,
        1,
        cmd_span.Code.?,
        true,
    );
}

pub fn startUp(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    input: ?*types.FileObject,
    output: ?*types.FileObject,
) !*Session {
    defaults.setRegularTabStops(editor, editor.file_data.TabWidth);

    const session = try allocator.create(Session);
    session.* = .{
        .current_frame = undefined,
        .special_frames = .{},
        .command_span = undefined,
    };

    try interactive_io.activate(&session.terminal);
    errdefer interactive_io.deactivate(&session.terminal);
    configureInteractiveTerminal(editor);

    session.special_frames.Oops = try makeSpecialFrame(editor, allocator, "OOPS");
    session.special_frames.Oops.?.SpaceLimit = types.MaxSpace;
    session.special_frames.Oops.?.SpaceLeft = types.MaxSpace - 50;
    session.special_frames.Cmd = try makeSpecialFrame(editor, allocator, "COMMAND");
    session.special_frames.Heap = try makeSpecialFrame(editor, allocator, "HEAP");

    session.current_frame = (try frame_ops.frameEdit(editor, allocator, null, types.DefaultFrameName)).?;
    editor.screen.Frame = session.current_frame;
    editor.screen.TopLine = session.current_frame.FirstGroup.?.FirstLine.?;
    editor.screen.BotLine = session.current_frame.LastGroup.?.LastLine.?;
    try user_ops.userKeyInitialize(editor, allocator);

    attachStartupFiles(editor, session.current_frame, input, output);

    if (session.current_frame.InputFile != 0) {
        interactive_io.queueStatusMessage(startup_loading_message);
    }
    if (session.current_frame.InputFile != 0 and !try file_ops.filePage(editor, allocator, session.current_frame)) {
        return error.InteractiveStartupFailed;
    }

    if (editor.file_data.Initial.len > 0) {
        const init_outcome = try executeCommandFrameFile(
            editor,
            allocator,
            session.current_frame,
            &session.special_frames,
            editor.file_data.Initial,
        );
        session.current_frame = init_outcome.frame;
        editor.exit_abort = false;
    }

    session.command_span = try allocator.create(types.SpanObject);
    session.command_span.* = .{
        .Name = command_span_name,
    };
    interactive_io.showBanner(types.DefaultFrameName);
    return session;
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
    var line = editor.screen.TopLine;
    const bot_line = editor.screen.BotLine;
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

    editor.screen.Frame = frame;
    editor.screen.TopLine = top_line;
    editor.screen.BotLine = bot_line;
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
    var top_number = if (editor.screen.TopLine) |top_line| line_ops.lineToNumber(top_line) else @as(isize, 1);
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

fn syncViewport(editor: *state.Editor, frame: *types.FrameObject) void {
    ensureHorizontalVisibility(editor, frame);
    if (editor.screen.Frame != frame or editor.screen.TopLine == null or editor.screen.BotLine == null) {
        loadViewport(editor, frame);
    } else {
        positionViewport(editor, frame);
    }
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

fn redrawScreen(editor: *state.Editor, frame: *types.FrameObject) !void {
    highlight.applyDirty(editor, frame);
    syncViewport(editor, frame);

    const height = terminalHeight(editor);
    const status_width = terminalWidth(editor);
    const top_marker_row = interactive_io.topMarkerRow(editor, frame);
    const bottom_marker_row = interactive_io.bottomMarkerRow(editor, frame);
    interactive_io.clearScreen();

    var row: isize = 1;
    var line = editor.screen.TopLine;
    while (row <= height) : (row += 1) {
        if (row == top_marker_row) {
            interactive_io.drawStyledLine(row, "<TOP>", .bold);
        } else if (row == bottom_marker_row) {
            interactive_io.drawStyledLine(row, "<BOTTOM>", .bold);
        } else if (line) |current| {
            const line_row = interactive_io.absoluteScreenRow(editor, frame, current.ScrRowNr);
            if (line_row == row) {
                interactive_io.drawFrameLine(editor, frame, row, current);
                if (editor.screen.BotLine != null and current == editor.screen.BotLine.?) {
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

    if (interactive_io.takeStatusMessage()) |message| {
        editor.screen.MsgRow = interactive_io.drawStatusMessage(height, status_width, message);
    } else {
        editor.screen.MsgRow = height + 1;
    }

    const cursor = visibleCursorPosition(editor, frame);
    interactive_io.moveCursor(cursor.col, cursor.row);
    interactive_io.refresh();
}

const testing = struct {
    fn renderSnapshot(editor: *state.Editor, frame: *types.FrameObject, writer: anytype) !void {
        syncViewport(editor, frame);

        const height = terminalHeight(editor);
        const width = displayWidth(editor, frame);
        const top_marker_row = interactive_io.topMarkerRow(editor, frame);
        const bottom_marker_row = interactive_io.bottomMarkerRow(editor, frame);
        try writer.writeAll("\x1b[2J\x1b[H");

        var row: isize = 1;
        var line = editor.screen.TopLine;
        while (row <= height) : (row += 1) {
            if (row == top_marker_row) {
                try writer.writeAll("<TOP>");
            } else if (row == bottom_marker_row) {
                try writer.writeAll("<BOTTOM>");
            } else if (line) |current| {
                const line_row = interactive_io.absoluteScreenRow(editor, frame, current.ScrRowNr);
                if (line_row == row) {
                    try writer.writeAll(visibleLineSlice(frame, current, width));
                    if (editor.screen.BotLine != null and current == editor.screen.BotLine.?) {
                        line = null;
                    } else {
                        line = current.FLink;
                    }
                } else {
                    // Leave the row blank.
                }
            }
            if (row < height) {
                try writer.writeAll("\r\n");
            }
        }

        const cursor = visibleCursorPosition(editor, frame);
        try writer.print("\x1b[{d};{d}H", .{ cursor.row, cursor.col });
    }
};

fn windUp(editor: *state.Editor, allocator: std.mem.Allocator, session: *Session) !void {
    interactive_io.moveCursor(1, terminalHeight(editor));
    interactive_io.clearLine();
    interactive_io.refresh();
    highlight.deinitHighlighting(editor.base_allocator, editor);
    if (session.terminal.active) {
        interactive_io.deactivate(&session.terminal);
    }
    interactive_io.printLine("");

    editor.ludwig_mode = .LudwigBatch;
    editor.screen.Frame = null;
    editor.screen.TopLine = null;
    editor.screen.BotLine = null;
    editor.tt_control_c = false;
    editor.exit_abort = false;

    if (editor.quit_requested) {
        editor.quit_requested = false;
    }
    _ = try file_ops.quitCloseFiles(editor, allocator);
}

fn executeCompiledCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    session: *Session,
) !bool {
    trace("[rt:compile] start mode={s} introducer={c}\n", .{
        @tagName(editor.edit_mode),
        if (editor.command_introducer >= 32 and editor.command_introducer <= 126)
            @as(u8, @intCast(editor.command_introducer))
        else
            '.',
    });
    if (!try code_ops.codeCompile(editor, allocator, session.current_frame, session.command_span, false)) {
        trace("[rt:compile] compile failed\n", .{});
        return false;
    }
    const compiled = &editor.compiler_code[@intCast(session.command_span.Code.?.Code)];
    trace("[rt:compile] op={s}\n", .{@tagName(compiled.Op)});
    const outcome = try code_ops.codeInterpretFrame(
        editor,
        allocator,
        session.current_frame,
        &session.special_frames,
        .LeadParamNone,
        1,
        session.command_span.Code.?,
        false,
    );
    session.current_frame = outcome.frame;
    editor.screen.Frame = session.current_frame;
    trace("[rt:compile] done ok={} quit={} introducer={d}\n", .{
        outcome.ok,
        editor.quit_requested,
        editor.command_introducer,
    });
    return outcome.ok;
}

fn markTextChange(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !void {
    frame.TextModified = true;
    try mark_ops.markCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkModified]);
    try mark_ops.markCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col - 1, &frame.Marks[types.MarkEquals]);
}

fn autoWrapIfNeeded(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !void {
    if (frame.Dot == null or frame.Dot.?.Col != frame.MarginRight + 1) {
        return;
    }
    if (!frame.Options.autoWrap) {
        return;
    }

    const next_key_opt = try interactive_io.readInputKey();
    const next_key = next_key_opt orelse return;
    if (next_key < 0 or next_key > std.math.maxInt(u8) or
        !chars.chIsPrintable(@intCast(next_key)) or
        next_key == editor.command_introducer)
    {
        interactive_io.takeBackInputKey(next_key);
        return;
    }
    const next_byte: u8 = @intCast(next_key);

    var split_col = frame.MarginRight;
    if (next_byte != ' ') {
        while (frame.Dot.?.Line.Str.?.get(split_col) != ' ' and split_col > frame.MarginLeft) {
            split_col -= 1;
        }
        var last_non_space = split_col;
        while (frame.Dot.?.Line.Str.?.get(last_non_space) == ' ' and last_non_space > frame.MarginLeft) {
            last_non_space -= 1;
        }
        if (last_non_space == frame.MarginLeft) {
            split_col = frame.MarginRight;
        }
        interactive_io.takeBackInputKey(next_key);
    }

    frame.Dot.?.Col = split_col + 1;
    _ = try text.textSplitLine(allocator, frame.Dot.?, 0, &frame.Marks[types.MarkEquals]);
    frame.Dot.?.Col += frame.MarginRight - split_col;
}

fn insertPrintable(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    session: *Session,
    key: u8,
) !bool {
    const frame = session.current_frame;
    const temp = try str_object.newBlankStrObject(allocator, 1);
    temp.set(1, key);

    const ok = switch (editor.edit_mode) {
        .ModeInsert => try text.textInsert(allocator, false, 1, temp, 1, frame.Dot.?),
        .ModeOvertype => try text.textOvertype(allocator, false, 1, temp, 1, frame.Dot.?),
        .ModeCommand => false,
    };
    if (!ok) {
        return false;
    }

    try markTextChange(allocator, frame);
    try autoWrapIfNeeded(editor, allocator, frame);
    return true;
}

fn executeLookupKey(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    session: *Session,
    key: isize,
) !bool {
    trace("[rt:lookup] key={d} '{c}' introducer={d}\n", .{
        key,
        if (key >= 32 and key <= 126) @as(u8, @intCast(key)) else '.',
        editor.command_introducer,
    });
    if (key < 0 or key >= types.lookup_count) {
        return false;
    }
    const binding = editor.lookup[@intCast(key)];
    if (binding.Command == .CmdNoop) {
        return false;
    }
    if (binding.Command == .CmdExtended) {
        const code = binding.Code orelse return false;
        const outcome = try code_ops.codeInterpretFrame(
            editor,
            allocator,
            session.current_frame,
            &session.special_frames,
            .LeadParamNone,
            1,
            code,
            true,
        );
        session.current_frame = outcome.frame;
        editor.screen.Frame = session.current_frame;
        return outcome.ok;
    }

    const ok = try code_ops.executeSingle(
        editor,
        allocator,
        &session.current_frame,
        &session.special_frames,
        binding.Command,
        .LeadParamNone,
        1,
        binding.Tpar,
        false,
    );
    editor.screen.Frame = session.current_frame;
    trace("[rt:lookup] op={s} ok={} quit={}\n", .{
        @tagName(binding.Command),
        ok,
        editor.quit_requested,
    });
    return ok;
}

fn positionDotAtModifiedMark(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !void {
    const modified = frame.Marks[types.MarkModified] orelse return;
    try mark_ops.markCreate(allocator, modified.Line, modified.Col, &frame.Dot);
}

fn confirmQuitRequest(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    session: *Session,
) !bool {
    var span = editor.first_span;
    while (span) |current_span| : (span = current_span.FLink) {
        const frame = current_span.Frame orelse continue;
        if (!frame.TextModified or frame.OutputFile != 0 or frame.InputFile == 0) {
            continue;
        }

        try positionDotAtModifiedMark(allocator, frame);
        session.current_frame = frame;
        editor.screen.Frame = frame;
        try redrawScreen(editor, frame);
        interactive_io.beep();

        while (true) {
            const reply = (try interactive_io.readVerifyReply(editor, frame, no_output_file_quit_message)) orelse {
                editor.exit_abort = true;
                return false;
            };
            switch (reply) {
                ' ', 'Y' => break,
                'A' => return true,
                'N', 'Q' => {
                    editor.exit_abort = true;
                    return false;
                },
                else => interactive_io.beep(),
            }
        }
    }

    return true;
}

pub fn run(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    session: *Session,
) !void {
    defer if (session.terminal.active) {
        interactive_io.deactivate(&session.terminal);
    };

    while (true) {
        try redrawScreen(editor, session.current_frame);
        var cmd_success = true;

        if (editor.edit_mode == .ModeCommand) {
            cmd_success = try executeCompiledCommand(editor, allocator, session);
        } else {
            const key_opt = try interactive_io.readInputKey();
            if (key_opt == null) {
                break;
            }

            const key = key_opt.?;
            trace("[rt:key] raw={d} '{c}' introducer={d}\n", .{
                key,
                if (key >= 32 and key <= 126) @as(u8, @intCast(key)) else '.',
                editor.command_introducer,
            });
            if (key == 3) {
                editor.tt_control_c = true;
            } else if (key == editor.command_introducer) {
                cmd_success = try executeCompiledCommand(editor, allocator, session);
            } else if (key >= 0 and key <= std.math.maxInt(u8) and chars.chIsPrintable(@intCast(key))) {
                cmd_success = try insertPrintable(editor, allocator, session, @intCast(key));
                trace("[rt:text] dot_col={} quit={}\n", .{
                    session.current_frame.Dot.?.Col,
                    editor.quit_requested,
                });
            } else {
                cmd_success = try executeLookupKey(editor, allocator, session, key);
            }
        }

        if (!editor.tt_control_c and !cmd_success) {
            interactive_io.beep();
        }

        if (editor.quit_requested) {
            if (!try confirmQuitRequest(editor, allocator, session)) {
                editor.quit_requested = false;
                editor.exit_abort = false;
                editor.tt_control_c = false;
                continue;
            }
            break;
        }
        editor.exit_abort = false;
        editor.tt_control_c = false;
    }

    try windUp(editor, allocator, session);
}

test "interactive testing snapshot paints startup file contents" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    editor.ludwig_mode = .LudwigScreen;
    editor.terminal_info = .{ .Width = 20, .Height = 4 };

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "alpha",
        "beta",
        "gamma",
    });

    var storage: [2048]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&storage);
    try testing.renderSnapshot(&editor, fixture.frame, &writer);

    const snapshot = storage[0..writer.end];
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "alpha\r\nbeta\r\ngamma") != null);
    try std.testing.expect(editor.screen.TopLine == fixture.content_lines[0]);
    try std.testing.expectEqual(@as(isize, 1), fixture.frame.Dot.?.Line.ScrRowNr);
}

test "interactive terminal configuration applies screen-derived defaults" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();

    interactive_io.testing.setDimensionsOverride(120, 24);
    defer interactive_io.testing.clearInput();

    configureInteractiveTerminal(&editor);

    try std.testing.expectEqual(types.LudwigModeType.LudwigScreen, editor.ludwig_mode);
    try std.testing.expectEqual(@as(isize, 120), editor.terminal_info.Width);
    try std.testing.expectEqual(@as(isize, 24), editor.terminal_info.Height);
    try std.testing.expectEqual(@as(isize, 120), editor.initial_scr_width);
    try std.testing.expectEqual(@as(isize, 24), editor.initial_scr_height);
    try std.testing.expectEqual(@as(isize, 1), editor.initial_margin_left);
    try std.testing.expectEqual(@as(isize, 120), editor.initial_margin_right);
    try std.testing.expectEqual(@as(isize, 4), editor.initial_margin_top);
    try std.testing.expectEqual(@as(isize, 4), editor.initial_margin_bottom);
    try std.testing.expectEqual(@as(isize, 25), editor.screen.MsgRow);
}

test "interactive testing snapshot paints top and bottom markers for clipped frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    editor.ludwig_mode = .LudwigScreen;
    editor.terminal_info = .{ .Width = 20, .Height = 6 };

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
    });
    fixture.frame.ScrHeight = 4;
    try mark_ops.markCreate(allocator, fixture.content_lines[3], 1, &fixture.frame.Dot);
    setViewport(&editor, fixture.frame, 2, displayHeight(&editor, fixture.frame));

    var storage: [2048]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&storage);

    try testing.renderSnapshot(&editor, fixture.frame, &writer);

    const snapshot = storage[0..writer.end];
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "<TOP>\r\n2\r\n3\r\n4\r\n5\r\n<BOTTOM>") != null);
}

test "interactive quit confirmation repositions dot at modified mark" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    editor.ludwig_mode = .LudwigScreen;
    editor.terminal_info = .{ .Width = 80, .Height = 24 };

    const current_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"current"});
    const modified_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"edited"});

    const current_span = try allocator.create(types.SpanObject);
    const modified_span = try allocator.create(types.SpanObject);
    current_span.* = .{
        .Name = "CURRENT",
        .Frame = current_fixture.frame,
        .FLink = modified_span,
    };
    modified_span.* = .{
        .Name = "WORK",
        .Frame = modified_fixture.frame,
        .BLink = current_span,
    };
    editor.first_span = current_span;
    current_fixture.frame.Span = current_span;
    modified_fixture.frame.Span = modified_span;

    const input_file = try allocator.create(types.FileObject);
    input_file.* = .{ .Filename = "input.txt" };
    editor.files[1] = input_file;
    editor.files_frames[1] = modified_fixture.frame;
    modified_fixture.frame.InputFile = 1;
    modified_fixture.frame.TextModified = true;
    try mark_ops.markCreate(allocator, modified_fixture.content_lines[0], 3, &modified_fixture.frame.Marks[types.MarkModified]);

    var session = Session{
        .current_frame = current_fixture.frame,
        .special_frames = .{},
        .command_span = undefined,
    };
    editor.screen.Frame = current_fixture.frame;

    interactive_io.testing.installInput("N");
    defer interactive_io.testing.clearInput();

    try std.testing.expect(!try confirmQuitRequest(&editor, allocator, &session));
    try std.testing.expect(session.current_frame == modified_fixture.frame);
    try std.testing.expect(editor.screen.Frame == modified_fixture.frame);
    try std.testing.expect(modified_fixture.frame.Dot != null);
    try std.testing.expect(modified_fixture.frame.Marks[types.MarkModified] != null);
    try std.testing.expect(modified_fixture.frame.Dot.?.Line == modified_fixture.frame.Marks[types.MarkModified].?.Line);
    try std.testing.expectEqual(modified_fixture.frame.Marks[types.MarkModified].?.Col, modified_fixture.frame.Dot.?.Col);
}

test "interactive quit confirmation accepts more-context replies without extra beep" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    editor.ludwig_mode = .LudwigScreen;
    editor.terminal_info = .{ .Width = 80, .Height = 10 };

    const current_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"current"});
    const modified_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "abc",
        "line2",
        "line3",
        "line4",
        "line5",
        "line6",
    });

    const current_span = try allocator.create(types.SpanObject);
    const modified_span = try allocator.create(types.SpanObject);
    current_span.* = .{
        .Name = "CURRENT",
        .Frame = current_fixture.frame,
        .FLink = modified_span,
    };
    modified_span.* = .{
        .Name = "WORK",
        .Frame = modified_fixture.frame,
        .BLink = current_span,
    };
    editor.first_span = current_span;
    current_fixture.frame.Span = current_span;
    modified_fixture.frame.Span = modified_span;

    const input_file = try allocator.create(types.FileObject);
    input_file.* = .{ .Filename = "input.txt" };
    editor.files[1] = input_file;
    editor.files_frames[1] = modified_fixture.frame;
    modified_fixture.frame.InputFile = 1;
    modified_fixture.frame.TextModified = true;
    try mark_ops.markCreate(allocator, modified_fixture.content_lines[0], 2, &modified_fixture.frame.Marks[types.MarkModified]);

    var session = Session{
        .current_frame = current_fixture.frame,
        .special_frames = .{},
        .command_span = undefined,
    };
    editor.screen.Frame = current_fixture.frame;

    interactive_io.testing.installInput("MQ");
    defer interactive_io.testing.clearInput();
    interactive_io.resetTestBeepCount();

    try std.testing.expect(!try confirmQuitRequest(&editor, allocator, &session));
    try std.testing.expectEqual(@as(usize, 1), interactive_io.getTestBeepCount());
}

test "interactive run beeps on command failure" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    editor.ludwig_mode = .LudwigScreen;
    editor.terminal_info = .{ .Width = 80, .Height = 24 };

    const frame = (try frame_ops.frameEdit(&editor, allocator, null, types.DefaultFrameName)).?;
    const command_span = try allocator.create(types.SpanObject);
    command_span.* = .{ .Name = command_span_name };

    var session = Session{
        .current_frame = frame,
        .special_frames = .{},
        .command_span = command_span,
    };

    interactive_io.testing.installInput("\\fk\\q");
    defer interactive_io.testing.clearInput();
    interactive_io.resetTestBeepCount();

    try run(&editor, allocator, &session);
    try std.testing.expectEqual(@as(usize, 1), interactive_io.getTestBeepCount());
}
