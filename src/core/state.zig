const builtin = @import("builtin");
const std = @import("std");
const command_tables = @import("command_tables.zig");
const defaults = @import("defaults.zig");
const str_object = @import("str_object.zig");
const types = @import("types.zig");

pub const Editor = struct {
    base_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    ProgramDirectory: []const u8 = "",
    TtControlC: bool = false,
    TtWinChanged: bool = false,
    NrKeyNames: isize = 0,
    KeyNameList: std.ArrayListUnmanaged(types.KeyNameRecord) = .{},
    KeyIntroducers: std.StaticBitSet(types.LookupCount) = std.StaticBitSet(types.LookupCount).initEmpty(),
    LudwigAborted: bool = false,
    ExitAbort: bool = false,
    VduFreeFlag: bool = false,
    Hangup: bool = false,
    QuitRequested: bool = false,
    BatchOutputEnabled: bool = !builtin.is_test,
    EditMode: types.ModeType = .ModeInsert,
    PreviousMode: types.ModeType = .ModeInsert,
    Files: [types.MaxFiles + 1]?*types.FileObject = [_]?*types.FileObject{null} ** (types.MaxFiles + 1),
    FilesFrames: [types.MaxFiles + 1]?*types.FrameObject = [_]?*types.FrameObject{null} ** (types.MaxFiles + 1),
    FgiFile: isize = 0,
    FgoFile: isize = 0,
    FirstSpan: ?*types.SpanObject = null,
    LudwigMode: types.LudwigModeType = .LudwigBatch,
    CommandIntroducer: isize = '\\',
    PromptRegion: [types.MaxTpCount + 1]types.PromptRegionAttrib = [_]types.PromptRegionAttrib{.{}} ** (types.MaxTpCount + 1),
    Screen: types.ScreenState = .{},
    CompilerCode: [types.MaxCode + 1]types.CodeObject = [_]types.CodeObject{.{}} ** (types.MaxCode + 1),
    CodeList: ?*types.CodeHeader = null,
    CodeTop: isize = 0,
    Prefixes: std.StaticBitSet(types.CommandCount) = std.StaticBitSet(types.CommandCount).initEmpty(),
    Lookup: [types.LookupCount]types.CommandObject = [_]types.CommandObject{.{}} ** types.LookupCount,
    LookupExp: [types.LookupExpCount]types.LookupExpType = [_]types.LookupExpType{.{}} ** types.LookupExpCount,
    LookupExpPtr: [types.CommandCount]usize = [_]usize{0} ** types.CommandCount,
    CmdAttrib: [types.CommandCount]types.CmdAttribRec = [_]types.CmdAttribRec{.{}} ** types.CommandCount,
    DfltPrompts: [defaults.PromptCount][]const u8 = [_][]const u8{""} ** defaults.PromptCount,
    ExecLevel: isize = 0,
    InitialMarks: types.MarkArray = [_]?*types.MarkObject{null} ** (types.MaxMarkNumber + 1),
    InitialScrHeight: isize = 0,
    InitialScrWidth: isize = 0,
    InitialScrOffset: isize = 0,
    InitialMarginLeft: isize = 0,
    InitialMarginRight: isize = 0,
    InitialMarginTop: isize = 0,
    InitialMarginBottom: isize = 0,
    InitialTabStops: types.TabArray = [_]bool{false} ** (types.MaxStrLenP + 1),
    InitialOptions: types.FrameOptions = .{},
    BlankString: ?*str_object.StrObject = null,
    InitialVerify: types.VerifyArray = [_]bool{false} ** (types.MaxVerify + 1),
    DefaultTabStops: types.TabArray = [_]bool{false} ** (types.MaxStrLenP + 1),
    FileData: types.FileDataType = .{},
    TerminalInfo: types.TerminalInfoType = .{},
    ImmediateInput: ?[]const u8 = null,
    ImmediateInputIndex: usize = 0,

    pub fn allocator(self: *Editor) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn init(base_allocator: std.mem.Allocator) !Editor {
        var editor = Editor{
            .base_allocator = base_allocator,
            .arena = std.heap.ArenaAllocator.init(base_allocator),
        };
        defaults.setRegularTabStops(&editor, 8);
        try defaults.setupInitialValues(&editor);
        try editor.initializeCompilerHeader();
        command_tables.initializeCommandAttributes(&editor);
        command_tables.loadCommandTable(&editor, editor.FileData.OldCmds);
        return editor;
    }

    pub fn deinit(self: *Editor) void {
        self.arena.deinit();
    }

    pub fn loadCommandTable(self: *Editor, old_version: bool) void {
        self.FileData.OldCmds = old_version;
        command_tables.loadCommandTable(self, old_version);
    }

    pub fn setImmediateInput(self: *Editor, source: []const u8) !void {
        self.ImmediateInput = try self.allocator().dupe(u8, source);
        self.ImmediateInputIndex = 0;
    }

    pub fn clearImmediateInput(self: *Editor) void {
        self.ImmediateInput = null;
        self.ImmediateInputIndex = 0;
    }

    fn initializeCompilerHeader(self: *Editor) !void {
        self.CodeTop = 0;
        const code_list = try self.allocator().create(types.CodeHeader);
        code_list.* = .{
            .Ref = 1,
            .Code = 1,
            .Len = 0,
        };
        code_list.FLink = code_list;
        code_list.BLink = code_list;
        self.CodeList = code_list;
    }
};

