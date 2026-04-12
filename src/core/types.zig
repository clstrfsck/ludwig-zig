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
    VerifyReplyYes,
    VerifyReplyNo,
    VerifyReplyAlways,
    VerifyReplyQuit,
};

pub const ParseType = enum(u16) {
    ParseCommand,
    ParseInput,
    ParseOutput,
    ParseEdit,
    ParseStdin,
    ParseExecute,
};

pub const FrameOptions = packed struct {
    autoIndent: bool = false,
    autoWrap: bool = false,
    newLine: bool = false,
    specialFrame: bool = false,
};

pub const Commands = enum(u16) {
    CmdNoop,
    CmdUp,
    CmdDown,
    CmdLeft,
    CmdRight,
    CmdHome,
    CmdReturn,
    CmdTab,
    CmdBacktab,
    CmdRubout,
    CmdJump,
    CmdAdvance,
    CmdPositionColumn,
    CmdPositionLine,
    CmdOpSysCommand,
    CmdWindowForward,
    CmdWindowBackward,
    CmdWindowLeft,
    CmdWindowRight,
    CmdWindowScroll,
    CmdWindowTop,
    CmdWindowEnd,
    CmdWindowNew,
    CmdWindowMiddle,
    CmdWindowSetHeight,
    CmdWindowUpdate,
    CmdGet,
    CmdNext,
    CmdBridge,
    CmdReplace,
    CmdEqualString,
    CmdEqualColumn,
    CmdEqualMark,
    CmdEqualEol,
    CmdEqualEop,
    CmdEqualEof,
    CmdOvertypeMode,
    CmdInsertMode,
    CmdOvertypeText,
    CmdInsertText,
    CmdTypeText,
    CmdInsertLine,
    CmdInsertChar,
    CmdInsertInvisible,
    CmdDeleteLine,
    CmdDeleteChar,
    CmdSwapLine,
    CmdSplitLine,
    CmdDittoUp,
    CmdDittoDown,
    CmdCaseUp,
    CmdCaseLow,
    CmdCaseEdit,
    CmdSetMarginLeft,
    CmdSetMarginRight,
    CmdLineFill,
    CmdLineJustify,
    CmdLineSquash,
    CmdLineCentre,
    CmdLineLeft,
    CmdLineRight,
    CmdWordAdvance,
    CmdWordDelete,
    CmdAdvanceParagraph,
    CmdDeleteParagraph,
    CmdSpanDefine,
    CmdSpanTransfer,
    CmdSpanCopy,
    CmdSpanCompile,
    CmdSpanJump,
    CmdSpanIndex,
    CmdSpanAssign,
    CmdBlockDefine,
    CmdBlockTransfer,
    CmdBlockCopy,
    CmdFrameKill,
    CmdFrameEdit,
    CmdFrameReturn,
    CmdSpanExecute,
    CmdSpanExecuteNoRecompile,
    CmdFrameParameters,
    CmdFileInput,
    CmdFileOutput,
    CmdFileEdit,
    CmdFileRead,
    CmdFileWrite,
    CmdFileClose,
    CmdFileRewind,
    CmdFileKill,
    CmdFileExecute,
    CmdFileSave,
    CmdFileTable,
    CmdFileGlobalInput,
    CmdFileGlobalOutput,
    CmdFileGlobalRewind,
    CmdFileGlobalKill,
    Cmdusercommand_introducer,
    CmdUserKey,
    CmdUserParent,
    CmdUserSubprocess,
    CmdUserLearn,
    CmdUserRecall,
    CmdResizeWindow,
    CmdHelp,
    CmdVerify,
    CmdCommand,
    CmdMark,
    CmdPage,
    CmdQuit,
    CmdDump,
    CmdValidate,
    CmdExecuteString,
    CmdDoLastCommand,
    CmdExtended,
    Cmdexit_abort,
    CmdExitFail,
    CmdExitSuccess,
    CmdPatternDummyPattern,
    CmdPatternDummyText,
    CmdPcJump,
    CmdExitTo,
    CmdFailTo,
    CmdIterate,
    CmdPrefixAst,
    CmdPrefixA,
    CmdPrefixB,
    CmdPrefixC,
    CmdPrefixD,
    CmdPrefixE,
    CmdPrefixEo,
    CmdPrefixEq,
    CmdPrefixF,
    CmdPrefixFg,
    CmdPrefixI,
    CmdPrefixK,
    CmdPrefixL,
    CmdPrefixO,
    CmdPrefixP,
    CmdPrefixS,
    CmdPrefixT,
    CmdPrefixTc,
    CmdPrefixTf,
    CmdPrefixU,
    CmdPrefixW,
    CmdPrefixX,
    CmdPrefixY,
    CmdPrefixZ,
    CmdPrefixTilde,
    CmdNoSuch,
};

pub const LeadParam = enum(u16) {
    LeadParamNone,
    LeadParamPlus,
    LeadParamMinus,
    LeadParamPInt,
    LeadParamNInt,
    LeadParamPIndef,
    LeadParamNIndef,
    LeadParamMarker,
};

pub const EqualAction = enum(u16) {
    EqNil,
    EqDel,
    EqOld,
};

