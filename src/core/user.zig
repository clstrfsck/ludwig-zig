const std = @import("std");
const chars = @import("chars.zig");
const code_store = @import("code_store.zig");
const interactive_io = @import("../platform/interactive_io.zig");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const state = @import("state.zig");
const str_object = @import("str_object.zig");
const terminal = @import("../ui/terminal/ncurses.zig");
const text = @import("text.zig");
const types = @import("types.zig");

const nonprintable_introducer_message = "Command Introducer is not printable";
const curses = terminal.c;

fn specialCommand(cmd: types.Commands) bool {
    return switch (cmd) {
        .CmdVerify,
        .CmdExitAbort,
        .CmdExitFail,
        .CmdExitSuccess,
        => true,
        else => false,
    };
}

pub fn UserKeyCodeToName(editor: *const state.Editor, key_code: isize) ?[]const u8 {
    for (editor.KeyNameList.items) |entry| {
        if (entry.KeyCode == key_code) {
            return entry.KeyName;
        }
    }
    return null;
}

pub fn UserKeyNameToCode(editor: *const state.Editor, key_name: []const u8) ?isize {
    for (editor.KeyNameList.items) |entry| {
        if (std.mem.eql(u8, entry.KeyName, key_name)) {
            return entry.KeyCode;
        }
    }
    return null;
}

pub fn ResolveUserKeyCode(editor: *const state.Editor, key: *const types.TParObject) ?isize {
    if (key.Str == null or key.Len <= 0) {
        return null;
    }
    if (key.Len == 1) {
        return key.Str.?.get(1);
    }
    return UserKeyNameToCode(editor, key.Str.?.slice(1, key.Len));
}

fn ensureKeyName(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    key_name: []const u8,
    key_code: isize,
) !void {
    for (editor.KeyNameList.items) |entry| {
        if (std.mem.eql(u8, entry.KeyName, key_name)) {
            return;
        }
    }
    try editor.KeyNameList.append(allocator, .{
        .KeyName = key_name,
        .KeyCode = key_code,
    });
}

fn registerKey(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    key_name: []const u8,
    key_code: isize,
    command: ?types.Commands,
    prompt: bool,
) !void {
    if (key_code < 0 or key_code >= @as(isize, @intCast(types.LookupCount))) {
        return;
    }

    try ensureKeyName(editor, allocator, key_name, key_code);
    if (command) |cmd| {
        const binding = &editor.Lookup[@intCast(key_code)];
        binding.Command = cmd;
        if (prompt and binding.Tpar == null) {
            binding.Tpar = try newPromptTpar(allocator);
        }
    }
}

fn newPromptTpar(allocator: std.mem.Allocator) !*types.TParObject {
    const tpar = try allocator.create(types.TParObject);
    tpar.* = .{
        .Str = try str_object.newBlankStrObject(allocator, 0),
        .Dlm = types.TpdPrompt,
    };
    return tpar;
}

fn emitMessage(editor: *const state.Editor, message: []const u8) void {
    if (editor.LudwigMode == .LudwigScreen) {
        interactive_io.queueStatusMessage(message);
    }
}

fn registerControlKeyNames(editor: *state.Editor, allocator: std.mem.Allocator) !void {
    var i: u8 = 1;
    while (i <= 32) : (i += 1) {
        const key_code: isize = i - 1;
        const key_name = switch (i) {
            9 => "BACKSPACE",
            10 => "TAB",
            11 => "LINE-FEED",
            14 => "RETURN",
            else => try std.fmt.allocPrint(allocator, "CONTROL-{c}", .{@as(u8, '@') + i - 1}),
        };
        try registerKey(editor, allocator, key_name, key_code, null, false);
    }
    try registerKey(editor, allocator, "DELETE", 127, null, false);
}

