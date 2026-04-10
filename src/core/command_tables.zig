const std = @import("std");
const types = @import("types.zig");

fn cmdIndex(cmd: types.Commands) usize {
    return @intFromEnum(cmd);
}

fn promptIndex(prompt: types.PromptType) usize {
    return @intFromEnum(prompt);
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
    attrib.LpAllowed = 0;
    for (lps) |lp| {
        attrib.LpAllowed |= (@as(u32, 1) << @intCast(@intFromEnum(lp)));
    }
    attrib.EqAction = eqa;
    attrib.TpCount = tpc;

    if (tpc >= 1) {
        attrib.TparInfo[1].PromptName = pnm1;
        attrib.TparInfo[1].TrimReply = tr1;
        attrib.TparInfo[1].MlAllowed = mla1;
    }
    if (tpc >= 2) {
        attrib.TparInfo[2].PromptName = pnm2;
        attrib.TparInfo[2].TrimReply = tr2;
        attrib.TparInfo[2].MlAllowed = mla2;
    }
}

const all_lead_params = [_]types.LeadParam{
    .LeadParamNone,
    .LeadParamPlus,
    .LeadParamMinus,
    .LeadParamPInt,
    .LeadParamNInt,
    .LeadParamPIndef,
    .LeadParamNIndef,
    .LeadParamMarker,
};

pub fn initializeCommandAttributes(editor: anytype) void {
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdNoop)], all_lead_params[0..], .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdUp)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdDown)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdRight)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdLeft)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdHome)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdReturn)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdTab)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdBacktab)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdRubout)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdJump)], all_lead_params[0..], .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdAdvance)], all_lead_params[0..], .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdPositionColumn)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdPositionLine)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdOpSysCommand)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .CmdPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdWindowForward)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdWindowBackward)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdWindowRight)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdWindowLeft)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdWindowScroll)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdWindowTop)], &[_]types.LeadParam{.LeadParamNone}, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdWindowEnd)], &[_]types.LeadParam{.LeadParamNone}, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdWindowNew)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdWindowMiddle)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdWindowSetHeight)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdWindowUpdate)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdGet)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt }, .EqNil, 1, .GetPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdNext)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt }, .EqNil, 1, .CharPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdBridge)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .CharPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdReplace)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 2, .ReplacePrompt, false, false, .ByPrompt, false, true);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdEqualString)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 1, .EqualPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdEqualColumn)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 1, .ColumnPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdEqualMark)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 1, .MarkPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdEqualEol)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdEqualEop)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdEqualEof)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdOvertypeMode)], &[_]types.LeadParam{.LeadParamNone}, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdInsertMode)], &[_]types.LeadParam{.LeadParamNone}, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdOvertypeText)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 1, .TextPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdInsertText)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 1, .TextPrompt, false, true, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdTypeText)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 1, .TextPrompt, false, true, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdInsertLine)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdInsertChar)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdInsertInvisible)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdDeleteLine)], all_lead_params[0..], .EqDel, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdDeleteChar)], all_lead_params[0..], .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdSwapLine)], all_lead_params[0..], .EqDel, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdSplitLine)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdDittoUp)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdDittoDown)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdCaseUp)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdCaseLow)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdCaseEdit)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdSetMarginLeft)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdSetMarginRight)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdLineFill)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdLineJustify)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdLineSquash)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdLineCentre)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdLineLeft)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdLineRight)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdWordAdvance)], all_lead_params[0..], .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdWordDelete)], all_lead_params[0..], .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdAdvanceParagraph)], all_lead_params[0..], .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdDeleteParagraph)], all_lead_params[0..], .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdSpanDefine)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamMarker }, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdSpanTransfer)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdSpanCopy)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdSpanCompile)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdSpanJump)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdSpanIndex)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdSpanAssign)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef }, .EqNil, 2, .SpanPrompt, true, false, .TextPrompt, false, true);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdBlockDefine)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamMarker }, .EqNil, 1, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdBlockTransfer)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdBlockCopy)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 1, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFrameKill)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .FramePrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFrameEdit)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .FramePrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFrameReturn)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdSpanExecute)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdSpanExecuteNoRecompile)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFrameParameters)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .ParamPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileInput)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .FilePrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileOutput)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .FilePrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileEdit)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .FilePrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileRead)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileWrite)], all_lead_params[0..], .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileClose)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileRewind)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileKill)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileExecute)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 1, .FilePrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileSave)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileTable)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileGlobalInput)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .FilePrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileGlobalOutput)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .FilePrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileGlobalRewind)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdFileGlobalKill)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdUserCommandIntroducer)], &[_]types.LeadParam{.LeadParamNone}, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdUserKey)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 2, .KeyPrompt, true, false, .CmdPrompt, false, true);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdUserParent)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdUserSubprocess)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdUserUndo)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdHelp)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .TopicPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdVerify)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .VerifyPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdCommand)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdMark)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdPage)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdQuit)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdDump)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdValidate)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdExecuteString)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 1, .CmdPrompt, false, true, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdDoLastCommand)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdExtended)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdExitAbort)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdExitFail)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdExitSuccess)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdPatternDummyPattern)], &[_]types.LeadParam{}, .EqNil, 1, .PatternPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdPatternDummyText)], &[_]types.LeadParam{}, .EqNil, 1, .TextPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.CmdAttrib[cmdIndex(.CmdResizeWindow)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
}

