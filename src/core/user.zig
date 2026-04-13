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
        .Cmdexit_abort,
        .CmdExitFail,
        .CmdExitSuccess,
        => true,
        else => false,
    };
}

pub fn userKeyCodeToName(editor: *const state.Editor, key_code: isize) ?[]const u8 {
    for (editor.key_name_list.items) |entry| {
        if (entry.key_code == key_code) {
            return entry.key_name;
        }
    }
    return null;
}

pub fn userKeyNameToCode(editor: *const state.Editor, key_name: []const u8) ?isize {
    for (editor.key_name_list.items) |entry| {
        if (std.mem.eql(u8, entry.key_name, key_name)) {
            return entry.key_code;
        }
    }
    return null;
}

pub fn resolveUserKeyCode(editor: *const state.Editor, key: *const types.TParObject) ?isize {
    if (key.str == null or key.len <= 0) {
        return null;
    }
    if (key.len == 1) {
        return key.str.?.get(1);
    }
    return userKeyNameToCode(editor, key.str.?.slice(1, key.len));
}

fn ensureKeyName(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    key_name: []const u8,
    key_code: isize,
) !void {
    for (editor.key_name_list.items) |entry| {
        if (std.mem.eql(u8, entry.key_name, key_name)) {
            return;
        }
    }
    try editor.key_name_list.append(allocator, .{
        .key_name = key_name,
        .key_code = key_code,
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
    if (key_code < 0 or key_code >= @as(isize, @intCast(types.lookup_count))) {
        return;
    }

    try ensureKeyName(editor, allocator, key_name, key_code);
    if (command) |cmd| {
        const binding = &editor.lookup[@intCast(key_code)];
        binding.command = cmd;
        if (prompt and binding.tpar == null) {
            binding.tpar = try newPromptTpar(allocator);
        }
    }
}

fn newPromptTpar(allocator: std.mem.Allocator) !*types.TParObject {
    const tpar = try allocator.create(types.TParObject);
    tpar.* = .{
        .str = try str_object.newBlankStrObject(allocator, 0),
        .dlm = types.tpd_prompt,
    };
    return tpar;
}

fn emitMessage(editor: *const state.Editor, message: []const u8) void {
    if (editor.ludwig_mode == .ludwig_screen) {
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

pub fn userKeyInitialize(editor: *state.Editor, allocator: std.mem.Allocator) !void {
    const terminal_keys = [_]struct {
        name: []const u8,
        code: isize,
        command: types.Commands,
        prompt: bool = false,
    }{
        .{ .name = "UP-ARROW", .code = types.terminal_key_codes.up_arrow, .command = .CmdUp },
        .{ .name = "DOWN-ARROW", .code = types.terminal_key_codes.down_arrow, .command = .CmdDown },
        .{ .name = "LEFT-ARROW", .code = types.terminal_key_codes.left_arrow, .command = .CmdLeft },
        .{ .name = "RIGHT-ARROW", .code = types.terminal_key_codes.right_arrow, .command = .CmdRight },
        .{ .name = "HOME", .code = types.terminal_key_codes.home, .command = .CmdHome },
        .{ .name = "BACK-TAB", .code = types.terminal_key_codes.back_tab, .command = .CmdBacktab },
        .{ .name = "INSERT-LINE", .code = types.terminal_key_codes.insert_line, .command = .CmdInsertLine },
        .{ .name = "DELETE-LINE", .code = types.terminal_key_codes.delete_line, .command = .CmdDeleteLine },
        .{ .name = "INSERT-CHAR", .code = types.terminal_key_codes.insert_char, .command = .CmdInsertChar },
        .{ .name = "DELETE-CHAR", .code = types.terminal_key_codes.delete_char, .command = .CmdDeleteChar },
        .{ .name = "PAGE-UP", .code = types.terminal_key_codes.page_up, .command = .CmdWindowBackward },
        .{ .name = "PREV-SCREEN", .code = types.terminal_key_codes.page_up, .command = .CmdWindowBackward },
        .{ .name = "PAGE-DOWN", .code = types.terminal_key_codes.page_down, .command = .CmdWindowForward },
        .{ .name = "NEXT-SCREEN", .code = types.terminal_key_codes.page_down, .command = .CmdWindowForward },
        .{ .name = "FIND", .code = types.terminal_key_codes.find, .command = .CmdGet, .prompt = true },
        .{ .name = "HELP", .code = types.terminal_key_codes.help, .command = .CmdHelp, .prompt = true },
        .{ .name = "WINDOW-RESIZE-EVENT", .code = types.terminal_key_codes.window_resize, .command = .CmdResizeWindow },
    };

    try registerControlKeyNames(editor, allocator);
    for (terminal_keys) |entry| {
        try registerKey(editor, allocator, entry.name, entry.code, entry.command, entry.prompt);
    }
    try registerFunctionKeyNames(editor, allocator);
    try registerCursesAliases(editor, allocator);
    editor.num_key_names = @intCast(editor.key_name_list.items.len);
}

pub fn userCommandIntroducer(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !bool {
    if (editor.command_introducer < 0 or
        editor.command_introducer > types.max_set_range or
        !chars.chIsPrintable(@intCast(editor.command_introducer)))
    {
        emitMessage(editor, nonprintable_introducer_message);
        return false;
    }

    const temp = try str_object.newBlankStrObject(allocator, 1);
    temp.set(1, @intCast(editor.command_introducer));

    const cmd_success = switch (editor.edit_mode) {
        .mode_insert => try text.textInsert(allocator, true, 1, temp, 1, frame.dot.?),
        .mode_command => if (editor.previous_mode == .mode_insert)
            try text.textInsert(allocator, true, 1, temp, 1, frame.dot.?)
        else
            try text.textOvertype(allocator, true, 1, temp, 1, frame.dot.?),
        .mode_overtype => try text.textOvertype(allocator, true, 1, temp, 1, frame.dot.?),
    };

    if (cmd_success) {
        frame.text_modified = true;
        try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col, &frame.marks[types.mark_modified]);
    }
    return cmd_success;
}

pub fn bindCompiledKey(
    editor: *state.Editor,
    key_code: isize,
    key_span: *types.SpanObject,
) bool {
    if (key_code < 0 or key_code >= @as(isize, @intCast(types.lookup_count))) {
        return false;
    }

    const binding = &editor.lookup[@intCast(key_code)];
    if (binding.code != null) {
        code_store.codeDiscard(editor, &binding.code);
    }
    binding.code = null;
    binding.tpar = null;

    const code = key_span.code orelse return false;
    const first = &editor.compiler_code[@intCast(code.code)];
    if (code.len == 2 and first.rep == .lead_param_none and !specialCommand(first.op)) {
        binding.command = first.op;
        binding.tpar = first.tpar;
        first.tpar = null;
    } else {
        binding.command = .CmdExtended;
        binding.code = code;
        key_span.code = null;
    }
    return true;
}

test "user key lookup uses editor key name list" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    try editor.key_name_list.append(allocator, .{
        .key_name = "TAB",
        .key_code = 9,
    });

    try std.testing.expectEqualStrings("TAB", userKeyCodeToName(&editor, 9).?);
    try std.testing.expectEqual(@as(?isize, 9), userKeyNameToCode(&editor, "TAB"));

    const named = try str_object.newStrObjectFrom(allocator, "TAB");
    var named_tpar = types.TParObject{
        .str = named,
        .len = 3,
    };
    try std.testing.expectEqual(@as(?isize, 9), resolveUserKeyCode(&editor, &named_tpar));

    const literal = try str_object.newStrObjectFrom(allocator, "A");
    var literal_tpar = types.TParObject{
        .str = literal,
        .len = 1,
    };
    try std.testing.expectEqual(@as(?isize, 'A'), resolveUserKeyCode(&editor, &literal_tpar));
}

test "user command introducer inserts in insert mode" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"ab"});
    editor.command_introducer = '@';
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 2, &fixture.frame.dot);

    try std.testing.expect(try userCommandIntroducer(&editor, allocator, fixture.frame));
    try std.testing.expectEqualStrings("a@b", line_ops.getLineContent(fixture.content_lines[0]));
    try std.testing.expectEqual(@as(isize, 3), fixture.frame.dot.?.col);
    try std.testing.expect(fixture.frame.text_modified);
    try std.testing.expect(fixture.frame.marks[types.mark_modified] != null);
}