fn registerFunctionKeyNames(editor: *state.Editor, allocator: std.mem.Allocator) !void {
    if (!@hasDecl(curses, "KEY_F0")) {
        return;
    }

    inline for (0..13) |n| {
        const key_code = curses.KEY_F0 + @as(c_int, @intCast(n));
        if (key_code <= curses.KEY_MAX) {
            const key_name = try std.fmt.allocPrint(allocator, "FUNCTION-{d}", .{n});
            try registerKey(editor, allocator, key_name, key_code, null, false);
        }
    }
    inline for (1..13) |n| {
        const key_code = curses.KEY_F0 + @as(c_int, @intCast(12 + n));
        if (key_code <= curses.KEY_MAX) {
            const key_name = try std.fmt.allocPrint(allocator, "SHIFT-FUNCTION-{d}", .{n});
            try registerKey(editor, allocator, key_name, key_code, null, false);
        }
    }
    inline for (25..64) |n| {
        const key_code = curses.KEY_F0 + @as(c_int, @intCast(n));
        if (key_code <= curses.KEY_MAX) {
            const key_name = try std.fmt.allocPrint(allocator, "FUNCTION-{d}", .{n});
            try registerKey(editor, allocator, key_name, key_code, null, false);
        }
    }
}

fn registerCursesAliases(editor: *state.Editor, allocator: std.mem.Allocator) !void {
    const extra_keys = [_]struct {
        key_name: []const u8,
        decl_name: []const u8,
    }{
        .{ .key_name = "BREAK", .decl_name = "KEY_BREAK" },
        .{ .key_name = "EIC", .decl_name = "KEY_EIC" },
        .{ .key_name = "CLEAR", .decl_name = "KEY_CLEAR" },
        .{ .key_name = "CLEAR-EOS", .decl_name = "KEY_EOS" },
        .{ .key_name = "CLEAR-EOL", .decl_name = "KEY_EOL" },
        .{ .key_name = "SCROLL-FORWARD", .decl_name = "KEY_SF" },
        .{ .key_name = "SCROLL-REVERSE", .decl_name = "KEY_SR" },
        .{ .key_name = "SET-TAB", .decl_name = "KEY_STAB" },
        .{ .key_name = "CLEAR-TAB", .decl_name = "KEY_CTAB" },
        .{ .key_name = "CLEAR-ALL-TABS", .decl_name = "KEY_CATAB" },
        .{ .key_name = "SEND", .decl_name = "KEY_SEND" },
        .{ .key_name = "SOFT-RESET", .decl_name = "KEY_SRESET" },
        .{ .key_name = "RESET", .decl_name = "KEY_RESET" },
        .{ .key_name = "PRINT", .decl_name = "KEY_PRINT" },
        .{ .key_name = "LOWER-LEFT", .decl_name = "KEY_LL" },
        .{ .key_name = "KEY-A1", .decl_name = "KEY_A1" },
        .{ .key_name = "KEY-A3", .decl_name = "KEY_A3" },
        .{ .key_name = "KEY-B2", .decl_name = "KEY_B2" },
        .{ .key_name = "KEY-C1", .decl_name = "KEY_C1" },
        .{ .key_name = "KEY-C3", .decl_name = "KEY_C3" },
        .{ .key_name = "BEGIN", .decl_name = "KEY_BEG" },
        .{ .key_name = "CANCEL", .decl_name = "KEY_CANCEL" },
        .{ .key_name = "CLOSE", .decl_name = "KEY_CLOSE" },
        .{ .key_name = "COMMAND", .decl_name = "KEY_COMMAND" },
        .{ .key_name = "COPY", .decl_name = "KEY_COPY" },
        .{ .key_name = "CREATE", .decl_name = "KEY_CREATE" },
        .{ .key_name = "END", .decl_name = "KEY_END" },
        .{ .key_name = "EXIT", .decl_name = "KEY_EXIT" },
        .{ .key_name = "MARK", .decl_name = "KEY_MARK" },
        .{ .key_name = "MESSAGE", .decl_name = "KEY_MESSAGE" },
        .{ .key_name = "MOVE", .decl_name = "KEY_MOVE" },
        .{ .key_name = "NEXT", .decl_name = "KEY_NEXT" },
        .{ .key_name = "OPEN", .decl_name = "KEY_OPEN" },
        .{ .key_name = "OPTIONS", .decl_name = "KEY_OPTIONS" },
        .{ .key_name = "PREVIOUS", .decl_name = "KEY_PREVIOUS" },
        .{ .key_name = "REDO", .decl_name = "KEY_REDO" },
        .{ .key_name = "REFERENCE", .decl_name = "KEY_REFERENCE" },
        .{ .key_name = "REFRESH", .decl_name = "KEY_REFRESH" },
        .{ .key_name = "REPLACE", .decl_name = "KEY_REPLACE" },
        .{ .key_name = "RESTART", .decl_name = "KEY_RESTART" },
        .{ .key_name = "RESUME", .decl_name = "KEY_RESUME" },
        .{ .key_name = "SAVE", .decl_name = "KEY_SAVE" },
        .{ .key_name = "SHIFT-BEGIN", .decl_name = "KEY_SBEG" },
        .{ .key_name = "SHIFT-CANCEL", .decl_name = "KEY_SCANCEL" },
        .{ .key_name = "SHIFT-COMMAND", .decl_name = "KEY_SCOMMAND" },
        .{ .key_name = "SHIFT-COPY", .decl_name = "KEY_SCOPY" },
        .{ .key_name = "SHIFT-CREATE", .decl_name = "KEY_SCREATE" },
        .{ .key_name = "SHIFT-DELETE-CHAR", .decl_name = "KEY_SDC" },
        .{ .key_name = "SHIFT-DELETE-LINE", .decl_name = "KEY_SDL" },
        .{ .key_name = "SELECT", .decl_name = "KEY_SELECT" },
        .{ .key_name = "SHIFT-CLEAR-EOL", .decl_name = "KEY_SEOL" },
        .{ .key_name = "SHIFT-EXIT", .decl_name = "KEY_SEXIT" },
        .{ .key_name = "SHIFT-FIND", .decl_name = "KEY_SFIND" },
        .{ .key_name = "SHIFT-HELP", .decl_name = "KEY_SHELP" },
        .{ .key_name = "SHIFT-HOME", .decl_name = "KEY_SHOME" },
        .{ .key_name = "SHIFT-INSERT-CHAR", .decl_name = "KEY_SIC" },
        .{ .key_name = "SHIFT-LEFT", .decl_name = "KEY_SLEFT" },
        .{ .key_name = "SHIFT-MESSAGE", .decl_name = "KEY_SMESSAGE" },
        .{ .key_name = "SHIFT-MOVE", .decl_name = "KEY_SMOVE" },
        .{ .key_name = "SHIFT-NEXT", .decl_name = "KEY_SNEXT" },
        .{ .key_name = "SHIFT-OPTIONS", .decl_name = "KEY_SOPTIONS" },
        .{ .key_name = "SHIFT-PREVIOUS", .decl_name = "KEY_SPREVIOUS" },
        .{ .key_name = "SHIFT-PRINT", .decl_name = "KEY_SPRINT" },
        .{ .key_name = "SHIFT-REDO", .decl_name = "KEY_SREDO" },
        .{ .key_name = "SHIFT-REPLACE", .decl_name = "KEY_SREPLACE" },
        .{ .key_name = "SHIFT-RIGHT", .decl_name = "KEY_SRIGHT" },
        .{ .key_name = "SHIFT-RESUME", .decl_name = "KEY_SRSUME" },
        .{ .key_name = "SHIFT-SAVE", .decl_name = "KEY_SSAVE" },
        .{ .key_name = "SHIFT-SUSPEND", .decl_name = "KEY_SSUSPEND" },
        .{ .key_name = "SHIFT-UNDO", .decl_name = "KEY_SUNDO" },
        .{ .key_name = "SUSPEND", .decl_name = "KEY_SUSPEND" },
        .{ .key_name = "UNDO", .decl_name = "KEY_UNDO" },
        .{ .key_name = "MOUSE", .decl_name = "KEY_MOUSE" },
        .{ .key_name = "SOME-OTHER-EVENT", .decl_name = "KEY_EVENT" },
    };

    inline for (extra_keys) |entry| {
        if (@hasDecl(curses, entry.decl_name)) {
            try registerKey(editor, allocator, entry.key_name, @field(curses, entry.decl_name), null, false);
        }
    }
}