pub const PromptType = enum(u16) {
    NoPrompt,
    CharPrompt,
    GetPrompt,
    EqualPrompt,
    KeyPrompt,
    CmdPrompt,
    SpanPrompt,
    TextPrompt,
    FramePrompt,
    FilePrompt,
    ColumnPrompt,
    MarkPrompt,
    ParamPrompt,
    TopicPrompt,
    ReplacePrompt,
    ByPrompt,
    VerifyPrompt,
    PatternPrompt,
    PatternSetPrompt,
};

pub const ParameterType = enum(u16) {
    PatternFail,
    PatternRange,
    NullParam,
};

pub const ModeType = enum(u16) {
    ModeOvertype,
    ModeInsert,
    ModeCommand,
};

pub const LudwigModeType = enum(u16) {
    LudwigBatch,
    LudwigHardcopy,
    LudwigScreen,
};

pub const LookupExpType = struct {
    Extn: u8 = 0,
    Command: Commands = .CmdNoop,
};

pub const TParObject = struct {
    Len: isize = 0,
    Dlm: u8 = 0,
    str: ?*StrObject = null,
    Nxt: ?*TParObject = null,
    Con: ?*TParObject = null,
};

pub const CodeHeader = struct {
    f_link: ?*CodeHeader = null,
    b_link: ?*CodeHeader = null,
    Ref: isize = 0,
    Code: isize = 0,
    Len: isize = 0,
};

pub const MarkObject = struct {
    Line: *LineHdrObject,
    Col: isize,
};

pub const FileObject = struct {
    Valid: bool = false,
    first_line: ?*LineHdrObject = null,
    last_line: ?*LineHdrObject = null,
    LineCount: isize = 0,
    RewindFirstLine: ?*LineHdrObject = null,
    RewindLastLine: ?*LineHdrObject = null,
    RewindLineCount: isize = 0,
    OutputFlag: bool = false,
    Eof: bool = false,
    Filename: []const u8 = "",
    LCounter: isize = 0,
    Memory: []const u8 = "",
    Tnm: []const u8 = "",
    Entab: bool = false,
    Create: bool = false,
    OsFile: ?std.fs.File = null,
    Reader: ?*anyopaque = null,
    Mode: isize = 0,
    PreviousFileId: i64 = 0,
    Purge: bool = false,
    Versions: isize = 0,
};

pub const MarkArray = [max_mark_number + 1]?*MarkObject;
pub const TabArray = [max_str_len_p1 + 1]bool;
pub const VerifyArray = [max_verify + 1]bool;

pub const SpecialFrames = struct {
    Cmd: ?*FrameObject = null,
    Heap: ?*FrameObject = null,
    Oops: ?*FrameObject = null,
};

pub const PlaceholderHighlighter = opaque {};
pub const HighlightState = ?*const anyopaque;
pub const HighlightMatchEntry = struct {
    Position: usize = 0,
    Pair: u16 = 0,
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
    TransitionAcceptSet: AcceptSet = .{},
    AcceptNextState: isize = 0,
    NextTransition: ?*TransitionObject = null,
    StartFlag: bool = false,
};

pub const StateEltObject = struct {
    StateElt: isize = 0,
    NextElt: ?*StateEltObject = null,
};

pub const NFAAttributeType = struct {
    GeneratorSet: [max_nfa_state_range + 1]bool = [_]bool{false} ** (max_nfa_state_range + 1),
    EquivList: ?*StateEltObject = null,
    EquivSet: [max_nfa_state_range + 1]bool = [_]bool{false} ** (max_nfa_state_range + 1),
};

pub const DFAStateType = struct {
    Transitions: ?*TransitionObject = null,
    Marked: bool = false,
    NFAAttributes: NFAAttributeType = .{},
    PatternStart: bool = false,
    FinalAccept: bool = false,
    LeftTransition: bool = false,
    RightTransition: bool = false,
    LeftContextCheck: bool = false,
};

pub const PatternDefType = struct {
    Strng: ?*StrObject = null,
    Length: isize = 0,
};

pub const DFATableObject = struct {
    DFATable: [max_dfa_state_range + 1]DFAStateType = [_]DFAStateType{.{}} ** (max_dfa_state_range + 1),
    DFAStatesUsed: isize = 0,
    Definition: PatternDefType = .{},
};

pub const NFATransitionType = struct {
    Indefinite: bool = false,
    Fail: bool = false,
    EpsilonOut: bool = false,
    FirstOut: isize = 0,
    SecondOut: isize = 0,
    NextState: isize = 0,
    AcceptSet: AcceptSet = .{},
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
    marks: std.ArrayList(*MarkObject) = .{},
    str: ?*StrObject = null,
    used: isize = 0,
    scr_row_num: isize = 0,
    hl_state: HighlightState = null,
    hl_match: HighlightMatchEntries = .{},

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
    rep: LeadParam = .LeadParamNone,
    cnt: isize = 0,
    op: Commands = .CmdNoop,
    tpar: ?*TParObject = null,
    code: ?*CodeHeader = null,
    lbl: isize = 0,
};

pub const CommandObject = struct {
    command: Commands = .CmdNoop,
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
    prompt_name: PromptType = .NoPrompt,
    trim_reply: bool = false,
    ml_allowed: bool = false,
};

pub const CmdAttribRec = struct {
    lp_allowed: u32 = 0,
    eq_action: EqualAction = .EqNil,
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

pub const command_count = @as(usize, @intFromEnum(Commands.CmdNoSuch)) + 1;
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
