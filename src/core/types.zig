const std = @import("std");
const StrObject = @import("str_object.zig").StrObject;

pub const LudwigVersion = "X5.0-006";

pub const MaxInt = std.math.maxInt(isize);
pub const OrdMaxChar = 255;
pub const MaxFiles = 100;
pub const MaxGroupLines = 64;
pub const MaxGroupLineOffset = MaxGroupLines - 1;
pub const MaxLines = MaxInt;
pub const MaxMarkNumber = 10;
pub const MinUserMarkNumber = 1;
pub const MaxUserMarkNumber = 9;
pub const MarkEquals = 0;
pub const MarkModified = 10;
pub const MaxSpace = 1_000_000;
pub const MaxRecSize = 512;
pub const MaxStrLen = 400;
pub const MaxStrLenP = MaxStrLen + 1;
pub const MaxScrRows = 100;
pub const MaxScrCols = 255;
pub const MaxCode = 4000;
pub const MaxVerify = 256;
pub const MaxTparRecursion = 100;
pub const MaxTpCount = 2;
pub const MaxExecRecursion = 100;
pub const MaxWordSets = 2;
pub const MaxWordSetsM1 = MaxWordSets - 1;
pub const TpdLit: u8 = '\'';
pub const TpdSmart: u8 = '`';
pub const TpdExact: u8 = '"';
pub const TpdSpan: u8 = '$';
pub const TpdPrompt: u8 = '&';
pub const TpdEnvironment: u8 = '?';
pub const ExpandLim = 130;
pub const NameLen = 31;
pub const FileNameLen = 1024;
pub const KeyLen = 4;
pub const MaxSpecialKeys = 1000;
pub const MaxNrKeyNames = 1000;
pub const MaxParseTable = 300;
pub const MaxNFAStateRange = 200;
pub const MaxDFAStateRange = 255;
pub const MaxSetRange = OrdMaxChar;
pub const PatternNull = 0;
pub const PatternNFAStart = 1;
pub const PatternDFAKill = 0;
pub const PatternDFAFail = 0;
pub const PatternDFAStart = 2;
pub const PatternMaxDepth = 20;
pub const PatternKStar: u8 = '*';
pub const PatternComma: u8 = ',';
pub const PatternRParen: u8 = ')';
pub const PatternLParen: u8 = '(';
pub const PatternDefineSetU: u8 = 'D';
pub const PatternDefineSetL: u8 = 'd';
pub const PatternMark: u8 = '@';
pub const PatternEquals: u8 = '=';
pub const PatternModified: u8 = '%';
pub const PatternPlus: u8 = '+';
pub const PatternNegate: u8 = '-';
pub const PatternBar: u8 = '|';
pub const PatternLRangeDelim: u8 = '[';
pub const PatternRRangeDelim: u8 = ']';
pub const PatternSpace: u8 = ' ';
pub const PatternBegLine = 0;
pub const PatternEndLine = 1;
pub const PatternLeftMargin = 3;
pub const PatternRightMargin = 4;
pub const PatternDotColumn = 5;
pub const PatternMarksStart = 19;
pub const PatternMarksModified = 29;
pub const PatternMarksEquals = 19;
pub const PatternAlphaStart = 32;
pub const BlankFrameName = "";
pub const DefaultFrameName = "LUDWIG";

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
    CmdUserCommandIntroducer,
    CmdUserKey,
    CmdUserParent,
    CmdUserSubprocess,
    CmdUserUndo,
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
    CmdExitAbort,
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
    Str: ?*StrObject = null,
    Nxt: ?*TParObject = null,
    Con: ?*TParObject = null,
};