pub fn UserKeyInitialize(editor: *state.Editor, allocator: std.mem.Allocator) !void {
    const terminal_keys = [_]struct {
        name: []const u8,
        code: isize,
        command: types.Commands,
        prompt: bool = false,
    }{
        .{ .name = "UP-ARROW", .code = types.TerminalKeyCodes.UpArrow, .command = .CmdUp },
        .{ .name = "DOWN-ARROW", .code = types.TerminalKeyCodes.DownArrow, .command = .CmdDown },
        .{ .name = "LEFT-ARROW", .code = types.TerminalKeyCodes.LeftArrow, .command = .CmdLeft },
        .{ .name = "RIGHT-ARROW", .code = types.TerminalKeyCodes.RightArrow, .command = .CmdRight },
        .{ .name = "HOME", .code = types.TerminalKeyCodes.Home, .command = .CmdHome },
        .{ .name = "BACK-TAB", .code = types.TerminalKeyCodes.BackTab, .command = .CmdBacktab },
        .{ .name = "INSERT-LINE", .code = types.TerminalKeyCodes.InsertLine, .command = .CmdInsertLine },
        .{ .name = "DELETE-LINE", .code = types.TerminalKeyCodes.DeleteLine, .command = .CmdDeleteLine },
        .{ .name = "INSERT-CHAR", .code = types.TerminalKeyCodes.InsertChar, .command = .CmdInsertChar },
        .{ .name = "DELETE-CHAR", .code = types.TerminalKeyCodes.DeleteChar, .command = .CmdDeleteChar },
        .{ .name = "PAGE-UP", .code = types.TerminalKeyCodes.PageUp, .command = .CmdWindowBackward },
        .{ .name = "PREV-SCREEN", .code = types.TerminalKeyCodes.PageUp, .command = .CmdWindowBackward },
        .{ .name = "PAGE-DOWN", .code = types.TerminalKeyCodes.PageDown, .command = .CmdWindowForward },
        .{ .name = "NEXT-SCREEN", .code = types.TerminalKeyCodes.PageDown, .command = .CmdWindowForward },
        .{ .name = "FIND", .code = types.TerminalKeyCodes.Find, .command = .CmdGet, .prompt = true },
        .{ .name = "HELP", .code = types.TerminalKeyCodes.Help, .command = .CmdHelp, .prompt = true },
        .{ .name = "WINDOW-RESIZE-EVENT", .code = types.TerminalKeyCodes.WindowResize, .command = .CmdResizeWindow },
    };

    try registerControlKeyNames(editor, allocator);
    for (terminal_keys) |entry| {
        try registerKey(editor, allocator, entry.name, entry.code, entry.command, entry.prompt);
    }
    try registerFunctionKeyNames(editor, allocator);
    try registerCursesAliases(editor, allocator);
    editor.NrKeyNames = @intCast(editor.KeyNameList.items.len);
}

