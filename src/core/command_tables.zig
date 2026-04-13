const state = @import("state.zig");
const types = @import("types.zig");

fn cmdIndex(cmd: types.Commands) usize {
    return @intFromEnum(cmd);
}

fn initCmd(
    attrib: *types.CmdAttribRec,
    lps: []const types.LeadParam,
    eqa: types.EqualAction,
    tpc: isize,
    pnm1: types.PromptType,
    tr1: bool,
    mla1: bool,
    pnm2: types.PromptType,
    tr2: bool,
    mla2: bool,
) void {
    attrib.lp_allowed = 0;
    for (lps) |lp| {
        attrib.lp_allowed |= (@as(u32, 1) << @intCast(@intFromEnum(lp)));
    }
    attrib.eq_action = eqa;
    attrib.tp_count = tpc;

    if (tpc >= 1) {
        attrib.tpar_info[1].prompt_name = pnm1;
        attrib.tpar_info[1].trim_reply = tr1;
        attrib.tpar_info[1].ml_allowed = mla1;
    }
    if (tpc >= 2) {
        attrib.tpar_info[2].prompt_name = pnm2;
        attrib.tpar_info[2].trim_reply = tr2;
        attrib.tpar_info[2].ml_allowed = mla2;
    }
}

const all_lead_params = [_]types.LeadParam{
    .lead_param_none,
    .lead_param_plus,
    .lead_param_minus,
    .lead_param_p_int,
    .lead_param_n_int,
    .lead_param_p_indef,
    .lead_param_n_indef,
    .lead_param_marker,
};

pub fn initializeCommandAttributes(editor: *state.Editor) void {
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_noop)], all_lead_params[0..], .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_up)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_down)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_right)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_left)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_home)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_return)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_tab)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_backtab)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_rubout)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_jump)], all_lead_params[0..], .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_advance)], all_lead_params[0..], .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_position_column)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_position_line)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_op_sys_command)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 1, .cmd_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_window_forward)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_window_backward)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_window_right)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_window_left)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_window_scroll)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_n_int, .lead_param_p_indef, .lead_param_n_indef }, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_window_top)], &[_]types.LeadParam{.lead_param_none}, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_window_end)], &[_]types.LeadParam{.lead_param_none}, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_window_new)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_window_middle)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_window_set_height)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_window_update)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_get)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_n_int }, .eq_nil, 1, .get_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_next)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_n_int }, .eq_nil, 1, .char_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_bridge)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus }, .eq_nil, 1, .char_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_replace)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_n_int, .lead_param_p_indef, .lead_param_n_indef }, .eq_nil, 2, .replace_prompt, false, false, .by_prompt, false, true);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_equal_string)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_indef, .lead_param_n_indef }, .eq_nil, 1, .equal_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_equal_column)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_indef, .lead_param_n_indef }, .eq_nil, 1, .column_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_equal_mark)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_indef, .lead_param_n_indef }, .eq_nil, 1, .mark_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_equal_eol)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_indef, .lead_param_n_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_equal_eop)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_equal_eof)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_overtype_mode)], &[_]types.LeadParam{.lead_param_none}, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_insert_mode)], &[_]types.LeadParam{.lead_param_none}, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_overtype_text)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_old, 1, .text_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_insert_text)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_old, 1, .text_prompt, false, true, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_type_text)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_old, 1, .text_prompt, false, true, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_insert_line)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_n_int }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_insert_char)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_n_int }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_insert_invisible)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_delete_line)], all_lead_params[0..], .eq_del, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_delete_char)], all_lead_params[0..], .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_swap_line)], all_lead_params[0..], .eq_del, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_split_line)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_ditto_up)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_n_int, .lead_param_p_indef, .lead_param_n_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_ditto_down)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_n_int, .lead_param_p_indef, .lead_param_n_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_case_up)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_n_int, .lead_param_p_indef, .lead_param_n_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_case_low)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_n_int, .lead_param_p_indef, .lead_param_n_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_case_edit)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_n_int, .lead_param_p_indef, .lead_param_n_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_set_margin_left)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_set_margin_right)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_line_fill)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_line_justify)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_line_squash)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_line_centre)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_line_left)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_line_right)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_word_advance)], all_lead_params[0..], .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_word_delete)], all_lead_params[0..], .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_advance_paragraph)], all_lead_params[0..], .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_delete_paragraph)], all_lead_params[0..], .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_span_define)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_marker }, .eq_nil, 1, .span_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_span_transfer)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 1, .span_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_span_copy)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_nil, 1, .span_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_span_compile)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 1, .span_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_span_jump)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus }, .eq_nil, 1, .span_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_span_index)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_span_assign)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_n_int, .lead_param_p_indef }, .eq_nil, 2, .span_prompt, true, false, .text_prompt, false, true);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_block_define)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_marker }, .eq_nil, 1, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_block_transfer)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 1, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_block_copy)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_nil, 1, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_frame_kill)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 1, .frame_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_frame_edit)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 1, .frame_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_frame_return)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_span_execute)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 1, .span_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_span_execute_no_recompile)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 1, .span_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_frame_parameters)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 1, .param_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_input)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus }, .eq_nil, 1, .file_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_output)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus }, .eq_nil, 1, .file_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_edit)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus }, .eq_nil, 1, .file_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_read)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_write)], all_lead_params[0..], .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_close)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_rewind)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_kill)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_execute)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 1, .file_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_save)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_table)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_global_input)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus }, .eq_nil, 1, .file_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_global_output)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus }, .eq_nil, 1, .file_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_global_rewind)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_file_global_kill)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_usercommand_introducer)], &[_]types.LeadParam{.lead_param_none}, .eq_old, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_user_key)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 2, .key_prompt, true, false, .cmd_prompt, false, true);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_user_parent)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_user_subprocess)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_help)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 1, .topic_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_verify)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 1, .verify_prompt, true, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_command)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_mark)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_minus, .lead_param_p_int, .lead_param_n_int }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_page)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_quit)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_dump)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_validate)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_execute_string)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 1, .cmd_prompt, false, true, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_do_last_command)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_extended)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_exit_abort)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_exit_fail)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_exit_success)], &[_]types.LeadParam{ .lead_param_none, .lead_param_plus, .lead_param_p_int, .lead_param_p_indef }, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_pattern_dummy_pattern)], &[_]types.LeadParam{}, .eq_nil, 1, .pattern_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_pattern_dummy_text)], &[_]types.LeadParam{}, .eq_nil, 1, .text_prompt, false, false, .no_prompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.cmd_resize_window)], &[_]types.LeadParam{.lead_param_none}, .eq_nil, 0, .no_prompt, false, false, .no_prompt, false, false);
}