pub const CodeHeader = struct {
    FLink: ?*CodeHeader = null,
    BLink: ?*CodeHeader = null,
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
    FirstLine: ?*LineHdrObject = null,
    LastLine: ?*LineHdrObject = null,
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

pub const MarkArray = [MaxMarkNumber + 1]?*MarkObject;
pub const TabArray = [MaxStrLenP + 1]bool;
pub const VerifyArray = [MaxVerify + 1]bool;

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
pub const HighlightMatchEntries = std.ArrayListUnmanaged(HighlightMatchEntry);

pub const AcceptSet = struct {
    bits: [MaxSetRange + 1]bool = [_]bool{false} ** (MaxSetRange + 1),

    pub fn Bit(self: *const AcceptSet, index: usize) u1 {
        return if (index <= MaxSetRange and self.bits[index]) 1 else 0;
    }

    pub fn Set(self: *AcceptSet, other: *const AcceptSet) void {
        self.bits = other.bits;
    }

    pub fn Clear(self: *AcceptSet) void {
        self.bits = [_]bool{false} ** (MaxSetRange + 1);
    }

    pub fn setBit(self: *AcceptSet, index: usize) void {
        if (index <= MaxSetRange) {
            self.bits[index] = true;
        }
    }

    pub fn isEmpty(self: *const AcceptSet) bool {
        for (self.bits) |bit| {
            if (bit) return false;
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
    GeneratorSet: [MaxNFAStateRange + 1]bool = [_]bool{false} ** (MaxNFAStateRange + 1),
    EquivList: ?*StateEltObject = null,
    EquivSet: [MaxNFAStateRange + 1]bool = [_]bool{false} ** (MaxNFAStateRange + 1),
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
    DFATable: [MaxDFAStateRange + 1]DFAStateType = [_]DFAStateType{.{}} ** (MaxDFAStateRange + 1),
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

pub const NFATableType = [MaxNFAStateRange + 1]NFATransitionType;

pub const FrameObject = struct {
    FirstGroup: ?*GroupObject = null,
    LastGroup: ?*GroupObject = null,
    Dot: ?*MarkObject = null,
    Marks: MarkArray = [_]?*MarkObject{null} ** (MaxMarkNumber + 1),
    ScrHeight: isize = 0,
    ScrWidth: isize = 0,
    ScrOffset: isize = 0,
    ScrDotLine: isize = 0,
    Span: ?*SpanObject = null,
    ReturnFrame: ?*FrameObject = null,
    InputCount: isize = 0,
    SpaceLimit: isize = 0,
    SpaceLeft: isize = 0,
    TextModified: bool = false,
    MarginLeft: isize = 0,
    MarginRight: isize = 0,
    MarginTop: isize = 0,
    MarginBottom: isize = 0,
    TabStops: TabArray = [_]bool{false} ** (MaxStrLenP + 1),
    Options: FrameOptions = .{},
    InputFile: isize = 0,
    OutputFile: isize = 0,
    GetTpar: TParObject = .{},
    GetPatternPtr: ?*DFATableObject = null,
    EqsTpar: TParObject = .{},
    EqsPatternPtr: ?*DFATableObject = null,
    Rep1Tpar: TParObject = .{},
    RepPatternPtr: ?*DFATableObject = null,
    Rep2Tpar: TParObject = .{},
    VerifyTpar: TParObject = .{},
    Highlighter: ?*PlaceholderHighlighter = null,
    DirtyLine: isize = 0,
};

pub const GroupObject = struct {
    FLink: ?*GroupObject = null,
    BLink: ?*GroupObject = null,
    Frame: *FrameObject,
    FirstLine: ?*LineHdrObject = null,
    LastLine: ?*LineHdrObject = null,
    FirstLineNr: isize = 0,
    NrLines: isize = 0,
};

pub const LineHdrObject = struct {
    FLink: ?*LineHdrObject = null,
    BLink: ?*LineHdrObject = null,
    Group: ?*GroupObject = null,
    OffsetNr: isize = 0,
    Marks: std.ArrayListUnmanaged(*MarkObject) = .{},
    Str: ?*StrObject = null,
    Used: isize = 0,
    ScrRowNr: isize = 0,
    HlState: HighlightState = null,
    HlMatch: HighlightMatchEntries = .{},

    pub fn Len(self: *const LineHdrObject) isize {
        if (self.Str) |str| {
            return @intCast(str.len());
        }
        return 0;
    }
};

pub const SpanObject = struct {
    FLink: ?*SpanObject = null,
    BLink: ?*SpanObject = null,
    Frame: ?*FrameObject = null,
    MarkOne: ?*MarkObject = null,
    MarkTwo: ?*MarkObject = null,
    Name: []const u8 = "",
    Code: ?*CodeHeader = null,
};

pub const PromptRegionAttrib = struct {
    LineNr: isize = 0,
    Redraw: ?*LineHdrObject = null,
};

pub const CodeObject = struct {
    Rep: LeadParam = .LeadParamNone,
    Cnt: isize = 0,
    Op: Commands = .CmdNoop,
    Tpar: ?*TParObject = null,
    Code: ?*CodeHeader = null,
    Lbl: isize = 0,
};

pub const CommandObject = struct {
    Command: Commands = .CmdNoop,
    Code: ?*CodeHeader = null,
    Tpar: ?*TParObject = null,
};

pub const TerminalInfoType = struct {
    Name: []const u8 = "",
    Width: isize = 0,
    Height: isize = 0,
};

pub const KeyNameRecord = struct {
    KeyName: []const u8 = "",
    KeyCode: isize = 0,
};

pub const TParAttribute = struct {
    PromptName: PromptType = .NoPrompt,
    TrimReply: bool = false,
    MlAllowed: bool = false,
};

pub const CmdAttribRec = struct {
    LpAllowed: u32 = 0,
    EqAction: EqualAction = .EqNil,
    TpCount: isize = 0,
    TparInfo: [MaxTpCount + 1]TParAttribute = [_]TParAttribute{.{}} ** (MaxTpCount + 1),
};

pub const HelpRecord = struct {
    Key: []const u8 = "",
    Txt: []const u8 = "",
};

pub const FileDataType = struct {
    OldCmds: bool = true,
    Highlighting: bool = false,
    Entab: bool = false,
    Space: isize = 0,
    Initial: []const u8 = "",
    Purge: bool = false,
    Versions: isize = 0,
    TabWidth: isize = 8,
};

pub const ScreenState = struct {
    Frame: ?*FrameObject = null,
    TopLine: ?*LineHdrObject = null,
    BotLine: ?*LineHdrObject = null,
    MsgRow: isize = 0,
    NeedsFix: bool = false,
    StdinReaderInitialized: bool = false,
};

pub const CommandCount = @as(usize, @intFromEnum(Commands.CmdNoSuch)) + 1;
pub const LookupCount = OrdMaxChar + MaxSpecialKeys + 1;
pub const LookupExpCount = ExpandLim + 1;

pub const TerminalKeyCodes = struct {
    const base: isize = LookupCount - 15;

    pub const UpArrow: isize = base;
    pub const DownArrow: isize = base + 1;
    pub const LeftArrow: isize = base + 2;
    pub const RightArrow: isize = base + 3;
    pub const Home: isize = base + 4;
    pub const BackTab: isize = base + 5;
    pub const InsertChar: isize = base + 6;
    pub const DeleteChar: isize = base + 7;
    pub const PageUp: isize = base + 8;
    pub const PageDown: isize = base + 9;
    pub const WindowResize: isize = base + 10;
    pub const InsertLine: isize = base + 11;
    pub const DeleteLine: isize = base + 12;
    pub const Find: isize = base + 13;
    pub const Help: isize = base + 14;
};
