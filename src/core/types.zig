const std = @import("std");
const StrObject = @import("str_object.zig").StrObject;

pub const ludwig_reader = "X5.0-006";

pub const max_int = std.math.maxInt(isize);
pub const ord_max_char = 255;
pub const max_files = 100;
pub const max_group_lines = 64;
pub const max_group_line_offset = max_group_lines - 1;
pub const max_lines = max_int;
pub const max_mark_number = 10;
pub const min_user_mark_number = 1;
pub const max_user_mark_number = 9;
pub const mark_equals = 0;
pub const mark_modified = 10;
pub const max_space = 1_000_000;
pub const max_rec_size = 512;
pub const max_str_len = 400;
pub const max_str_len_p1 = max_str_len + 1;
pub const max_scr_rows = 100;
pub const max_scr_cols = 255;
pub const max_code = 4000;
pub const max_verify = 256;
pub const max_tpar_recursion = 100;
pub const max_tp_count = 2;
pub const max_exec_recursion = 100;
pub const max_word_sets = 2;
pub const max_word_sets_m1 = max_word_sets - 1;
pub const tpd_lit: u8 = '\'';
pub const tpd_smart: u8 = '`';
pub const tpd_exact: u8 = '"';
pub const tpd_span: u8 = '$';
pub const tpd_prompt: u8 = '&';
pub const tpd_environment: u8 = '?';
pub const expand_lim = 130;
pub const name_len = 31;
pub const file_name_len = 1024;
pub const key_len = 4;
pub const max_special_keys = 1000;
pub const max_num_key_names = 1000;
pub const max_parse_table = 300;
pub const max_nfa_state_range = 200;
pub const max_dfa_state_range = 255;
pub const max_set_range = ord_max_char;
pub const pattern_null = 0;
pub const pattern_nfa_start = 1;
pub const pattern_dfa_kill = 0;
pub const pattern_dfa_fail = 0;
pub const pattern_dfa_start = 2;
pub const pattern_max_depth = 20;
pub const pattern_k_star: u8 = '*';
pub const pattern_comma: u8 = ',';
pub const pattern_r_paren: u8 = ')';
pub const pattern_l_paren: u8 = '(';
pub const pattern_define_set_u: u8 = 'D';
pub const pattern_define_set_l: u8 = 'd';
pub const pattern_mark: u8 = '@';
pub const pattern_equals: u8 = '=';
pub const pattern_modified: u8 = '%';
pub const pattern_plus: u8 = '+';
pub const pattern_negate: u8 = '-';
pub const pattern_bar: u8 = '|';
pub const pattern_l_range_delim: u8 = '[';
pub const pattern_r_range_delim: u8 = ']';
pub const pattern_space: u8 = ' ';
pub const pattern_beg_line = 0;
pub const pattern_end_line = 1;
pub const pattern_left_margin = 3;
pub const pattern_right_margin = 4;
pub const pattern_dot_column = 5;
pub const pattern_marks_start = 19;
pub const pattern_marks_modified = 29;
pub const pattern_marks_equals = 19;
pub const pattern_alpha_start = 32;
pub const blank_frame_name = "";
pub const default_frame_name = "LUDWIG";

pub const VerifyResponse = enum(u16) {
    verify_yes,
    verify_no,
    verify_always,
    verify_quit,
};

pub const ParseType = enum(u16) {
    parse_command,
    parse_input,
    parse_output,
    parse_edit,
    parse_stdin,
    parse_execute,
};

pub const FrameOptions = packed struct {
    auto_indent: bool = false,
    auto_wrap: bool = false,
    new_line: bool = false,
    special_frame: bool = false,
};

