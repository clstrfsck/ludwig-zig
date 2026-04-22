const builtin = @import("builtin");
const std = @import("std");
const command_tables = @import("command_tables.zig");
const defaults = @import("defaults.zig");
const str_object = @import("str_object.zig");
const types = @import("types.zig");

pub const Editor = struct {
    base_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    io: std.Io,
    env: std.process.Environ.Map,
    program_directory: []const u8 = "",
    tt_control_c: bool = false,
    tt_win_changed: bool = false,
    num_key_names: isize = 0,
    key_name_list: std.ArrayList(types.KeyNameRecord) = .empty,
    key_introducers: std.StaticBitSet(types.lookup_count) = std.StaticBitSet(types.lookup_count).initEmpty(),
    ludwig_aborted: bool = false,
    exit_abort: bool = false,
    vdu_free_flag: bool = false,
    hangup: bool = false,
    quit_requested: bool = false,
    batch_output_enabled: bool = !builtin.is_test,
    edit_mode: types.ModeType = .mode_insert,
    previous_mode: types.ModeType = .mode_insert,
    files: [types.max_files + 1]?*types.FileObject = [_]?*types.FileObject{null} ** (types.max_files + 1),
    files_frames: [types.max_files + 1]?*types.FrameObject = [_]?*types.FrameObject{null} ** (types.max_files + 1),
    fgi_file: isize = 0,
    fgo_file: isize = 0,
    first_span: ?*types.SpanObject = null,
    ludwig_mode: types.LudwigModeType = .ludwig_batch,
    command_introducer: isize = '\\',
    prompt_region: [types.max_tp_count + 1]types.PromptRegionAttrib = [_]types.PromptRegionAttrib{.{}} ** (types.max_tp_count + 1),
    screen: types.ScreenState = .{},
    compiler_code: [types.max_code + 1]types.CodeObject = [_]types.CodeObject{.{}} ** (types.max_code + 1),
    code_list: ?*types.CodeHeader = null,
    code_top: isize = 0,
    prefixes: std.StaticBitSet(types.command_count) = std.StaticBitSet(types.command_count).initEmpty(),
    lookup: [types.lookup_count]types.CommandObject = [_]types.CommandObject{.{}} ** types.lookup_count,
    lookup_exp: [types.lookup_exp_count]types.LookupExpType = [_]types.LookupExpType{.{}} ** types.lookup_exp_count,
    lookup_exp_ptr: [types.command_count]usize = [_]usize{0} ** types.command_count,
    cmd_attrib: [types.command_count]types.CmdAttribRec = [_]types.CmdAttribRec{.{}} ** types.command_count,
    dflt_prompts: [defaults.prompt_count][]const u8 = [_][]const u8{""} ** defaults.prompt_count,
    exec_level: isize = 0,
    initial_marks: types.MarkArray = [_]?*types.MarkObject{null} ** (types.max_mark_number + 1),
    initial_scr_height: isize = 0,
    initial_scr_width: isize = 0,
    initial_scr_offset: isize = 0,
    initial_margin_left: isize = 0,
    initial_margin_right: isize = 0,
    initial_margin_top: isize = 0,
    initial_margin_bottom: isize = 0,
    initial_tab_stops: types.TabArray = [_]bool{false} ** (types.max_str_len_p1 + 1),
    initial_options: types.FrameOptions = .{},
    blank_string: ?*str_object.StrObject = null,
    initial_verify: types.VerifyArray = [_]bool{false} ** (types.max_verify + 1),
    default_tab_stops: types.TabArray = [_]bool{false} ** (types.max_str_len_p1 + 1),
    file_data: types.FileDataType = .{},
    terminal_info: types.TerminalInfoType = .{},
    immediate_input: ?[]const u8 = null,
    immediate_input_index: usize = 0,

    pub fn allocator(self: *Editor) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn init(io: std.Io, base_allocator: std.mem.Allocator, env: std.process.Environ.Map) !Editor {
        var editor = Editor{
            .base_allocator = base_allocator,
            .arena = std.heap.ArenaAllocator.init(base_allocator),
            .io = io,
            .env = env,
        };
        defaults.setRegularTabStops(&editor, 8);
        try defaults.setupInitialValues(&editor);
        try editor.initializeCompilerHeader();
        command_tables.initializeCommandAttributes(&editor);
        command_tables.loadCommandTable(&editor, editor.file_data.old_cmds);
        return editor;
    }

    pub fn deinit(self: *Editor) void {
        self.arena.deinit();
    }

    pub fn loadCommandTable(self: *Editor, old_version: bool) void {
        self.file_data.old_cmds = old_version;
        command_tables.loadCommandTable(self, old_version);
    }

    pub fn setImmediateInput(self: *Editor, source: []const u8) !void {
        self.immediate_input = try self.allocator().dupe(u8, source);
        self.immediate_input_index = 0;
    }

    pub fn clearImmediateInput(self: *Editor) void {
        self.immediate_input = null;
        self.immediate_input_index = 0;
    }

    fn initializeCompilerHeader(self: *Editor) !void {
        self.code_top = 0;
        const code_list = try self.allocator().create(types.CodeHeader);
        code_list.* = .{
            .ref = 1,
            .code = 1,
            .len = 0,
        };
        code_list.f_link = code_list;
        code_list.b_link = code_list;
        self.code_list = code_list;
    }
};

