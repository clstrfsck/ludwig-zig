const builtin = @import("builtin");
const std = @import("std");
const state = @import("state.zig");
const types = @import("types.zig");
const str_object = @import("str_object.zig");

pub const prompt_count = @as(usize, @intFromEnum(types.PromptType.PatternSetPrompt)) + 1;

pub fn setRegularTabStops(editor: *state.Editor, width: isize) void {
    const clamped_width = @max(@as(isize, 2), @min(@as(isize, 8), width));
    for (&editor.default_tab_stops, 0..) |*slot, index| {
        slot.* = @mod(@as(isize, @intCast(index)), clamped_width) == 1;
    }
    editor.initial_tab_stops = editor.default_tab_stops;
}

pub fn setupInitialValues(editor: *state.Editor) !void {
    editor.ludwig_aborted = false;
    editor.exit_abort = false;
    editor.hangup = false;
    editor.quit_requested = false;
    editor.batch_output_enabled = !builtin.is_test;
    editor.edit_mode = .mode_insert;
    editor.previous_mode = .mode_insert;

    editor.fgi_file = 0;
    editor.fgo_file = 0;
    editor.first_span = null;
    editor.ludwig_mode = .ludwig_batch;
    editor.command_introducer = '\\';
    editor.screen = .{
        .stdin_reader_initialized = true,
    };
    editor.screen.msg_row = types.max_int;
    editor.vdu_free_flag = false;
    editor.exec_level = 0;

    editor.initial_marks = [_]?*types.MarkObject{null} ** (types.max_mark_number + 1);
    editor.initial_scr_height = 1;
    editor.initial_scr_width = 132;
    editor.initial_scr_offset = 0;
    editor.initial_margin_left = 1;
    editor.initial_margin_right = 132;
    editor.initial_margin_top = 0;
    editor.initial_margin_bottom = 0;
    editor.initial_options = .{};

    editor.prefixes = std.StaticBitSet(types.command_count).initEmpty();
    var cmd = @as(usize, @intFromEnum(types.Commands.CmdPrefixAst));
    while (cmd <= @as(usize, @intFromEnum(types.Commands.CmdPrefixTilde))) : (cmd += 1) {
        editor.prefixes.set(cmd);
    }

    editor.dflt_prompts[@intFromEnum(types.PromptType.NoPrompt)] = "        ";
    editor.dflt_prompts[@intFromEnum(types.PromptType.CharPrompt)] = "Charset:";
    editor.dflt_prompts[@intFromEnum(types.PromptType.GetPrompt)] = "Get    :";
    editor.dflt_prompts[@intFromEnum(types.PromptType.EqualPrompt)] = "Equal  :";
    editor.dflt_prompts[@intFromEnum(types.PromptType.KeyPrompt)] = "Key    :";
    editor.dflt_prompts[@intFromEnum(types.PromptType.CmdPrompt)] = "Command:";
    editor.dflt_prompts[@intFromEnum(types.PromptType.SpanPrompt)] = "Span   :";
    editor.dflt_prompts[@intFromEnum(types.PromptType.TextPrompt)] = "Text   :";
    editor.dflt_prompts[@intFromEnum(types.PromptType.FramePrompt)] = "Frame  :";
    editor.dflt_prompts[@intFromEnum(types.PromptType.FilePrompt)] = "File   :";
    editor.dflt_prompts[@intFromEnum(types.PromptType.ColumnPrompt)] = "Column :";
    editor.dflt_prompts[@intFromEnum(types.PromptType.MarkPrompt)] = "Mark   :";
    editor.dflt_prompts[@intFromEnum(types.PromptType.ParamPrompt)] = "Param  :";
    editor.dflt_prompts[@intFromEnum(types.PromptType.TopicPrompt)] = "Topic  :";
    editor.dflt_prompts[@intFromEnum(types.PromptType.ReplacePrompt)] = "Replace:";
    editor.dflt_prompts[@intFromEnum(types.PromptType.ByPrompt)] = "By     :";
    editor.dflt_prompts[@intFromEnum(types.PromptType.VerifyPrompt)] = "Verify ?";
    editor.dflt_prompts[@intFromEnum(types.PromptType.PatternPrompt)] = "Pattern:";
    editor.dflt_prompts[@intFromEnum(types.PromptType.PatternSetPrompt)] = "Pat Set:";

    editor.file_data = .{
        .old_cmds = true,
        .highlighting = false,
        .entab = false,
        .space = 500_000,
        .initial = "",
        .purge = false,
        .versions = 1,
        .tab_width = 8,
    };

    editor.blank_string = try str_object.newBlankStrObject(editor.allocator(), types.max_str_len);
}
