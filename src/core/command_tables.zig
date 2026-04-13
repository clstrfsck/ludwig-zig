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
    .LeadParamNone,
    .LeadParamPlus,
    .LeadParamMinus,
    .LeadParamPInt,
    .LeadParamNInt,
    .LeadParamPIndef,
    .LeadParamNIndef,
    .LeadParamMarker,
};

pub fn initializeCommandAttributes(editor: *state.Editor) void {
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdNoop)], all_lead_params[0..], .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdUp)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdDown)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdRight)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdLeft)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdHome)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdReturn)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdTab)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdBacktab)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdRubout)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdJump)], all_lead_params[0..], .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdAdvance)], all_lead_params[0..], .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdPositionColumn)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdPositionLine)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdOpSysCommand)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .CmdPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdWindowForward)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdWindowBackward)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdWindowRight)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdWindowLeft)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdWindowScroll)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdWindowTop)], &[_]types.LeadParam{.LeadParamNone}, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdWindowEnd)], &[_]types.LeadParam{.LeadParamNone}, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdWindowNew)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdWindowMiddle)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdWindowSetHeight)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdWindowUpdate)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdGet)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt }, .EqNil, 1, .GetPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdNext)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt }, .EqNil, 1, .CharPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdBridge)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .CharPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdReplace)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 2, .ReplacePrompt, false, false, .ByPrompt, false, true);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdEqualString)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 1, .EqualPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdEqualColumn)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 1, .ColumnPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdEqualMark)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 1, .MarkPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdEqualEol)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdEqualEop)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdEqualEof)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdOvertypeMode)], &[_]types.LeadParam{.LeadParamNone}, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdInsertMode)], &[_]types.LeadParam{.LeadParamNone}, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdOvertypeText)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 1, .TextPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdInsertText)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 1, .TextPrompt, false, true, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdTypeText)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqOld, 1, .TextPrompt, false, true, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdInsertLine)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdInsertChar)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdInsertInvisible)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdDeleteLine)], all_lead_params[0..], .EqDel, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdDeleteChar)], all_lead_params[0..], .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdSwapLine)], all_lead_params[0..], .EqDel, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdSplitLine)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdDittoUp)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdDittoDown)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdCaseUp)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdCaseLow)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdCaseEdit)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef, .LeadParamNIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdSetMarginLeft)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdSetMarginRight)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdLineFill)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdLineJustify)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdLineSquash)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdLineCentre)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdLineLeft)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdLineRight)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdWordAdvance)], all_lead_params[0..], .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdWordDelete)], all_lead_params[0..], .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdAdvanceParagraph)], all_lead_params[0..], .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdDeleteParagraph)], all_lead_params[0..], .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdSpanDefine)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamMarker }, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdSpanTransfer)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdSpanCopy)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdSpanCompile)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdSpanJump)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdSpanIndex)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdSpanAssign)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt, .LeadParamPIndef }, .EqNil, 2, .SpanPrompt, true, false, .TextPrompt, false, true);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdBlockDefine)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamMarker }, .EqNil, 1, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdBlockTransfer)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdBlockCopy)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 1, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFrameKill)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .FramePrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFrameEdit)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .FramePrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFrameReturn)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdSpanExecute)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdSpanExecuteNoRecompile)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 1, .SpanPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFrameParameters)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .ParamPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileInput)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .FilePrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileOutput)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .FilePrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileEdit)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .FilePrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileRead)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileWrite)], all_lead_params[0..], .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileClose)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileRewind)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileKill)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileExecute)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 1, .FilePrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileSave)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileTable)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileGlobalInput)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .FilePrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileGlobalOutput)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 1, .FilePrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileGlobalRewind)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdFileGlobalKill)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.Cmdusercommand_introducer)], &[_]types.LeadParam{.LeadParamNone}, .EqOld, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdUserKey)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 2, .KeyPrompt, true, false, .CmdPrompt, false, true);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdUserParent)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdUserSubprocess)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdHelp)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .TopicPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdVerify)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 1, .VerifyPrompt, true, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdCommand)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdMark)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamMinus, .LeadParamPInt, .LeadParamNInt }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdPage)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdQuit)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdDump)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdValidate)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdExecuteString)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 1, .CmdPrompt, false, true, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdDoLastCommand)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdExtended)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.Cmdexit_abort)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdExitFail)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdExitSuccess)], &[_]types.LeadParam{ .LeadParamNone, .LeadParamPlus, .LeadParamPInt, .LeadParamPIndef }, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdPatternDummyPattern)], &[_]types.LeadParam{}, .EqNil, 1, .PatternPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdPatternDummyText)], &[_]types.LeadParam{}, .EqNil, 1, .TextPrompt, false, false, .NoPrompt, false, false);
    initCmd(&editor.cmd_attrib[cmdIndex(.CmdResizeWindow)], &[_]types.LeadParam{.LeadParamNone}, .EqNil, 0, .NoPrompt, false, false, .NoPrompt, false, false);
}

fn addLookupExp(editor: *state.Editor, index: usize, ch: u8, cmd: types.Commands) void {
    editor.lookup_exp[index].extn = ch;
    editor.lookup_exp[index].command = cmd;
}