test "editor init ports value.go defaults and compiler state" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();

    try std.testing.expectEqual(types.ModeType.mode_insert, editor.edit_mode);
    try std.testing.expectEqual(types.ModeType.mode_insert, editor.previous_mode);
    try std.testing.expectEqual(types.LudwigModeType.ludwig_batch, editor.ludwig_mode);
    try std.testing.expectEqual(@as(isize, '\\'), editor.command_introducer);
    try std.testing.expectEqual(types.max_int, editor.screen.msg_row);
    try std.testing.expect(editor.screen.stdin_reader_initialized);
    try std.testing.expect(!editor.quit_requested);
    try std.testing.expect(editor.blank_string != null);
    try std.testing.expectEqual(@as(usize, types.max_str_len), editor.blank_string.?.len());
    try std.testing.expect(editor.code_list != null);
    try std.testing.expect(editor.code_list.?.f_link == editor.code_list);
    try std.testing.expect(editor.code_list.?.b_link == editor.code_list);
    try std.testing.expectEqual(@as(isize, 1), editor.initial_scr_height);
    try std.testing.expectEqual(@as(isize, 132), editor.initial_scr_width);
    try std.testing.expectEqual(@as(isize, 0), editor.initial_scr_offset);
    try std.testing.expectEqual(@as(isize, 1), editor.initial_margin_left);
    try std.testing.expectEqual(@as(isize, 132), editor.initial_margin_right);
    try std.testing.expectEqual(@as(isize, 0), editor.initial_margin_top);
    try std.testing.expectEqual(@as(isize, 0), editor.initial_margin_bottom);
    try std.testing.expectEqual(@as(isize, 500_000), editor.file_data.space);
    try std.testing.expectEqual(@as(isize, 8), editor.file_data.tab_width);
    try std.testing.expect(editor.file_data.old_cmds);
    try std.testing.expect(!editor.file_data.highlighting);
    try std.testing.expect(!editor.file_data.entab);
    try std.testing.expect(!editor.file_data.purge);
    try std.testing.expectEqual(@as(isize, 1), editor.file_data.versions);
    try std.testing.expectEqualStrings("Command:", editor.dflt_prompts[@intFromEnum(types.PromptType.cmd_prompt)]);
}

test "editor init recreates prefix and lookup table defaults" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();

    try std.testing.expect(editor.prefixes.isSet(@intFromEnum(types.Commands.cmd_prefix_a)));
    try std.testing.expect(editor.prefixes.isSet(@intFromEnum(types.Commands.cmd_prefix_tilde)));
    try std.testing.expectEqual(types.Commands.cmd_advance, editor.lookup['A'].command);
    try std.testing.expectEqual(types.Commands.cmd_command, editor.lookup['\\'].command);
    try std.testing.expectEqual(@as(usize, 35), editor.lookup_exp_ptr[@intFromEnum(types.Commands.cmd_prefix_s)]);
    try std.testing.expectEqual(types.EqualAction.eq_nil, editor.cmd_attrib[@intFromEnum(types.Commands.cmd_replace)].eq_action);
    try std.testing.expectEqual(@as(isize, 2), editor.cmd_attrib[@intFromEnum(types.Commands.cmd_replace)].tp_count);
}

test "editor can switch to new command lookup tables" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();

    editor.loadCommandTable(false);
    try std.testing.expectEqual(types.Commands.cmd_prefix_a, editor.lookup['A'].command);
    try std.testing.expectEqual(types.Commands.cmd_prefix_t, editor.lookup['T'].command);
    try std.testing.expectEqual(types.Commands.cmd_jump, editor.lookup_exp[1].command);
    try std.testing.expectEqual(@as(usize, 80), editor.lookup_exp_ptr[@intFromEnum(types.Commands.cmd_prefix_t)]);
}