pub const Commands = enum(u16) {
    cmd_noop,
    cmd_up,
    cmd_down,
    cmd_left,
    cmd_right,
    cmd_home,
    cmd_return,
    cmd_tab,
    cmd_backtab,
    cmd_rubout,
    cmd_jump,
    cmd_advance,
    cmd_position_column,
    cmd_position_line,
    cmd_op_sys_command,
    cmd_window_forward,
    cmd_window_backward,
    cmd_window_left,
    cmd_window_right,
    cmd_window_scroll,
    cmd_window_top,
    cmd_window_end,
    cmd_window_new,
    cmd_window_middle,
    cmd_window_set_height,
    cmd_window_update,
    cmd_get,
    cmd_next,
    cmd_bridge,
    cmd_replace,
    cmd_equal_string,
    cmd_equal_column,
    cmd_equal_mark,
    cmd_equal_eol,
    cmd_equal_eop,
    cmd_equal_eof,
    cmd_overtype_mode,
    cmd_insert_mode,
    cmd_overtype_text,
    cmd_insert_text,
    cmd_type_text,
    cmd_insert_line,
    cmd_insert_char,
    cmd_insert_invisible,
    cmd_delete_line,
    cmd_delete_char,
    cmd_swap_line,
    cmd_split_line,
    cmd_ditto_up,
    cmd_ditto_down,
    cmd_case_up,
    cmd_case_low,
    cmd_case_edit,
    cmd_set_margin_left,
    cmd_set_margin_right,
    cmd_line_fill,
    cmd_line_justify,
    cmd_line_squash,
    cmd_line_centre,
    cmd_line_left,
    cmd_line_right,
    cmd_word_advance,
    cmd_word_delete,
    cmd_advance_paragraph,
    cmd_delete_paragraph,
    cmd_span_define,
    cmd_span_transfer,
    cmd_span_copy,
    cmd_span_compile,
    cmd_span_jump,
    cmd_span_index,
    cmd_span_assign,
    cmd_block_define,
    cmd_block_transfer,
    cmd_block_copy,
    cmd_frame_kill,
    cmd_frame_edit,
    cmd_frame_return,
    cmd_span_execute,
    cmd_span_execute_no_recompile,
    cmd_frame_parameters,
    cmd_file_input,
    cmd_file_output,
    cmd_file_edit,
    cmd_file_read,
    cmd_file_write,
    cmd_file_close,
    cmd_file_rewind,
    cmd_file_kill,
    cmd_file_execute,
    cmd_file_save,
    cmd_file_table,
    cmd_file_global_input,
    cmd_file_global_output,
    cmd_file_global_rewind,
    cmd_file_global_kill,
    cmd_usercommand_introducer,
    cmd_user_key,
    cmd_user_parent,
    cmd_user_subprocess,
    cmd_user_learn,
    cmd_user_recall,
    cmd_resize_window,
    cmd_help,
    cmd_verify,
    cmd_command,
    cmd_mark,
    cmd_page,
    cmd_quit,
    cmd_dump,
    cmd_validate,
    cmd_execute_string,
    cmd_do_last_command,
    cmd_extended,
    cmd_exit_abort,
    cmd_exit_fail,
    cmd_exit_success,
    cmd_pattern_dummy_pattern,
    cmd_pattern_dummy_text,
    cmd_pc_jump,
    cmd_exit_to,
    cmd_fail_to,
    cmd_iterate,
    cmd_prefix_ast,
    cmd_prefix_a,
    cmd_prefix_b,
    cmd_prefix_c,
    cmd_prefix_d,
    cmd_prefix_e,
    cmd_prefix_eo,
    cmd_prefix_eq,
    cmd_prefix_f,
    cmd_prefix_fg,
    cmd_prefix_i,
    cmd_prefix_k,
    cmd_prefix_l,
    cmd_prefix_o,
    cmd_prefix_p,
    cmd_prefix_s,
    cmd_prefix_t,
    cmd_prefix_tc,
    cmd_prefix_tf,
    cmd_prefix_u,
    cmd_prefix_w,
    cmd_prefix_x,
    cmd_prefix_y,
    cmd_prefix_z,
    cmd_prefix_tilde,
    cmd_no_such,
};

pub const LeadParam = enum(u16) {
    lead_param_none,
    lead_param_plus,
    lead_param_minus,
    lead_param_p_int,
    lead_param_n_int,
    lead_param_p_indef,
    lead_param_n_indef,
    lead_param_marker,
};

pub const EqualAction = enum(u16) {
    eq_nil,
    eq_del,
    eq_old,
};

pub const PromptType = enum(u16) {
    no_prompt,
    char_prompt,
    get_prompt,
    equal_prompt,
    key_prompt,
    cmd_prompt,
    span_prompt,
    text_prompt,
    frame_prompt,
    file_prompt,
    column_prompt,
    mark_prompt,
    param_prompt,
    topic_prompt,
    replace_prompt,
    by_prompt,
    verify_prompt,
    pattern_prompt,
    pattern_set_prompt,
};

pub const ParameterType = enum(u16) {
    pattern_fail,
    pattern_range,
    null_param,
};

pub const ModeType = enum(u16) {
    mode_overtype,
    mode_insert,
    mode_command,
};

pub const LudwigModeType = enum(u16) {
    ludwig_batch,
    ludwig_hardcopy,
    ludwig_screen,
};

pub const LookupExpType = struct {
    extn: u8 = 0,
    command: Commands = .cmd_noop,
};

pub const TParObject = struct {
    len: isize = 0,
    dlm: u8 = 0,
    str: ?*StrObject = null,
    nxt: ?*TParObject = null,
    con: ?*TParObject = null,
};

pub const CodeHeader = struct {
    f_link: ?*CodeHeader = null,
    b_link: ?*CodeHeader = null,
    ref: isize = 0,
    code: isize = 0,
    len: isize = 0,
};

pub const MarkObject = struct {
    line: *LineHdrObject,
    col: isize,
};