pub fn UserCommandIntroducer(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !bool {
    if (editor.CommandIntroducer < 0 or
        editor.CommandIntroducer > types.MaxSetRange or
        !chars.chIsPrintable(@intCast(editor.CommandIntroducer)))
    {
        emitMessage(editor, nonprintable_introducer_message);
        return false;
    }

    const temp = try str_object.newBlankStrObject(allocator, 1);
    temp.set(1, @intCast(editor.CommandIntroducer));

    const cmd_success = switch (editor.EditMode) {
        .ModeInsert => try text.TextInsert(allocator, true, 1, temp, 1, frame.Dot.?),
        .ModeCommand => if (editor.PreviousMode == .ModeInsert)
            try text.TextInsert(allocator, true, 1, temp, 1, frame.Dot.?)
        else
            try text.TextOvertype(allocator, true, 1, temp, 1, frame.Dot.?),
        .ModeOvertype => try text.TextOvertype(allocator, true, 1, temp, 1, frame.Dot.?),
    };

    if (cmd_success) {
        frame.TextModified = true;
        try mark_ops.markCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkModified]);
    }
    return cmd_success;
}

pub fn BindCompiledKey(
    editor: *state.Editor,
    key_code: isize,
    key_span: *types.SpanObject,
) bool {
    if (key_code < 0 or key_code >= @as(isize, @intCast(types.LookupCount))) {
        return false;
    }

    const binding = &editor.Lookup[@intCast(key_code)];
    if (binding.Code != null) {
        code_store.codeDiscard(editor, &binding.Code);
    }
    binding.Code = null;
    binding.Tpar = null;

    const code = key_span.Code orelse return false;
    const first = &editor.CompilerCode[@intCast(code.Code)];
    if (code.Len == 2 and first.Rep == .LeadParamNone and !specialCommand(first.Op)) {
        binding.Command = first.Op;
        binding.Tpar = first.Tpar;
        first.Tpar = null;
    } else {
        binding.Command = .CmdExtended;
        binding.Code = code;
        key_span.Code = null;
    }
    return true;
}