test "user command introducer overtypes in command mode after overtype" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"ab"});
    editor.command_introducer = '@';
    editor.edit_mode = .mode_command;
    editor.previous_mode = .mode_overtype;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 2, &fixture.frame.dot);

    try std.testing.expect(try userCommandIntroducer(&editor, allocator, fixture.frame));
    try std.testing.expectEqualStrings("a@", line_ops.getLineContent(fixture.content_lines[0]));
    try std.testing.expectEqual(@as(isize, 3), fixture.frame.dot.?.col);
}

test "user command introducer rejects non-printable introducer" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"ab"});
    editor.command_introducer = 7;
    try std.testing.expect(!(try userCommandIntroducer(&editor, allocator, fixture.frame)));
}

test "user key initialize binds terminal navigation keys" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();

    try userKeyInitialize(&editor, editor.allocator());

    try std.testing.expectEqual(types.Commands.CmdUp, editor.lookup[@intCast(types.terminal_key_codes.up_arrow)].command);
    try std.testing.expectEqual(types.Commands.CmdDown, editor.lookup[@intCast(types.terminal_key_codes.down_arrow)].command);
    try std.testing.expectEqual(types.Commands.CmdLeft, editor.lookup[@intCast(types.terminal_key_codes.left_arrow)].command);
    try std.testing.expectEqual(types.Commands.CmdRight, editor.lookup[@intCast(types.terminal_key_codes.right_arrow)].command);
    try std.testing.expectEqual(types.Commands.CmdHome, editor.lookup[@intCast(types.terminal_key_codes.home)].command);
    try std.testing.expectEqual(types.Commands.CmdBacktab, editor.lookup[@intCast(types.terminal_key_codes.back_tab)].command);
    try std.testing.expectEqual(types.Commands.CmdInsertLine, editor.lookup[@intCast(types.terminal_key_codes.insert_line)].command);
    try std.testing.expectEqual(types.Commands.CmdDeleteLine, editor.lookup[@intCast(types.terminal_key_codes.delete_line)].command);
    try std.testing.expectEqual(types.Commands.CmdWindowBackward, editor.lookup[@intCast(types.terminal_key_codes.page_up)].command);
    try std.testing.expectEqual(types.Commands.CmdWindowForward, editor.lookup[@intCast(types.terminal_key_codes.page_down)].command);
    try std.testing.expectEqual(types.Commands.CmdGet, editor.lookup[@intCast(types.terminal_key_codes.find)].command);
    try std.testing.expectEqual(types.Commands.CmdHelp, editor.lookup[@intCast(types.terminal_key_codes.help)].command);
    try std.testing.expectEqual(types.Commands.CmdResizeWindow, editor.lookup[@intCast(types.terminal_key_codes.window_resize)].command);
    try std.testing.expectEqual(@as(?isize, types.terminal_key_codes.up_arrow), userKeyNameToCode(&editor, "UP-ARROW"));
    try std.testing.expectEqual(@as(?isize, types.terminal_key_codes.page_up), userKeyNameToCode(&editor, "PREV-SCREEN"));
    try std.testing.expectEqual(@as(?isize, types.terminal_key_codes.page_down), userKeyNameToCode(&editor, "NEXT-SCREEN"));
    try std.testing.expectEqual(@as(?isize, types.terminal_key_codes.find), userKeyNameToCode(&editor, "FIND"));
    try std.testing.expectEqual(@as(?isize, types.terminal_key_codes.help), userKeyNameToCode(&editor, "HELP"));
    try std.testing.expect(editor.lookup[@intCast(types.terminal_key_codes.find)].tpar != null);
    try std.testing.expect(editor.lookup[@intCast(types.terminal_key_codes.help)].tpar != null);
    try std.testing.expectEqual(@as(?isize, types.terminal_key_codes.window_resize), userKeyNameToCode(&editor, "WINDOW-RESIZE-EVENT"));
    try std.testing.expectEqual(@as(?isize, 1), userKeyNameToCode(&editor, "CONTROL-A"));
    try std.testing.expectEqual(@as(?isize, 127), userKeyNameToCode(&editor, "DELETE"));
    try std.testing.expectEqual(@as(?isize, curses.KEY_F0 + 1), userKeyNameToCode(&editor, "FUNCTION-1"));
    try std.testing.expectEqual(@as(?isize, curses.KEY_F0 + 13), userKeyNameToCode(&editor, "SHIFT-FUNCTION-1"));
    try std.testing.expect(types.terminal_key_codes.page_down != curses.KEY_F0 + 1);
    try std.testing.expectEqualStrings("FUNCTION-1", userKeyCodeToName(&editor, curses.KEY_F0 + 1).?);
    try std.testing.expectEqualStrings("PAGE-DOWN", userKeyCodeToName(&editor, types.terminal_key_codes.page_down).?);
    try std.testing.expect(editor.num_key_names > 0);
}