fn addLookupExp(editor: *state.Editor, index: usize, ch: u8, cmd: types.Commands) void {
    editor.lookup_exp[index].extn = ch;
    editor.lookup_exp[index].command = cmd;
}

pub fn loadCommandTable(editor: *state.Editor, old_version: bool) void {
    editor.lookup = [_]types.CommandObject{.{}} ** types.lookup_count;
    editor.lookup_exp = [_]types.LookupExpType{.{}} ** types.lookup_exp_count;
    editor.lookup_exp_ptr = [_]usize{0} ** types.command_count;

    editor.lookup[2].command = .cmd_window_backward;
    editor.lookup[4].command = .cmd_delete_char;
    editor.lookup[5].command = .cmd_window_end;
    editor.lookup[6].command = .cmd_window_forward;
    editor.lookup[7].command = .cmd_do_last_command;
    editor.lookup[9].command = .cmd_tab;
    editor.lookup[10].command = .cmd_down;
    editor.lookup[11].command = .cmd_delete_line;
    editor.lookup[12].command = .cmd_insert_line;
    editor.lookup[13].command = .cmd_return;
    editor.lookup[14].command = .cmd_window_new;
    editor.lookup[16].command = .cmd_usercommand_introducer;
    editor.lookup[18].command = .cmd_right;
    editor.lookup[20].command = .cmd_window_top;
    editor.lookup[21].command = .cmd_up;
    editor.lookup[23].command = .cmd_word_advance;
    editor.lookup[26].command = .cmd_user_parent;
    editor.lookup[30].command = .cmd_insert_char;
    editor.lookup['"'].command = .cmd_ditto_up;
    editor.lookup['\''].command = .cmd_ditto_down;
    editor.lookup['B'].command = .cmd_prefix_b;
    editor.lookup['E'].command = .cmd_prefix_e;
    editor.lookup['F'].command = .cmd_prefix_f;
    editor.lookup['G'].command = .cmd_get;
    editor.lookup['H'].command = .cmd_help;
    editor.lookup['M'].command = .cmd_mark;
    editor.lookup['Q'].command = .cmd_quit;
    editor.lookup['R'].command = .cmd_replace;
    editor.lookup['S'].command = .cmd_prefix_s;
    editor.lookup['U'].command = .cmd_prefix_u;
    editor.lookup['V'].command = .cmd_verify;
    editor.lookup['W'].command = .cmd_prefix_w;
    editor.lookup['X'].command = .cmd_prefix_x;
    editor.lookup['\\'].command = .cmd_command;
    editor.lookup['{'].command = .cmd_set_margin_left;
    editor.lookup['}'].command = .cmd_set_margin_right;
    editor.lookup['~'].command = .cmd_prefix_tilde;
    editor.lookup[127].command = .cmd_rubout;

    if (old_version) {
        editor.lookup[8].command = .cmd_rubout;
        editor.lookup['*'].command = .cmd_prefix_ast;
        editor.lookup['?'].command = .cmd_insert_invisible;
        editor.lookup['A'].command = .cmd_advance;
        editor.lookup['C'].command = .cmd_insert_char;
        editor.lookup['D'].command = .cmd_delete_char;
        editor.lookup['I'].command = .cmd_insert_text;
        editor.lookup['J'].command = .cmd_jump;
        editor.lookup['K'].command = .cmd_delete_line;
        editor.lookup['L'].command = .cmd_insert_line;
        editor.lookup['N'].command = .cmd_next;
        editor.lookup['O'].command = .cmd_overtype_text;
        editor.lookup['Y'].command = .cmd_prefix_y;
        editor.lookup['Z'].command = .cmd_prefix_z;
        editor.lookup['^'].command = .cmd_execute_string;

        addLookupExp(editor, 1, 'U', .cmd_case_up);
        addLookupExp(editor, 2, 'L', .cmd_case_low);
        addLookupExp(editor, 3, 'E', .cmd_case_edit);
        addLookupExp(editor, 4, 'R', .cmd_bridge);
        addLookupExp(editor, 5, 'X', .cmd_span_execute);
        addLookupExp(editor, 6, 'D', .cmd_frame_edit);
        addLookupExp(editor, 7, 'R', .cmd_frame_return);
        addLookupExp(editor, 8, 'N', .cmd_span_execute_no_recompile);
        addLookupExp(editor, 9, 'Q', .cmd_prefix_eq);
        addLookupExp(editor, 10, 'O', .cmd_prefix_eo);
        addLookupExp(editor, 11, 'K', .cmd_frame_kill);
        addLookupExp(editor, 12, 'P', .cmd_frame_parameters);
        addLookupExp(editor, 13, 'L', .cmd_equal_eol);
        addLookupExp(editor, 14, 'F', .cmd_equal_eof);
        addLookupExp(editor, 15, 'P', .cmd_equal_eop);
        addLookupExp(editor, 16, 'S', .cmd_equal_string);
        addLookupExp(editor, 17, 'C', .cmd_equal_column);
        addLookupExp(editor, 18, 'M', .cmd_equal_mark);
        addLookupExp(editor, 19, 'S', .cmd_file_save);
        addLookupExp(editor, 20, 'B', .cmd_file_rewind);
        addLookupExp(editor, 21, 'I', .cmd_file_input);
        addLookupExp(editor, 22, 'E', .cmd_file_edit);
        addLookupExp(editor, 23, 'O', .cmd_file_output);
        addLookupExp(editor, 24, 'G', .cmd_prefix_fg);
        addLookupExp(editor, 25, 'K', .cmd_file_kill);
        addLookupExp(editor, 26, 'X', .cmd_file_execute);
        addLookupExp(editor, 27, 'T', .cmd_file_table);
        addLookupExp(editor, 28, 'P', .cmd_page);
        addLookupExp(editor, 29, 'I', .cmd_file_global_input);
        addLookupExp(editor, 30, 'O', .cmd_file_global_output);
        addLookupExp(editor, 31, 'B', .cmd_file_global_rewind);
        addLookupExp(editor, 32, 'K', .cmd_file_global_kill);
        addLookupExp(editor, 33, 'R', .cmd_file_read);
        addLookupExp(editor, 34, 'W', .cmd_file_write);
        addLookupExp(editor, 35, 'A', .cmd_span_assign);
        addLookupExp(editor, 36, 'C', .cmd_span_copy);
        addLookupExp(editor, 37, 'D', .cmd_span_define);
        addLookupExp(editor, 38, 'T', .cmd_span_transfer);
        addLookupExp(editor, 39, 'W', .cmd_swap_line);
        addLookupExp(editor, 40, 'L', .cmd_split_line);
        addLookupExp(editor, 41, 'J', .cmd_span_jump);
        addLookupExp(editor, 42, 'I', .cmd_span_index);
        addLookupExp(editor, 43, 'R', .cmd_span_compile);
        addLookupExp(editor, 44, 'C', .cmd_usercommand_introducer);
        addLookupExp(editor, 45, 'K', .cmd_user_key);
        addLookupExp(editor, 46, 'P', .cmd_user_parent);
        addLookupExp(editor, 47, 'S', .cmd_user_subprocess);
        addLookupExp(editor, 48, 'F', .cmd_window_forward);
        addLookupExp(editor, 49, 'B', .cmd_window_backward);
        addLookupExp(editor, 50, 'M', .cmd_window_middle);
        addLookupExp(editor, 51, 'T', .cmd_window_top);
        addLookupExp(editor, 52, 'E', .cmd_window_end);
        addLookupExp(editor, 53, 'N', .cmd_window_new);
        addLookupExp(editor, 54, 'R', .cmd_window_right);
        addLookupExp(editor, 55, 'L', .cmd_window_left);
        addLookupExp(editor, 56, 'H', .cmd_window_set_height);
        addLookupExp(editor, 57, 'S', .cmd_window_scroll);
        addLookupExp(editor, 58, 'U', .cmd_window_update);
        addLookupExp(editor, 59, 'S', .cmd_exit_success);
        addLookupExp(editor, 60, 'F', .cmd_exit_fail);
        addLookupExp(editor, 61, 'A', .cmd_exit_abort);
        addLookupExp(editor, 62, 'F', .cmd_line_fill);
        addLookupExp(editor, 63, 'J', .cmd_line_justify);
        addLookupExp(editor, 64, 'S', .cmd_line_squash);
        addLookupExp(editor, 65, 'C', .cmd_line_centre);
        addLookupExp(editor, 66, 'L', .cmd_line_left);
        addLookupExp(editor, 67, 'R', .cmd_line_right);
        addLookupExp(editor, 68, 'A', .cmd_word_advance);
        addLookupExp(editor, 69, 'D', .cmd_word_delete);
        addLookupExp(editor, 70, 'U', .cmd_up);
        addLookupExp(editor, 71, 'D', .cmd_down);
        addLookupExp(editor, 72, 'R', .cmd_right);
        addLookupExp(editor, 73, 'L', .cmd_left);
        addLookupExp(editor, 74, 'H', .cmd_home);
        addLookupExp(editor, 75, 'C', .cmd_return);
        addLookupExp(editor, 76, 'T', .cmd_tab);
        addLookupExp(editor, 77, 'B', .cmd_backtab);
        addLookupExp(editor, 78, 'Z', .cmd_rubout);
        addLookupExp(editor, 79, 'V', .cmd_validate);
        addLookupExp(editor, 80, 'D', .cmd_dump);
        addLookupExp(editor, 81, '?', .cmd_no_such);

        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_ast)] = 1;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_a)] = 4;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_b)] = 4;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_c)] = 5;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_d)] = 5;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_e)] = 5;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_eo)] = 13;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_eq)] = 16;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_f)] = 19;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_fg)] = 29;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_i)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_k)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_l)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_o)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_p)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_s)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_t)] = 44;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_tc)] = 44;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_tf)] = 44;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_u)] = 44;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_w)] = 48;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_x)] = 59;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_y)] = 62;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_z)] = 70;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_tilde)] = 79;
        editor.lookup_exp_ptr[cmdIndex(.cmd_no_such)] = 81;
    } else {
        editor.lookup[8].command = .cmd_left;
        editor.lookup['A'].command = .cmd_prefix_a;
        editor.lookup['C'].command = .cmd_prefix_c;
        editor.lookup['D'].command = .cmd_prefix_d;
        editor.lookup['K'].command = .cmd_prefix_k;
        editor.lookup['L'].command = .cmd_prefix_l;
        editor.lookup['O'].command = .cmd_prefix_o;
        editor.lookup['P'].command = .cmd_prefix_p;
        editor.lookup['T'].command = .cmd_prefix_t;

        addLookupExp(editor, 1, 'C', .cmd_jump);
        addLookupExp(editor, 2, 'L', .cmd_advance);
        addLookupExp(editor, 3, 'O', .cmd_bridge);
        addLookupExp(editor, 4, 'P', .cmd_advance_paragraph);
        addLookupExp(editor, 5, 'S', .cmd_noop);
        addLookupExp(editor, 6, 'T', .cmd_next);
        addLookupExp(editor, 7, 'W', .cmd_word_advance);
        addLookupExp(editor, 8, 'B', .cmd_noop);
        addLookupExp(editor, 9, 'C', .cmd_noop);
        addLookupExp(editor, 10, 'D', .cmd_noop);
        addLookupExp(editor, 11, 'I', .cmd_noop);
        addLookupExp(editor, 12, 'K', .cmd_noop);
        addLookupExp(editor, 13, 'M', .cmd_noop);
        addLookupExp(editor, 14, 'O', .cmd_noop);
        addLookupExp(editor, 15, 'C', .cmd_insert_char);
        addLookupExp(editor, 16, 'L', .cmd_insert_line);
        addLookupExp(editor, 17, 'C', .cmd_delete_char);
        addLookupExp(editor, 18, 'L', .cmd_delete_line);
        addLookupExp(editor, 19, 'P', .cmd_delete_paragraph);
        addLookupExp(editor, 20, 'S', .cmd_noop);
        addLookupExp(editor, 21, 'W', .cmd_word_delete);
        addLookupExp(editor, 22, 'D', .cmd_frame_edit);
        addLookupExp(editor, 23, 'K', .cmd_frame_kill);
        addLookupExp(editor, 24, 'O', .cmd_prefix_eo);
        addLookupExp(editor, 25, 'P', .cmd_frame_parameters);
        addLookupExp(editor, 26, 'Q', .cmd_prefix_eq);
        addLookupExp(editor, 27, 'R', .cmd_frame_return);
        addLookupExp(editor, 28, 'L', .cmd_equal_eol);
        addLookupExp(editor, 29, 'F', .cmd_equal_eof);
        addLookupExp(editor, 30, 'P', .cmd_equal_eop);
        addLookupExp(editor, 31, 'C', .cmd_equal_column);
        addLookupExp(editor, 32, 'L', .cmd_noop);
        addLookupExp(editor, 33, 'M', .cmd_equal_mark);
        addLookupExp(editor, 34, 'S', .cmd_equal_string);
        addLookupExp(editor, 35, 'S', .cmd_file_save);
        addLookupExp(editor, 36, 'B', .cmd_file_rewind);
        addLookupExp(editor, 37, 'E', .cmd_file_edit);
        addLookupExp(editor, 38, 'G', .cmd_prefix_fg);
        addLookupExp(editor, 39, 'I', .cmd_file_input);
        addLookupExp(editor, 40, 'K', .cmd_file_kill);
        addLookupExp(editor, 41, 'O', .cmd_file_output);
        addLookupExp(editor, 42, 'P', .cmd_page);
        addLookupExp(editor, 43, 'S', .cmd_noop);
        addLookupExp(editor, 44, 'T', .cmd_file_table);
        addLookupExp(editor, 45, 'X', .cmd_file_execute);
        addLookupExp(editor, 46, 'B', .cmd_file_global_rewind);
        addLookupExp(editor, 47, 'I', .cmd_file_global_input);
        addLookupExp(editor, 48, 'K', .cmd_file_global_kill);
        addLookupExp(editor, 49, 'O', .cmd_file_global_output);
        addLookupExp(editor, 50, 'R', .cmd_file_read);
        addLookupExp(editor, 51, 'W', .cmd_file_write);
        addLookupExp(editor, 52, 'B', .cmd_backtab);
        addLookupExp(editor, 53, 'C', .cmd_return);
        addLookupExp(editor, 54, 'D', .cmd_down);
        addLookupExp(editor, 55, 'H', .cmd_home);
        addLookupExp(editor, 56, 'I', .cmd_insert_mode);
        addLookupExp(editor, 57, 'L', .cmd_left);
        addLookupExp(editor, 58, 'M', .cmd_user_key);
        addLookupExp(editor, 59, 'O', .cmd_overtype_mode);
        addLookupExp(editor, 60, 'R', .cmd_right);
        addLookupExp(editor, 61, 'T', .cmd_tab);
        addLookupExp(editor, 62, 'U', .cmd_up);
        addLookupExp(editor, 63, 'X', .cmd_rubout);
        addLookupExp(editor, 64, 'R', .cmd_noop);
        addLookupExp(editor, 65, 'S', .cmd_noop);
        addLookupExp(editor, 66, 'P', .cmd_user_parent);
        addLookupExp(editor, 67, 'S', .cmd_user_subprocess);
        addLookupExp(editor, 68, 'X', .cmd_op_sys_command);
        addLookupExp(editor, 69, 'C', .cmd_position_column);
        addLookupExp(editor, 70, 'L', .cmd_position_line);
        addLookupExp(editor, 71, 'A', .cmd_span_assign);
        addLookupExp(editor, 72, 'C', .cmd_span_copy);
        addLookupExp(editor, 73, 'D', .cmd_span_define);
        addLookupExp(editor, 74, 'E', .cmd_span_execute_no_recompile);
        addLookupExp(editor, 75, 'J', .cmd_span_jump);
        addLookupExp(editor, 76, 'M', .cmd_span_transfer);
        addLookupExp(editor, 77, 'R', .cmd_span_compile);
        addLookupExp(editor, 78, 'T', .cmd_span_index);
        addLookupExp(editor, 79, 'X', .cmd_span_execute);
        addLookupExp(editor, 80, 'B', .cmd_split_line);
        addLookupExp(editor, 81, 'C', .cmd_prefix_tc);
        addLookupExp(editor, 82, 'F', .cmd_prefix_tf);
        addLookupExp(editor, 83, 'I', .cmd_insert_text);
        addLookupExp(editor, 84, 'N', .cmd_insert_invisible);
        addLookupExp(editor, 85, 'O', .cmd_overtype_text);
        addLookupExp(editor, 86, 'R', .cmd_noop);
        addLookupExp(editor, 87, 'S', .cmd_swap_line);
        addLookupExp(editor, 88, 'X', .cmd_execute_string);
        addLookupExp(editor, 89, 'E', .cmd_case_edit);
        addLookupExp(editor, 90, 'L', .cmd_case_low);
        addLookupExp(editor, 91, 'U', .cmd_case_up);
        addLookupExp(editor, 92, 'C', .cmd_line_centre);
        addLookupExp(editor, 93, 'F', .cmd_line_fill);
        addLookupExp(editor, 94, 'J', .cmd_line_justify);
        addLookupExp(editor, 95, 'L', .cmd_line_left);
        addLookupExp(editor, 96, 'R', .cmd_line_right);
        addLookupExp(editor, 97, 'S', .cmd_line_squash);
        addLookupExp(editor, 98, 'C', .cmd_usercommand_introducer);
        addLookupExp(editor, 99, 'B', .cmd_window_backward);
        addLookupExp(editor, 100, 'C', .cmd_window_middle);
        addLookupExp(editor, 101, 'E', .cmd_window_end);
        addLookupExp(editor, 102, 'F', .cmd_window_forward);
        addLookupExp(editor, 103, 'H', .cmd_window_set_height);
        addLookupExp(editor, 104, 'L', .cmd_window_left);
        addLookupExp(editor, 105, 'M', .cmd_window_scroll);
        addLookupExp(editor, 106, 'N', .cmd_window_new);
        addLookupExp(editor, 107, 'O', .cmd_noop);
        addLookupExp(editor, 108, 'R', .cmd_window_right);
        addLookupExp(editor, 109, 'S', .cmd_noop);
        addLookupExp(editor, 110, 'T', .cmd_window_top);
        addLookupExp(editor, 111, 'U', .cmd_window_update);
        addLookupExp(editor, 112, 'A', .cmd_exit_abort);
        addLookupExp(editor, 113, 'F', .cmd_exit_fail);
        addLookupExp(editor, 114, 'S', .cmd_exit_success);
        addLookupExp(editor, 115, 'D', .cmd_dump);
        addLookupExp(editor, 116, 'V', .cmd_validate);
        addLookupExp(editor, 117, '?', .cmd_no_such);

        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_ast)] = 1;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_a)] = 1;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_b)] = 8;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_c)] = 15;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_d)] = 17;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_e)] = 22;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_eo)] = 28;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_eq)] = 31;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_f)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_fg)] = 46;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_i)] = 52;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_k)] = 52;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_l)] = 64;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_o)] = 66;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_p)] = 69;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_s)] = 71;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_t)] = 80;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_tc)] = 89;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_tf)] = 92;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_u)] = 98;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_w)] = 99;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_x)] = 112;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_y)] = 115;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_z)] = 115;
        editor.lookup_exp_ptr[cmdIndex(.cmd_prefix_tilde)] = 115;
        editor.lookup_exp_ptr[cmdIndex(.cmd_no_such)] = 117;
    }
}