pub fn loadCommandTable(editor: *state.Editor, old_version: bool) void {
    editor.lookup = [_]types.CommandObject{.{}} ** types.lookup_count;
    editor.lookup_exp = [_]types.LookupExpType{.{}} ** types.lookup_exp_count;
    editor.lookup_exp_ptr = [_]usize{0} ** types.command_count;

    editor.lookup[2].command = .CmdWindowBackward;
    editor.lookup[4].command = .CmdDeleteChar;
    editor.lookup[5].command = .CmdWindowEnd;
    editor.lookup[6].command = .CmdWindowForward;
    editor.lookup[7].command = .CmdDoLastCommand;
    editor.lookup[9].command = .CmdTab;
    editor.lookup[10].command = .CmdDown;
    editor.lookup[11].command = .CmdDeleteLine;
    editor.lookup[12].command = .CmdInsertLine;
    editor.lookup[13].command = .CmdReturn;
    editor.lookup[14].command = .CmdWindowNew;
    editor.lookup[16].command = .Cmdusercommand_introducer;
    editor.lookup[18].command = .CmdRight;
    editor.lookup[20].command = .CmdWindowTop;
    editor.lookup[21].command = .CmdUp;
    editor.lookup[23].command = .CmdWordAdvance;
    editor.lookup[26].command = .CmdUserParent;
    editor.lookup[30].command = .CmdInsertChar;
    editor.lookup['"'].command = .CmdDittoUp;
    editor.lookup['\''].command = .CmdDittoDown;
    editor.lookup['B'].command = .CmdPrefixB;
    editor.lookup['E'].command = .CmdPrefixE;
    editor.lookup['F'].command = .CmdPrefixF;
    editor.lookup['G'].command = .CmdGet;
    editor.lookup['H'].command = .CmdHelp;
    editor.lookup['M'].command = .CmdMark;
    editor.lookup['Q'].command = .CmdQuit;
    editor.lookup['R'].command = .CmdReplace;
    editor.lookup['S'].command = .CmdPrefixS;
    editor.lookup['U'].command = .CmdPrefixU;
    editor.lookup['V'].command = .CmdVerify;
    editor.lookup['W'].command = .CmdPrefixW;
    editor.lookup['X'].command = .CmdPrefixX;
    editor.lookup['\\'].command = .CmdCommand;
    editor.lookup['{'].command = .CmdSetMarginLeft;
    editor.lookup['}'].command = .CmdSetMarginRight;
    editor.lookup['~'].command = .CmdPrefixTilde;
    editor.lookup[127].command = .CmdRubout;

    if (old_version) {
        editor.lookup[8].command = .CmdRubout;
        editor.lookup['*'].command = .CmdPrefixAst;
        editor.lookup['?'].command = .CmdInsertInvisible;
        editor.lookup['A'].command = .CmdAdvance;
        editor.lookup['C'].command = .CmdInsertChar;
        editor.lookup['D'].command = .CmdDeleteChar;
        editor.lookup['I'].command = .CmdInsertText;
        editor.lookup['J'].command = .CmdJump;
        editor.lookup['K'].command = .CmdDeleteLine;
        editor.lookup['L'].command = .CmdInsertLine;
        editor.lookup['N'].command = .CmdNext;
        editor.lookup['O'].command = .CmdOvertypeText;
        editor.lookup['Y'].command = .CmdPrefixY;
        editor.lookup['Z'].command = .CmdPrefixZ;
        editor.lookup['^'].command = .CmdExecuteString;

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
        addLookupExp(editor, 44, 'C', .Cmdusercommand_introducer);
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
        addLookupExp(editor, 61, 'A', .Cmdexit_abort);
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

        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixAst)] = 1;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixA)] = 4;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixB)] = 4;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixC)] = 5;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixD)] = 5;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixE)] = 5;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixEo)] = 13;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixEq)] = 16;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixF)] = 19;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixFg)] = 29;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixI)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixK)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixL)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixO)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixP)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixS)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixT)] = 44;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixTc)] = 44;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixTf)] = 44;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixU)] = 44;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixW)] = 48;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixX)] = 59;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixY)] = 62;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixZ)] = 70;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixTilde)] = 79;
        editor.lookup_exp_ptr[cmdIndex(.CmdNoSuch)] = 81;
    } else {
        editor.lookup[8].command = .CmdLeft;
        editor.lookup['A'].command = .CmdPrefixA;
        editor.lookup['C'].command = .CmdPrefixC;
        editor.lookup['D'].command = .CmdPrefixD;
        editor.lookup['K'].command = .CmdPrefixK;
        editor.lookup['L'].command = .CmdPrefixL;
        editor.lookup['O'].command = .CmdPrefixO;
        editor.lookup['P'].command = .CmdPrefixP;
        editor.lookup['T'].command = .CmdPrefixT;

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
        addLookupExp(editor, 98, 'C', .Cmdusercommand_introducer);
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
        addLookupExp(editor, 112, 'A', .Cmdexit_abort);
        addLookupExp(editor, 113, 'F', .CmdExitFail);
        addLookupExp(editor, 114, 'S', .CmdExitSuccess);
        addLookupExp(editor, 115, 'D', .CmdDump);
        addLookupExp(editor, 116, 'V', .CmdValidate);
        addLookupExp(editor, 117, '?', .CmdNoSuch);

        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixAst)] = 1;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixA)] = 1;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixB)] = 8;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixC)] = 15;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixD)] = 17;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixE)] = 22;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixEo)] = 28;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixEq)] = 31;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixF)] = 35;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixFg)] = 46;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixI)] = 52;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixK)] = 52;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixL)] = 64;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixO)] = 66;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixP)] = 69;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixS)] = 71;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixT)] = 80;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixTc)] = 89;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixTf)] = 92;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixU)] = 98;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixW)] = 99;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixX)] = 112;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixY)] = 115;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixZ)] = 115;
        editor.lookup_exp_ptr[cmdIndex(.CmdPrefixTilde)] = 115;
        editor.lookup_exp_ptr[cmdIndex(.CmdNoSuch)] = 117;
    }
}