pub const FileObject = struct {
    valid: bool = false,
    first_line: ?*LineHdrObject = null,
    last_line: ?*LineHdrObject = null,
    line_count: isize = 0,
    rewind_first_line: ?*LineHdrObject = null,
    rewind_last_line: ?*LineHdrObject = null,
    rewind_line_count: isize = 0,
    output_flag: bool = false,
    eof: bool = false,
    filename: []const u8 = "",
    l_counter: isize = 0,
    memory: []const u8 = "",
    tnm: []const u8 = "",
    entab: bool = false,
    create: bool = false,
    os_file: ?std.Io.File = null,
    reader: ?*anyopaque = null,
    mode: isize = 0,
    previous_file_id: i64 = 0,
    purge: bool = false,
    versions: isize = 0,
};

pub const MarkArray = [max_mark_number + 1]?*MarkObject;
pub const TabArray = [max_str_len_p1 + 1]bool;
pub const VerifyArray = [max_verify + 1]bool;

pub const SpecialFrames = struct {
    cmd: ?*FrameObject = null,
    heap: ?*FrameObject = null,
    oops: ?*FrameObject = null,
};

pub const PlaceholderHighlighter = opaque {};
pub const HighlightState = ?*const anyopaque;
pub const HighlightMatchEntry = struct {
    position: usize = 0,
    pair: u16 = 0,
};
pub const HighlightMatchEntries = std.ArrayList(HighlightMatchEntry);

pub const AcceptSet = struct {
    bits: [max_set_range + 1]bool = [_]bool{false} ** (max_set_range + 1),

    pub fn bit(self: *const AcceptSet, index: usize) u1 {
        return if (index <= max_set_range and self.bits[index]) 1 else 0;
    }

    pub fn set(self: *AcceptSet, other: *const AcceptSet) void {
        self.bits = other.bits;
    }

    pub fn clear(self: *AcceptSet) void {
        self.bits = [_]bool{false} ** (max_set_range + 1);
    }

    pub fn setBit(self: *AcceptSet, index: usize) void {
        if (index <= max_set_range) {
            self.bits[index] = true;
        }
    }

    pub fn isEmpty(self: *const AcceptSet) bool {
        for (self.bits) |b| {
            if (b) return false;
        }
        return true;
    }
};

pub const TransitionObject = struct {
    transition_accept_set: AcceptSet = .{},
    sccept_next_state: isize = 0,
    next_transition: ?*TransitionObject = null,
    start_flag: bool = false,
};

pub const StateEltObject = struct {
    state_elt: isize = 0,
    next_elt: ?*StateEltObject = null,
};

pub const NFAAttributeType = struct {
    generator_set: [max_nfa_state_range + 1]bool = [_]bool{false} ** (max_nfa_state_range + 1),
    equiv_list: ?*StateEltObject = null,
    equiv_set: [max_nfa_state_range + 1]bool = [_]bool{false} ** (max_nfa_state_range + 1),
};

pub const DFAStateType = struct {
    transitions: ?*TransitionObject = null,
    martked: bool = false,
    nfa_attributes: NFAAttributeType = .{},
    pattern_start: bool = false,
    final_accept: bool = false,
    left_transition: bool = false,
    right_transition: bool = false,
    left_context_check: bool = false,
};

pub const PatternDefType = struct {
    strng: ?*StrObject = null,
    length: isize = 0,
};

pub const DFATableObject = struct {
    dfa_table: [max_dfa_state_range + 1]DFAStateType = [_]DFAStateType{.{}} ** (max_dfa_state_range + 1),
    dfa_states_used: isize = 0,
    definition: PatternDefType = .{},
};

pub const NFATransitionType = struct {
    indefinite: bool = false,
    fail: bool = false,
    epsilon_out: bool = false,
    first_out: isize = 0,
    second_out: isize = 0,
    next_state: isize = 0,
    accept_set: AcceptSet = .{},
};

pub const NFATableType = [max_nfa_state_range + 1]NFATransitionType;

pub const FrameObject = struct {
    first_group: ?*GroupObject = null,
    last_group: ?*GroupObject = null,
    dot: ?*MarkObject = null,
    marks: MarkArray = [_]?*MarkObject{null} ** (max_mark_number + 1),
    scr_height: isize = 0,
    scr_width: isize = 0,
    scr_offset: isize = 0,
    scr_dot_line: isize = 0,
    span: ?*SpanObject = null,
    return_frame: ?*FrameObject = null,
    input_count: isize = 0,
    space_limit: isize = 0,
    space_left: isize = 0,
    text_modified: bool = false,
    margin_left: isize = 0,
    margin_right: isize = 0,
    margin_top: isize = 0,
    margin_bottom: isize = 0,
    tab_stops: TabArray = [_]bool{false} ** (max_str_len_p1 + 1),
    options: FrameOptions = .{},
    input_file: isize = 0,
    output_file: isize = 0,
    get_tpar: TParObject = .{},
    get_pattern_ptr: ?*DFATableObject = null,
    eqs_tpar: TParObject = .{},
    eqs_pattern_ptr: ?*DFATableObject = null,
    rep_1_tpar: TParObject = .{},
    rep_pattern_ptr: ?*DFATableObject = null,
    rep_2_tpar: TParObject = .{},
    verify_tpar: TParObject = .{},
    highlighter: ?*PlaceholderHighlighter = null,
    dirty_line: isize = 0,
};