test "editor init ports value.go defaults and compiler state" {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    try std.testing.expectEqual(types.ModeType.ModeInsert, editor.EditMode);
    try std.testing.expectEqual(types.ModeType.ModeInsert, editor.PreviousMode);
    try std.testing.expectEqual(types.LudwigModeType.LudwigBatch, editor.LudwigMode);
    try std.testing.expectEqual(@as(isize, '\\'), editor.CommandIntroducer);
    try std.testing.expectEqual(types.MaxInt, editor.Screen.MsgRow);
    try std.testing.expect(editor.Screen.StdinReaderInitialized);
    try std.testing.expect(!editor.QuitRequested);
    try std.testing.expect(editor.BlankString != null);
    try std.testing.expectEqual(@as(usize, types.MaxStrLen), editor.BlankString.?.len());
    try std.testing.expect(editor.CodeList != null);
    try std.testing.expect(editor.CodeList.?.FLink == editor.CodeList);
    try std.testing.expect(editor.CodeList.?.BLink == editor.CodeList);
    try std.testing.expectEqual(@as(isize, 1), editor.InitialScrHeight);
    try std.testing.expectEqual(@as(isize, 132), editor.InitialScrWidth);
    try std.testing.expectEqual(@as(isize, 0), editor.InitialScrOffset);
    try std.testing.expectEqual(@as(isize, 1), editor.InitialMarginLeft);
    try std.testing.expectEqual(@as(isize, 132), editor.InitialMarginRight);
    try std.testing.expectEqual(@as(isize, 0), editor.InitialMarginTop);
    try std.testing.expectEqual(@as(isize, 0), editor.InitialMarginBottom);
    try std.testing.expectEqual(@as(isize, 500_000), editor.FileData.Space);
    try std.testing.expectEqual(@as(isize, 8), editor.FileData.TabWidth);
    try std.testing.expect(editor.FileData.OldCmds);
    try std.testing.expect(!editor.FileData.Highlighting);
    try std.testing.expect(!editor.FileData.Entab);
    try std.testing.expect(!editor.FileData.Purge);
    try std.testing.expectEqual(@as(isize, 1), editor.FileData.Versions);
    try std.testing.expectEqualStrings("Command:", editor.DfltPrompts[@intFromEnum(types.PromptType.CmdPrompt)]);
}

test "editor init recreates prefix and lookup table defaults" {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    try std.testing.expect(editor.Prefixes.isSet(@intFromEnum(types.Commands.CmdPrefixA)));
    try std.testing.expect(editor.Prefixes.isSet(@intFromEnum(types.Commands.CmdPrefixTilde)));
    try std.testing.expectEqual(types.Commands.CmdAdvance, editor.Lookup['A'].Command);
    try std.testing.expectEqual(types.Commands.CmdCommand, editor.Lookup['\\'].Command);
    try std.testing.expectEqual(@as(usize, 35), editor.LookupExpPtr[@intFromEnum(types.Commands.CmdPrefixS)]);
    try std.testing.expectEqual(types.EqualAction.EqNil, editor.CmdAttrib[@intFromEnum(types.Commands.CmdReplace)].EqAction);
    try std.testing.expectEqual(@as(isize, 2), editor.CmdAttrib[@intFromEnum(types.Commands.CmdReplace)].TpCount);
}

test "editor can switch to new command lookup tables" {
    var editor = try Editor.init(std.testing.allocator);
    defer editor.deinit();

    editor.loadCommandTable(false);
    try std.testing.expectEqual(types.Commands.CmdPrefixA, editor.Lookup['A'].Command);
    try std.testing.expectEqual(types.Commands.CmdPrefixT, editor.Lookup['T'].Command);
    try std.testing.expectEqual(types.Commands.CmdJump, editor.LookupExp[1].Command);
    try std.testing.expectEqual(@as(usize, 80), editor.LookupExpPtr[@intFromEnum(types.Commands.CmdPrefixT)]);
}