pub fn UserUndo() bool {
    return false;
}

test "user key lookup uses editor key name list" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    try editor.KeyNameList.append(allocator, .{
        .KeyName = "TAB",
        .KeyCode = 9,
    });

    try std.testing.expectEqualStrings("TAB", UserKeyCodeToName(&editor, 9).?);
    try std.testing.expectEqual(@as(?isize, 9), UserKeyNameToCode(&editor, "TAB"));

    const named = try str_object.newStrObjectFrom(allocator, "TAB");
    var named_tpar = types.TParObject{
        .Str = named,
        .Len = 3,
    };
    try std.testing.expectEqual(@as(?isize, 9), ResolveUserKeyCode(&editor, &named_tpar));

    const literal = try str_object.newStrObjectFrom(allocator, "A");
    var literal_tpar = types.TParObject{
        .Str = literal,
        .Len = 1,
    };
    try std.testing.expectEqual(@as(?isize, 'A'), ResolveUserKeyCode(&editor, &literal_tpar));
}

test "user command introducer inserts in insert mode" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"ab"});
    editor.CommandIntroducer = '@';
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 2, &fixture.frame.Dot);

    try std.testing.expect(try UserCommandIntroducer(&editor, allocator, fixture.frame));
    try std.testing.expectEqualStrings("a@b", line_ops.getLineContent(fixture.content_lines[0]));
    try std.testing.expectEqual(@as(isize, 3), fixture.frame.Dot.?.Col);
    try std.testing.expect(fixture.frame.TextModified);
    try std.testing.expect(fixture.frame.Marks[types.MarkModified] != null);
}

test "user command introducer overtypes in command mode after overtype" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"ab"});
    editor.CommandIntroducer = '@';
    editor.EditMode = .ModeCommand;
    editor.PreviousMode = .ModeOvertype;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 2, &fixture.frame.Dot);

    try std.testing.expect(try UserCommandIntroducer(&editor, allocator, fixture.frame));
    try std.testing.expectEqualStrings("a@", line_ops.getLineContent(fixture.content_lines[0]));
    try std.testing.expectEqual(@as(isize, 3), fixture.frame.Dot.?.Col);
}

test "user command introducer rejects non-printable introducer" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"ab"});
    editor.CommandIntroducer = 7;
    try std.testing.expect(!(try UserCommandIntroducer(&editor, allocator, fixture.frame)));
}