fn addLookupExp(editor: anytype, index: usize, ch: u8, cmd: types.Commands) void {
    editor.LookupExp[index].Extn = ch;
    editor.LookupExp[index].Command = cmd;
}

pub fn loadCommandTable(editor: anytype, old_version: bool) void {
    editor.Lookup = [_]types.CommandObject{.{}} ** types.LookupCount;
    editor.LookupExp = [_]types.LookupExpType{.{}} ** types.LookupExpCount;
    editor.LookupExpPtr = [_]usize{0} ** types.CommandCount;

    editor.Lookup[2].Command = .CmdWindowBackward;
    editor.Lookup[4].Command = .CmdDeleteChar;
    editor.Lookup[5].Command = .CmdWindowEnd;
    editor.Lookup[6].Command = .CmdWindowForward;
    editor.Lookup[7].Command = .CmdDoLastCommand;
    editor.Lookup[9].Command = .CmdTab;
    editor.Lookup[10].Command = .CmdDown;
    editor.Lookup[11].Command = .CmdDeleteLine;
    editor.Lookup[12].Command = .CmdInsertLine;
    editor.Lookup[13].Command = .CmdReturn;
    editor.Lookup[14].Command = .CmdWindowNew;
    editor.Lookup[16].Command = .CmdUserCommandIntroducer;
    editor.Lookup[18].Command = .CmdRight;
    editor.Lookup[20].Command = .CmdWindowTop;
    editor.Lookup[21].Command = .CmdUp;
    editor.Lookup[23].Command = .CmdWordAdvance;
    editor.Lookup[26].Command = .CmdUserParent;
    editor.Lookup[30].Command = .CmdInsertChar;
    editor.Lookup['"'].Command = .CmdDittoUp;
    editor.Lookup['\''].Command = .CmdDittoDown;
    editor.Lookup['B'].Command = .CmdPrefixB;
    editor.Lookup['E'].Command = .CmdPrefixE;
    editor.Lookup['F'].Command = .CmdPrefixF;
    editor.Lookup['G'].Command = .CmdGet;
    editor.Lookup['H'].Command = .CmdHelp;
    editor.Lookup['M'].Command = .CmdMark;
    editor.Lookup['Q'].Command = .CmdQuit;
    editor.Lookup['R'].Command = .CmdReplace;
    editor.Lookup['S'].Command = .CmdPrefixS;
    editor.Lookup['U'].Command = .CmdPrefixU;
    editor.Lookup['V'].Command = .CmdVerify;
    editor.Lookup['W'].Command = .CmdPrefixW;
    editor.Lookup['X'].Command = .CmdPrefixX;
    editor.Lookup['\\'].Command = .CmdCommand;
    editor.Lookup['{'].Command = .CmdSetMarginLeft;
    editor.Lookup['}'].Command = .CmdSetMarginRight;
    editor.Lookup['~'].Command = .CmdPrefixTilde;
    editor.Lookup[127].Command = .CmdRubout;

    if (old_version) {
        editor.Lookup[8].Command = .CmdRubout;
        editor.Lookup['*'].Command = .CmdPrefixAst;
        editor.Lookup['?'].Command = .CmdInsertInvisible;
        editor.Lookup['A'].Command = .CmdAdvance;
        editor.Lookup['C'].Command = .CmdInsertChar;
        editor.Lookup['D'].Command = .CmdDeleteChar;
        editor.Lookup['I'].Command = .CmdInsertText;
        editor.Lookup['J'].Command = .CmdJump;
        editor.Lookup['K'].Command = .CmdDeleteLine;
        editor.Lookup['L'].Command = .CmdInsertLine;
        editor.Lookup['N'].Command = .CmdNext;
        editor.Lookup['O'].Command = .CmdOvertypeText;
        editor.Lookup['Y'].Command = .CmdPrefixY;
        editor.Lookup['Z'].Command = .CmdPrefixZ;
        editor.Lookup['^'].Command = .CmdExecuteString;

        addLookupExp(editor, 1, 'U', .CmdCaseUp);
        addLookupExp(editor, 2, 'L', .CmdCaseLow);
        addLookupExp(editor, 3, 'E', .CmdCaseEdit);
        addLookupExp(editor, 4, 'R', .CmdBridge);
        addLookupExp(editor, 5, 'X', .CmdSpanExecute);
        addLookupExp(editor, 6, 'D', .CmdFrameEdit);
        addLookupExp(editor, 7, 'R', .CmdFrameReturn);
        addLookupExp(editor, 8, 'N', .CmdSpanExecuteNoRecompile);
        addLookupExp(editor, 9, 'Q', .CmdPrefixEq);
        addLookupExp(editor, 10, 'O', .CmdPrefixEo);
        addLookupExp(editor, 11, 'K', .CmdFrameKill);
        addLookupExp(editor, 12, 'P', .CmdFrameParameters);
        addLookupExp(editor, 13, 'L', .CmdEqualEol);
        addLookupExp(editor, 14, 'F', .CmdEqualEof);
        addLookupExp(editor, 15, 'P', .CmdEqualEop);
        addLookupExp(editor, 16, 'S', .CmdEqualString);
        addLookupExp(editor, 17, 'C', .CmdEqualColumn);
        addLookupExp(editor, 18, 'M', .CmdEqualMark);
        addLookupExp(editor, 19, 'S', .CmdFileSave);
        addLookupExp(editor, 20, 'B', .CmdFileRewind);
        addLookupExp(editor, 21, 'I', .CmdFileInput);
        addLookupExp(editor, 22, 'E', .CmdFileEdit);
        addLookupExp(editor, 23, 'O', .CmdFileOutput);
        addLookupExp(editor, 24, 'G', .CmdPrefixFg);
        addLookupExp(editor, 25, 'K', .CmdFileKill);
        addLookupExp(editor, 26, 'X', .CmdFileExecute);
        addLookupExp(editor, 27, 'T', .CmdFileTable);
        addLookupExp(editor, 28, 'P', .CmdPage);
        addLookupExp(editor, 29, 'I', .CmdFileGlobalInput);
        addLookupExp(editor, 30, 'O', .CmdFileGlobalOutput);
        addLookupExp(editor, 31, 'B', .CmdFileGlobalRewind);
        addLookupExp(editor, 32, 'K', .CmdFileGlobalKill);
        addLookupExp(editor, 33, 'R', .CmdFileRead);
        addLookupExp(editor, 34, 'W', .CmdFileWrite);
        addLookupExp(editor, 35, 'A', .CmdSpanAssign);
        addLookupExp(editor, 36, 'C', .CmdSpanCopy);
        addLookupExp(editor, 37, 'D', .CmdSpanDefine);
        addLookupExp(editor, 38, 'T', .CmdSpanTransfer);
        addLookupExp(editor, 39, 'W', .CmdSwapLine);
        addLookupExp(editor, 40, 'L', .CmdSplitLine);
        addLookupExp(editor, 41, 'J', .CmdSpanJump);
        addLookupExp(editor, 42, 'I', .CmdSpanIndex);
        addLookupExp(editor, 43, 'R', .CmdSpanCompile);
        addLookupExp(editor, 44, 'C', .CmdUserCommandIntroducer);
        addLookupExp(editor, 45, 'K', .CmdUserKey);
        addLookupExp(editor, 46, 'P', .CmdUserParent);
        addLookupExp(editor, 47, 'S', .CmdUserSubprocess);
        addLookupExp(editor, 48, 'F', .CmdWindowForward);
        addLookupExp(editor, 49, 'B', .CmdWindowBackward);
        addLookupExp(editor, 50, 'M', .CmdWindowMiddle);
        addLookupExp(editor, 51, 'T', .CmdWindowTop);
        addLookupExp(editor, 52, 'E', .CmdWindowEnd);
        addLookupExp(editor, 53, 'N', .CmdWindowNew);
        addLookupExp(editor, 54, 'R', .CmdWindowRight);
        addLookupExp(editor, 55, 'L', .CmdWindowLeft);
        addLookupExp(editor, 56, 'H', .CmdWindowSetHeight);
        addLookupExp(editor, 57, 'S', .CmdWindowScroll);
        addLookupExp(editor, 58, 'U', .CmdWindowUpdate);
        addLookupExp(editor, 59, 'S', .CmdExitSuccess);
        addLookupExp(editor, 60, 'F', .CmdExitFail);
        addLookupExp(editor, 61, 'A', .CmdExitAbort);
        addLookupExp(editor, 62, 'F', .CmdLineFill);
        addLookupExp(editor, 63, 'J', .CmdLineJustify);
        addLookupExp(editor, 64, 'S', .CmdLineSquash);
        addLookupExp(editor, 65, 'C', .CmdLineCentre);
        addLookupExp(editor, 66, 'L', .CmdLineLeft);
        addLookupExp(editor, 67, 'R', .CmdLineRight);
        addLookupExp(editor, 68, 'A', .CmdWordAdvance);
        addLookupExp(editor, 69, 'D', .CmdWordDelete);
        addLookupExp(editor, 70, 'U', .CmdUp);
        addLookupExp(editor, 71, 'D', .CmdDown);
        addLookupExp(editor, 72, 'R', .CmdRight);
        addLookupExp(editor, 73, 'L', .CmdLeft);
        addLookupExp(editor, 74, 'H', .CmdHome);
        addLookupExp(editor, 75, 'C', .CmdReturn);
        addLookupExp(editor, 76, 'T', .CmdTab);
        addLookupExp(editor, 77, 'B', .CmdBacktab);
        addLookupExp(editor, 78, 'Z', .CmdRubout);
        addLookupExp(editor, 79, 'V', .CmdValidate);
        addLookupExp(editor, 80, 'D', .CmdDump);
        addLookupExp(editor, 81, '?', .CmdNoSuch);

        editor.LookupExpPtr[cmdIndex(.CmdPrefixAst)] = 1;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixA)] = 4;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixB)] = 4;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixC)] = 5;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixD)] = 5;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixE)] = 5;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixEo)] = 13;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixEq)] = 16;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixF)] = 19;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixFg)] = 29;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixI)] = 35;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixK)] = 35;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixL)] = 35;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixO)] = 35;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixP)] = 35;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixS)] = 35;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixT)] = 44;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixTc)] = 44;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixTf)] = 44;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixU)] = 44;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixW)] = 48;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixX)] = 59;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixY)] = 62;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixZ)] = 70;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixTilde)] = 79;
        editor.LookupExpPtr[cmdIndex(.CmdNoSuch)] = 81;
    } else {
        editor.Lookup[8].Command = .CmdLeft;
        editor.Lookup['A'].Command = .CmdPrefixA;
        editor.Lookup['C'].Command = .CmdPrefixC;
        editor.Lookup['D'].Command = .CmdPrefixD;
        editor.Lookup['K'].Command = .CmdPrefixK;
        editor.Lookup['L'].Command = .CmdPrefixL;
        editor.Lookup['O'].Command = .CmdPrefixO;
        editor.Lookup['P'].Command = .CmdPrefixP;
        editor.Lookup['T'].Command = .CmdPrefixT;

        addLookupExp(editor, 1, 'C', .CmdJump);
        addLookupExp(editor, 2, 'L', .CmdAdvance);
        addLookupExp(editor, 3, 'O', .CmdBridge);
        addLookupExp(editor, 4, 'P', .CmdAdvanceParagraph);
        addLookupExp(editor, 5, 'S', .CmdNoop);
        addLookupExp(editor, 6, 'T', .CmdNext);
        addLookupExp(editor, 7, 'W', .CmdWordAdvance);
        addLookupExp(editor, 8, 'B', .CmdNoop);
        addLookupExp(editor, 9, 'C', .CmdNoop);
        addLookupExp(editor, 10, 'D', .CmdNoop);
        addLookupExp(editor, 11, 'I', .CmdNoop);
        addLookupExp(editor, 12, 'K', .CmdNoop);
        addLookupExp(editor, 13, 'M', .CmdNoop);
        addLookupExp(editor, 14, 'O', .CmdNoop);
        addLookupExp(editor, 15, 'C', .CmdInsertChar);
        addLookupExp(editor, 16, 'L', .CmdInsertLine);
        addLookupExp(editor, 17, 'C', .CmdDeleteChar);
        addLookupExp(editor, 18, 'L', .CmdDeleteLine);
        addLookupExp(editor, 19, 'P', .CmdDeleteParagraph);
        addLookupExp(editor, 20, 'S', .CmdNoop);
        addLookupExp(editor, 21, 'W', .CmdWordDelete);
        addLookupExp(editor, 22, 'D', .CmdFrameEdit);
        addLookupExp(editor, 23, 'K', .CmdFrameKill);
        addLookupExp(editor, 24, 'O', .CmdPrefixEo);
        addLookupExp(editor, 25, 'P', .CmdFrameParameters);
        addLookupExp(editor, 26, 'Q', .CmdPrefixEq);
        addLookupExp(editor, 27, 'R', .CmdFrameReturn);
        addLookupExp(editor, 28, 'L', .CmdEqualEol);
        addLookupExp(editor, 29, 'F', .CmdEqualEof);
        addLookupExp(editor, 30, 'P', .CmdEqualEop);
        addLookupExp(editor, 31, 'C', .CmdEqualColumn);
        addLookupExp(editor, 32, 'L', .CmdNoop);
        addLookupExp(editor, 33, 'M', .CmdEqualMark);
        addLookupExp(editor, 34, 'S', .CmdEqualString);
        addLookupExp(editor, 35, 'S', .CmdFileSave);
        addLookupExp(editor, 36, 'B', .CmdFileRewind);
        addLookupExp(editor, 37, 'E', .CmdFileEdit);
        addLookupExp(editor, 38, 'G', .CmdPrefixFg);
        addLookupExp(editor, 39, 'I', .CmdFileInput);
        addLookupExp(editor, 40, 'K', .CmdFileKill);
        addLookupExp(editor, 41, 'O', .CmdFileOutput);
        addLookupExp(editor, 42, 'P', .CmdPage);
        addLookupExp(editor, 43, 'S', .CmdNoop);
        addLookupExp(editor, 44, 'T', .CmdFileTable);
        addLookupExp(editor, 45, 'X', .CmdFileExecute);
        addLookupExp(editor, 46, 'B', .CmdFileGlobalRewind);
        addLookupExp(editor, 47, 'I', .CmdFileGlobalInput);
        addLookupExp(editor, 48, 'K', .CmdFileGlobalKill);
        addLookupExp(editor, 49, 'O', .CmdFileGlobalOutput);
        addLookupExp(editor, 50, 'R', .CmdFileRead);
        addLookupExp(editor, 51, 'W', .CmdFileWrite);
        addLookupExp(editor, 52, 'B', .CmdBacktab);
        addLookupExp(editor, 53, 'C', .CmdReturn);
        addLookupExp(editor, 54, 'D', .CmdDown);
        addLookupExp(editor, 55, 'H', .CmdHome);
        addLookupExp(editor, 56, 'I', .CmdInsertMode);
        addLookupExp(editor, 57, 'L', .CmdLeft);
        addLookupExp(editor, 58, 'M', .CmdUserKey);
        addLookupExp(editor, 59, 'O', .CmdOvertypeMode);
        addLookupExp(editor, 60, 'R', .CmdRight);
        addLookupExp(editor, 61, 'T', .CmdTab);
        addLookupExp(editor, 62, 'U', .CmdUp);
        addLookupExp(editor, 63, 'X', .CmdRubout);
        addLookupExp(editor, 64, 'R', .CmdNoop);
        addLookupExp(editor, 65, 'S', .CmdNoop);
        addLookupExp(editor, 66, 'P', .CmdUserParent);
        addLookupExp(editor, 67, 'S', .CmdUserSubprocess);
        addLookupExp(editor, 68, 'X', .CmdOpSysCommand);
        addLookupExp(editor, 69, 'C', .CmdPositionColumn);
        addLookupExp(editor, 70, 'L', .CmdPositionLine);
        addLookupExp(editor, 71, 'A', .CmdSpanAssign);
        addLookupExp(editor, 72, 'C', .CmdSpanCopy);
        addLookupExp(editor, 73, 'D', .CmdSpanDefine);
        addLookupExp(editor, 74, 'E', .CmdSpanExecuteNoRecompile);
        addLookupExp(editor, 75, 'J', .CmdSpanJump);
        addLookupExp(editor, 76, 'M', .CmdSpanTransfer);
        addLookupExp(editor, 77, 'R', .CmdSpanCompile);
        addLookupExp(editor, 78, 'T', .CmdSpanIndex);
        addLookupExp(editor, 79, 'X', .CmdSpanExecute);
        addLookupExp(editor, 80, 'B', .CmdSplitLine);
        addLookupExp(editor, 81, 'C', .CmdPrefixTc);
        addLookupExp(editor, 82, 'F', .CmdPrefixTf);
        addLookupExp(editor, 83, 'I', .CmdInsertText);
        addLookupExp(editor, 84, 'N', .CmdInsertInvisible);
        addLookupExp(editor, 85, 'O', .CmdOvertypeText);
        addLookupExp(editor, 86, 'R', .CmdNoop);
        addLookupExp(editor, 87, 'S', .CmdSwapLine);
        addLookupExp(editor, 88, 'X', .CmdExecuteString);
        addLookupExp(editor, 89, 'E', .CmdCaseEdit);
        addLookupExp(editor, 90, 'L', .CmdCaseLow);
        addLookupExp(editor, 91, 'U', .CmdCaseUp);
        addLookupExp(editor, 92, 'C', .CmdLineCentre);
        addLookupExp(editor, 93, 'F', .CmdLineFill);
        addLookupExp(editor, 94, 'J', .CmdLineJustify);
        addLookupExp(editor, 95, 'L', .CmdLineLeft);
        addLookupExp(editor, 96, 'R', .CmdLineRight);
        addLookupExp(editor, 97, 'S', .CmdLineSquash);
        addLookupExp(editor, 98, 'C', .CmdUserCommandIntroducer);
        addLookupExp(editor, 99, 'B', .CmdWindowBackward);
        addLookupExp(editor, 100, 'C', .CmdWindowMiddle);
        addLookupExp(editor, 101, 'E', .CmdWindowEnd);
        addLookupExp(editor, 102, 'F', .CmdWindowForward);
        addLookupExp(editor, 103, 'H', .CmdWindowSetHeight);
        addLookupExp(editor, 104, 'L', .CmdWindowLeft);
        addLookupExp(editor, 105, 'M', .CmdWindowScroll);
        addLookupExp(editor, 106, 'N', .CmdWindowNew);
        addLookupExp(editor, 107, 'O', .CmdNoop);
        addLookupExp(editor, 108, 'R', .CmdWindowRight);
        addLookupExp(editor, 109, 'S', .CmdNoop);
        addLookupExp(editor, 110, 'T', .CmdWindowTop);
        addLookupExp(editor, 111, 'U', .CmdWindowUpdate);
        addLookupExp(editor, 112, 'A', .CmdExitAbort);
        addLookupExp(editor, 113, 'F', .CmdExitFail);
        addLookupExp(editor, 114, 'S', .CmdExitSuccess);
        addLookupExp(editor, 115, 'D', .CmdDump);
        addLookupExp(editor, 116, 'V', .CmdValidate);
        addLookupExp(editor, 117, '?', .CmdNoSuch);

        editor.LookupExpPtr[cmdIndex(.CmdPrefixAst)] = 1;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixA)] = 1;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixB)] = 8;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixC)] = 15;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixD)] = 17;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixE)] = 22;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixEo)] = 28;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixEq)] = 31;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixF)] = 35;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixFg)] = 46;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixI)] = 52;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixK)] = 52;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixL)] = 64;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixO)] = 66;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixP)] = 69;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixS)] = 71;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixT)] = 80;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixTc)] = 89;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixTf)] = 92;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixU)] = 98;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixW)] = 99;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixX)] = 112;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixY)] = 115;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixZ)] = 115;
        editor.LookupExpPtr[cmdIndex(.CmdPrefixTilde)] = 115;
        editor.LookupExpPtr[cmdIndex(.CmdNoSuch)] = 117;
    }
}
