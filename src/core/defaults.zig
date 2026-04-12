const builtin = @import("builtin");
const std = @import("std");
const types = @import("types.zig");
const str_object = @import("str_object.zig");

pub const prompt_count = @as(usize, @intFromEnum(types.PromptType.PatternSetPrompt)) + 1;

pub fn setRegularTabStops(editor: anytype, width: isize) void {
    const clamped_width = @max(@as(isize, 2), @min(@as(isize, 8), width));
    for (&editor.DefaultTabStops, 0..) |*slot, index| {
        slot.* = @mod(@as(isize, @intCast(index)), clamped_width) == 1;
    }
    editor.InitialTabStops = editor.DefaultTabStops;
}

pub fn setupInitialValues(editor: anytype) !void {
    editor.LudwigAborted = false;
    editor.ExitAbort = false;
    editor.Hangup = false;
    editor.QuitRequested = false;
    editor.BatchOutputEnabled = !builtin.is_test;
    editor.EditMode = .ModeInsert;
    editor.PreviousMode = .ModeInsert;

    editor.FgiFile = 0;
    editor.FgoFile = 0;
    editor.FirstSpan = null;
    editor.LudwigMode = .LudwigBatch;
    editor.CommandIntroducer = '\\';
    editor.Screen = .{
        .StdinReaderInitialized = true,
    };
    editor.Screen.MsgRow = types.MaxInt;
    editor.VduFreeFlag = false;
    editor.ExecLevel = 0;

    editor.InitialMarks = [_]?*types.MarkObject{null} ** (types.MaxMarkNumber + 1);
    editor.InitialScrHeight = 1;
    editor.InitialScrWidth = 132;
    editor.InitialScrOffset = 0;
    editor.InitialMarginLeft = 1;
    editor.InitialMarginRight = 132;
    editor.InitialMarginTop = 0;
    editor.InitialMarginBottom = 0;
    editor.InitialOptions = .{};

    editor.Prefixes = std.StaticBitSet(types.CommandCount).initEmpty();
    var cmd = @as(usize, @intFromEnum(types.Commands.CmdPrefixAst));
    while (cmd <= @as(usize, @intFromEnum(types.Commands.CmdPrefixTilde))) : (cmd += 1) {
        editor.Prefixes.set(cmd);
    }

    editor.DfltPrompts[@intFromEnum(types.PromptType.NoPrompt)] = "        ";
    editor.DfltPrompts[@intFromEnum(types.PromptType.CharPrompt)] = "Charset:";
    editor.DfltPrompts[@intFromEnum(types.PromptType.GetPrompt)] = "Get    :";
    editor.DfltPrompts[@intFromEnum(types.PromptType.EqualPrompt)] = "Equal  :";
    editor.DfltPrompts[@intFromEnum(types.PromptType.KeyPrompt)] = "Key    :";
    editor.DfltPrompts[@intFromEnum(types.PromptType.CmdPrompt)] = "Command:";
    editor.DfltPrompts[@intFromEnum(types.PromptType.SpanPrompt)] = "Span   :";
    editor.DfltPrompts[@intFromEnum(types.PromptType.TextPrompt)] = "Text   :";
    editor.DfltPrompts[@intFromEnum(types.PromptType.FramePrompt)] = "Frame  :";
    editor.DfltPrompts[@intFromEnum(types.PromptType.FilePrompt)] = "File   :";
    editor.DfltPrompts[@intFromEnum(types.PromptType.ColumnPrompt)] = "Column :";
    editor.DfltPrompts[@intFromEnum(types.PromptType.MarkPrompt)] = "Mark   :";
    editor.DfltPrompts[@intFromEnum(types.PromptType.ParamPrompt)] = "Param  :";
    editor.DfltPrompts[@intFromEnum(types.PromptType.TopicPrompt)] = "Topic  :";
    editor.DfltPrompts[@intFromEnum(types.PromptType.ReplacePrompt)] = "Replace:";
    editor.DfltPrompts[@intFromEnum(types.PromptType.ByPrompt)] = "By     :";
    editor.DfltPrompts[@intFromEnum(types.PromptType.VerifyPrompt)] = "Verify ?";
    editor.DfltPrompts[@intFromEnum(types.PromptType.PatternPrompt)] = "Pattern:";
    editor.DfltPrompts[@intFromEnum(types.PromptType.PatternSetPrompt)] = "Pat Set:";

    editor.FileData = .{
        .OldCmds = true,
        .Highlighting = false,
        .Entab = false,
        .Space = 500_000,
        .Initial = "",
        .Purge = false,
        .Versions = 1,
        .TabWidth = 8,
    };

    editor.BlankString = try str_object.newBlankStrObject(editor.allocator(), types.MaxStrLen);
}