pub const GroupObject = struct {
    f_link: ?*GroupObject = null,
    b_link: ?*GroupObject = null,
    frame: *FrameObject,
    first_line: ?*LineHdrObject = null,
    last_line: ?*LineHdrObject = null,
    first_line_num: isize = 0,
    num_lines: isize = 0,
};

pub const LineHdrObject = struct {
    f_link: ?*LineHdrObject = null,
    b_link: ?*LineHdrObject = null,
    group: ?*GroupObject = null,
    offset_num: isize = 0,
    marks: std.ArrayList(*MarkObject) = .empty,
    str: ?*StrObject = null,
    used: isize = 0,
    scr_row_num: isize = 0,
    hl_state: HighlightState = null,
    hl_match: HighlightMatchEntries = .empty,

    pub fn len(self: *const LineHdrObject) isize {
        if (self.str) |str| {
            return @intCast(str.len());
        }
        return 0;
    }
};

pub const SpanObject = struct {
    f_link: ?*SpanObject = null,
    b_link: ?*SpanObject = null,
    frame: ?*FrameObject = null,
    mark_one: ?*MarkObject = null,
    mark_two: ?*MarkObject = null,
    name: []const u8 = "",
    code: ?*CodeHeader = null,
};

pub const PromptRegionAttrib = struct {
    line_num: isize = 0,
    redraw: ?*LineHdrObject = null,
};

pub const CodeObject = struct {
    rep: LeadParam = .lead_param_none,
    cnt: isize = 0,
    op: Commands = .cmd_noop,
    tpar: ?*TParObject = null,
    code: ?*CodeHeader = null,
    lbl: isize = 0,
};

pub const CommandObject = struct {
    command: Commands = .cmd_noop,
    code: ?*CodeHeader = null,
    tpar: ?*TParObject = null,
};

pub const TerminalInfoType = struct {
    name: []const u8 = "",
    width: isize = 0,
    height: isize = 0,
};

pub const KeyNameRecord = struct {
    key_name: []const u8 = "",
    key_code: isize = 0,
};

pub const TParAttribute = struct {
    prompt_name: PromptType = .no_prompt,
    trim_reply: bool = false,
    ml_allowed: bool = false,
};

pub const CmdAttribRec = struct {
    lp_allowed: u32 = 0,
    eq_action: EqualAction = .eq_nil,
    tp_count: isize = 0,
    tpar_info: [max_tp_count + 1]TParAttribute = [_]TParAttribute{.{}} ** (max_tp_count + 1),
};

pub const HelpRecord = struct {
    key: []const u8 = "",
    txt: []const u8 = "",
};

pub const FileDataType = struct {
    old_cmds: bool = true,
    highlighting: bool = false,
    entab: bool = false,
    space: isize = 0,
    initial: []const u8 = "",
    purge: bool = false,
    versions: isize = 0,
    tab_width: isize = 8,
};

pub const ScreenState = struct {
    frame: ?*FrameObject = null,
    top_line: ?*LineHdrObject = null,
    bot_line: ?*LineHdrObject = null,
    msg_row: isize = 0,
    needs_fix: bool = false,
    stdin_reader_initialized: bool = false,
};

pub const command_count = @as(usize, @intFromEnum(Commands.cmd_no_such)) + 1;
pub const lookup_count = ord_max_char + max_special_keys + 1;
pub const lookup_exp_count = expand_lim + 1;

pub const terminal_key_codes = struct {
    const base: isize = lookup_count - 15;

    pub const up_arrow: isize = base;
    pub const down_arrow: isize = base + 1;
    pub const left_arrow: isize = base + 2;
    pub const right_arrow: isize = base + 3;
    pub const home: isize = base + 4;
    pub const back_tab: isize = base + 5;
    pub const insert_char: isize = base + 6;
    pub const delete_char: isize = base + 7;
    pub const page_up: isize = base + 8;
    pub const page_down: isize = base + 9;
    pub const window_resize: isize = base + 10;
    pub const insert_line: isize = base + 11;
    pub const delete_line: isize = base + 12;
    pub const find: isize = base + 13;
    pub const help: isize = base + 14;
};