test "user key initialize binds terminal navigation keys" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();

    try UserKeyInitialize(&editor, editor.allocator());

    try std.testing.expectEqual(types.Commands.CmdUp, editor.Lookup[@intCast(types.TerminalKeyCodes.UpArrow)].Command);
    try std.testing.expectEqual(types.Commands.CmdDown, editor.Lookup[@intCast(types.TerminalKeyCodes.DownArrow)].Command);
    try std.testing.expectEqual(types.Commands.CmdLeft, editor.Lookup[@intCast(types.TerminalKeyCodes.LeftArrow)].Command);
    try std.testing.expectEqual(types.Commands.CmdRight, editor.Lookup[@intCast(types.TerminalKeyCodes.RightArrow)].Command);
    try std.testing.expectEqual(types.Commands.CmdHome, editor.Lookup[@intCast(types.TerminalKeyCodes.Home)].Command);
    try std.testing.expectEqual(types.Commands.CmdBacktab, editor.Lookup[@intCast(types.TerminalKeyCodes.BackTab)].Command);
    try std.testing.expectEqual(types.Commands.CmdInsertLine, editor.Lookup[@intCast(types.TerminalKeyCodes.InsertLine)].Command);
    try std.testing.expectEqual(types.Commands.CmdDeleteLine, editor.Lookup[@intCast(types.TerminalKeyCodes.DeleteLine)].Command);
    try std.testing.expectEqual(types.Commands.CmdWindowBackward, editor.Lookup[@intCast(types.TerminalKeyCodes.PageUp)].Command);
    try std.testing.expectEqual(types.Commands.CmdWindowForward, editor.Lookup[@intCast(types.TerminalKeyCodes.PageDown)].Command);
    try std.testing.expectEqual(types.Commands.CmdGet, editor.Lookup[@intCast(types.TerminalKeyCodes.Find)].Command);
    try std.testing.expectEqual(types.Commands.CmdHelp, editor.Lookup[@intCast(types.TerminalKeyCodes.Help)].Command);
    try std.testing.expectEqual(types.Commands.CmdResizeWindow, editor.Lookup[@intCast(types.TerminalKeyCodes.WindowResize)].Command);
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.UpArrow), UserKeyNameToCode(&editor, "UP-ARROW"));
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.PageUp), UserKeyNameToCode(&editor, "PREV-SCREEN"));
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.PageDown), UserKeyNameToCode(&editor, "NEXT-SCREEN"));
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.Find), UserKeyNameToCode(&editor, "FIND"));
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.Help), UserKeyNameToCode(&editor, "HELP"));
    try std.testing.expect(editor.Lookup[@intCast(types.TerminalKeyCodes.Find)].Tpar != null);
    try std.testing.expect(editor.Lookup[@intCast(types.TerminalKeyCodes.Help)].Tpar != null);
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.WindowResize), UserKeyNameToCode(&editor, "WINDOW-RESIZE-EVENT"));
    try std.testing.expectEqual(@as(?isize, 1), UserKeyNameToCode(&editor, "CONTROL-A"));
    try std.testing.expectEqual(@as(?isize, 127), UserKeyNameToCode(&editor, "DELETE"));
    try std.testing.expectEqual(@as(?isize, curses.KEY_F0 + 1), UserKeyNameToCode(&editor, "FUNCTION-1"));
    try std.testing.expectEqual(@as(?isize, curses.KEY_F0 + 13), UserKeyNameToCode(&editor, "SHIFT-FUNCTION-1"));
    try std.testing.expect(types.TerminalKeyCodes.PageDown != curses.KEY_F0 + 1);
    try std.testing.expectEqualStrings("FUNCTION-1", UserKeyCodeToName(&editor, curses.KEY_F0 + 1).?);
    try std.testing.expectEqualStrings("PAGE-DOWN", UserKeyCodeToName(&editor, types.TerminalKeyCodes.PageDown).?);
    try std.testing.expect(editor.NrKeyNames > 0);
}
