const std = @import("std");
const arrow = @import("arrow.zig");
const batch_output = @import("../platform/batch_output.zig");
const caseditto = @import("caseditto.zig");
const code_store = @import("code_store.zig");
const eqsgetrep = @import("eqsgetrep.zig");
const file_ops = @import("file.zig");
const frame_ops = @import("frame.zig");
const help_ops = @import("../platform/help.zig");
const interactive_io = @import("../platform/interactive_io.zig");
const sys_ops = @import("../platform/sys.zig");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const newword = @import("newword.zig");
const nextbridge = @import("nextbridge.zig");
const span_ops = @import("span.zig");
const state = @import("state.zig");
const swap = @import("swap.zig");
const tpar_ops = @import("tpar.zig");
const str_object = @import("str_object.zig");
const text = @import("text.zig");
const types = @import("types.zig");
const user_ops = @import("user.zig");
const validate_ops = @import("validate.zig");
const window_ops = @import("window.zig");
const word = @import("word.zig");

const max_level = 100;
const max_rep_count: isize = 65535;

const ParseState = struct {
    status: []const u8 = "",
    key: isize = 0,
    eoln: bool = false,
    pc: isize = 0,
    codeBase: isize = 0,
    currentPoint: types.MarkObject = undefined,
    startPoint: types.MarkObject = undefined,
    endPoint: types.MarkObject = undefined,
    verifyCount: isize = 0,
    fromSpan: bool = false,
    inputBuffer: ?[]const u8 = null,
    inputIndex: usize = 0,
    liveInput: bool = false,
};

const Labels = struct {
    exitLabel: isize = 0,
    failLabel: isize = 0,
    count: isize = 0,
};

const InterpStatus = enum {
    success,
    failure,
    fail_forever,
};

pub const InterpretResult = struct {
    frame: *types.FrameObject,
    ok: bool,
};

fn cmdIndex(command: types.Commands) usize {
    return @intFromEnum(command);
}

fn isInterpCmd(cmd: types.Commands) bool {
    return switch (cmd) {
        .CmdPcJump,
        .CmdExitTo,
        .CmdFailTo,
        .CmdIterate,
        .CmdExitSuccess,
        .CmdExitFail,
        .CmdExitAbort,
        .CmdExtended,
        .CmdVerify,
        .CmdNoop,
        => true,
        else => false,
    };
}

fn compileError(ps: *ParseState, message: []const u8) bool {
    ps.status = message;
    return false;
}

fn nextKey(ps: *ParseState) bool {
    ps.eoln = false;
    if (ps.inputBuffer) |buffer| {
        while (ps.inputIndex < buffer.len and (buffer[ps.inputIndex] == '\r' or buffer[ps.inputIndex] == '\n')) : (ps.inputIndex += 1) {}
        if (ps.inputIndex >= buffer.len) {
            ps.key = 0;
        } else {
            ps.key = buffer[ps.inputIndex];
            ps.inputIndex += 1;
        }
        return true;
    }

    if (ps.liveInput) {
        const key = interactive_io.readInputKey() catch return false;
        if (key) |live_key| {
            ps.key = live_key;
        } else {
            ps.key = 0;
        }
        return true;
    }

    if (!ps.fromSpan) {
        ps.key = 0;
        return false;
    }

    if (ps.currentPoint.Line == ps.endPoint.Line and ps.currentPoint.Col == ps.endPoint.Col) {
        ps.key = 0;
        return true;
    }

    if (ps.currentPoint.Col <= ps.currentPoint.Line.Used) {
        ps.key = ps.currentPoint.Line.Str.?.Get(ps.currentPoint.Col);
        ps.currentPoint.Col += 1;
    } else if (ps.currentPoint.Line != ps.endPoint.Line) {
        ps.key = ' ';
        ps.eoln = true;
        ps.currentPoint.Line = ps.currentPoint.Line.FLink.?;
        ps.currentPoint.Col = 1;
    } else {
        ps.key = 0;
    }
    return true;
}

fn nextNonBl(ps: *ParseState) bool {
    while (true) {
        while (true) {
            if (!nextKey(ps)) {
                return false;
            }
            if (ps.fromSpan and ps.key == '<' and ps.currentPoint.Col <= ps.currentPoint.Line.Used and ps.currentPoint.Line.Str.?.Get(ps.currentPoint.Col) == '>') {
                ps.key = 0;
            }
            if (ps.key != ' ') {
                break;
            }
        }
        if (ps.key != '!') {
            return true;
        }
        if (!ps.fromSpan) {
            ps.status = "Comments illegal";
            return false;
        }
        ps.currentPoint.Col = ps.currentPoint.Line.Used + 1;
    }
}

fn generate(
    editor: *state.Editor,
    ps: *ParseState,
    rep: types.LeadParam,
    cnt: isize,
    op: types.Commands,
    tpar: ?*types.TParObject,
    lbl: isize,
    code: ?*types.CodeHeader,
) bool {
    ps.pc += 1;
    if (ps.codeBase + ps.pc > types.MaxCode) {
        ps.status = "Compiler code overflow";
        return false;
    }
    const cc = &editor.CompilerCode[@intCast(ps.codeBase + ps.pc)];
    cc.Rep = rep;
    cc.Cnt = cnt;
    cc.Op = op;
    cc.Tpar = tpar;
    cc.Lbl = lbl;
    cc.Code = code;
    return true;
}

fn poke(editor: *state.Editor, code_base: isize, location: isize, new_label: isize) void {
    editor.CompilerCode[@intCast(code_base + location)].Lbl = new_label;
}

fn getCount(ps: *ParseState, rep_count: *isize) bool {
    if (ps.key >= '0' and ps.key <= '9') {
        rep_count.* = 0;
        while (true) {
            const digit = ps.key - '0';
            if (rep_count.* <= @divTrunc(max_rep_count - digit, 10)) {
                rep_count.* = rep_count.* * 10 + digit;
            } else {
                return compileError(ps, "Count too large");
            }
            if (!nextKey(ps)) {
                return false;
            }
            if (ps.key < '0' or ps.key > '9') {
                break;
            }
        }
    } else {
        rep_count.* = 1;
    }
    return true;
}

fn scanLeadingParam(ps: *ParseState, rep_sym: *types.LeadParam, rep_count: *isize) bool {
    switch (ps.key) {
        '0'...'9' => {
            rep_sym.* = .LeadParamPInt;
            return getCount(ps, rep_count);
        },
        '+' => {
            if (!nextKey(ps)) return false;
            rep_sym.* = .LeadParamPlus;
            rep_count.* = 1;
            if (ps.key >= '0' and ps.key <= '9') {
                rep_sym.* = .LeadParamPInt;
                return getCount(ps, rep_count);
            }
        },
        '-' => {
            if (!nextKey(ps)) return false;
            rep_sym.* = .LeadParamMinus;
            rep_count.* = -1;
            if (ps.key >= '0' and ps.key <= '9') {
                rep_sym.* = .LeadParamNInt;
                if (!getCount(ps, rep_count)) return false;
                rep_count.* = -rep_count.*;
            }
        },
        '>', '.' => {
            if (!nextKey(ps)) return false;
            rep_sym.* = .LeadParamPIndef;
            rep_count.* = 0;
        },
        '<', ',' => {
            if (!nextKey(ps)) return false;
            rep_sym.* = .LeadParamNIndef;
            rep_count.* = 0;
        },
        '@' => {
            if (!nextKey(ps)) return false;
            rep_sym.* = .LeadParamMarker;
            if (!getCount(ps, rep_count)) return false;
            if (rep_count.* <= 0 or rep_count.* > types.MaxUserMarkNumber) {
                return compileError(ps, "Illegal mark number");
            }
        },
        '=' => {
            if (!nextKey(ps)) return false;
            rep_sym.* = .LeadParamMarker;
            rep_count.* = types.MarkEquals;
        },
        '%' => {
            if (!nextKey(ps)) return false;
            rep_sym.* = .LeadParamMarker;
            rep_count.* = types.MarkModified;
        },
        else => {
            rep_sym.* = .LeadParamNone;
            rep_count.* = 1;
        },
    }
    return true;
}

fn newPromptParam(allocator: std.mem.Allocator) !*types.TParObject {
    const tp = try allocator.create(types.TParObject);
    tp.* = .{
        .Str = try str_object.NewBlankStrObject(allocator, types.MaxStrLen),
        .Dlm = types.TpdPrompt,
    };
    return tp;
}

fn scanTrailingParam(
    allocator: std.mem.Allocator,
    editor: *state.Editor,
    ps: *ParseState,
    command: types.Commands,
    rep_sym: types.LeadParam,
    full_scan: bool,
    result: *?*types.TParObject,
) bool {
    var tp_count = editor.CmdAttrib[cmdIndex(command)].TpCount;
    result.* = null;

    if (tp_count < 0) {
        tp_count = if (rep_sym == .LeadParamMinus) 0 else -tp_count;
    }

    if (tp_count <= 0) {
        return true;
    }

    if (!full_scan) {
        var head: ?*types.TParObject = null;
        var tail: ?*types.TParObject = null;
        var i: isize = 1;
        while (i <= tp_count) : (i += 1) {
            const node = newPromptParam(allocator) catch return compileError(ps, "Out of memory");
            if (head == null) {
                head = node;
            } else {
                tail.?.Nxt = node;
            }
            tail = node;
        }
        result.* = head;
        return true;
    }

    if (!nextKey(ps)) {
        return false;
    }
    const par_delim = ps.key;
    if (ps.key < 0 or ps.key > types.MaxSetRange or !@import("chars.zig").ChIsPunctuation(@intCast(ps.key))) {
        return compileError(ps, "Illegal parameter delimiter");
    }

    var head: ?*types.TParObject = null;
    var prev_param: ?*types.TParObject = null;
    var tci: isize = 1;
    while (tci <= tp_count) : (tci += 1) {
        var param_head: ?*types.TParObject = null;
        var param_tail: ?*types.TParObject = null;

        while (true) {
            var par_length: isize = 0;
            const par_string = str_object.NewBlankStrObject(allocator, types.MaxStrLen) catch return compileError(ps, "Out of memory");
            while (true) {
                if (!nextKey(ps)) {
                    return false;
                }
                if (ps.key == 0) {
                    return compileError(ps, "Missing trailing delimiter");
                }
                par_length += 1;
                par_string.Set(par_length, @intCast(ps.key));
                if (ps.eoln or ps.key == par_delim) {
                    break;
                }
            }
            par_length -= 1;
            if (ps.eoln and !editor.CmdAttrib[cmdIndex(command)].TparInfo[@intCast(tci)].MlAllowed) {
                return compileError(ps, "Missing trailing delimiter");
            }

            const node = allocator.create(types.TParObject) catch return compileError(ps, "Out of memory");
            node.* = .{
                .Len = par_length,
                .Dlm = @intCast(par_delim),
                .Str = par_string,
            };
            if (param_head == null) {
                param_head = node;
            } else {
                param_tail.?.Con = node;
            }
            param_tail = node;

            if (ps.key == par_delim) {
                break;
            }
        }

        if (head == null) {
            head = param_head;
        } else {
            prev_param.?.Nxt = param_head;
        }
        prev_param = param_head;
    }

    result.* = head;
    return true;
}

fn lookupExpansionRange(editor: *state.Editor, command: types.Commands) struct { usize, usize } {
    const start = editor.LookupExpPtr[cmdIndex(command)];
    var next = cmdIndex(command) + 1;
    while (next < editor.LookupExpPtr.len and editor.LookupExpPtr[next] == 0) : (next += 1) {}
    const end = if (next < editor.LookupExpPtr.len) editor.LookupExpPtr[next] else types.LookupExpCount;
    return .{ start, end };
}

fn scanSimpleCommand(
    allocator: std.mem.Allocator,
    editor: *state.Editor,
    ps: *ParseState,
    command: types.Commands,
    rep_sym: types.LeadParam,
    rep_count: *isize,
    pc1: *isize,
    full_scan: bool,
) bool {
    const lp_allowed = editor.CmdAttrib[cmdIndex(command)].LpAllowed;
    if ((lp_allowed & (@as(u32, 1) << @intCast(@intFromEnum(rep_sym)))) == 0) {
        return compileError(ps, "Illegal leading parameter");
    }

    if (command == .CmdVerify) {
        ps.verifyCount += 1;
        if (ps.verifyCount > types.MaxVerify) {
            return compileError(ps, "Too many verify commands in span");
        }
        rep_count.* = ps.verifyCount;
    }

    var tparam: ?*types.TParObject = null;
    if (!scanTrailingParam(allocator, editor, ps, command, rep_sym, full_scan, &tparam)) {
        return false;
    }

    if (!generate(editor, ps, rep_sym, rep_count.*, command, tparam, 0, null)) {
        return false;
    }
    pc1.* = ps.pc;
    return true;
}

fn scanExitHandler(
    allocator: std.mem.Allocator,
    editor: *state.Editor,
    ps: *ParseState,
    pc1: isize,
    pc4: *isize,
    full_scan: bool,
) bool {
    if (!nextNonBl(ps)) {
        return false;
    }
    if (ps.key == '[') {
        if (!nextNonBl(ps)) {
            return false;
        }
        while (ps.key != ':' and ps.key != ']') {
            if (!scanCommand(allocator, editor, ps, full_scan)) {
                return false;
            }
        }
        if (ps.key == ':') {
            if (!generate(editor, ps, .LeadParamNone, 0, .CmdPcJump, null, 0, null)) {
                return false;
            }
            pc4.* = ps.pc;
            poke(editor, ps.codeBase, pc1, ps.pc + 1);
            if (!nextNonBl(ps)) {
                return false;
            }
            while (ps.key != ']') {
                if (!scanCommand(allocator, editor, ps, full_scan)) {
                    return false;
                }
            }
            poke(editor, ps.codeBase, pc4.*, ps.pc + 1);
        } else {
            poke(editor, ps.codeBase, pc1, ps.pc + 1);
        }
        if (!nextNonBl(ps)) {
            return false;
        }
    }
    return true;
}

fn scanCompoundCommand(
    allocator: std.mem.Allocator,
    editor: *state.Editor,
    ps: *ParseState,
    rep_sym: types.LeadParam,
    rep_count: isize,
    pc1: *isize,
    pc2: *isize,
    pc3: *isize,
) bool {
    if (rep_sym != .LeadParamNone and rep_sym != .LeadParamPlus and rep_sym != .LeadParamPInt and rep_sym != .LeadParamPIndef) {
        return compileError(ps, "Illegal leading parameter");
    }
    if (!generate(editor, ps, .LeadParamNone, 0, .CmdExitTo, null, 0, null)) {
        return false;
    }
    pc2.* = ps.pc;
    if (!generate(editor, ps, .LeadParamNone, 0, .CmdFailTo, null, 0, null)) {
        return false;
    }
    pc1.* = ps.pc;
    pc3.* = ps.pc + 1;
    if (rep_sym != .LeadParamPIndef) {
        if (!generate(editor, ps, .LeadParamNone, rep_count, .CmdIterate, null, 0, null)) {
            return false;
        }
    }
    if (!nextNonBl(ps)) {
        return false;
    }
    while (ps.key != ')') {
        if (!scanCommand(allocator, editor, ps, true)) {
            return false;
        }
    }
    if (!generate(editor, ps, .LeadParamNone, 0, .CmdPcJump, null, pc3.*, null)) {
        return false;
    }
    poke(editor, ps.codeBase, pc2.*, ps.pc + 1);
    return true;
}

fn scanCommand(
    allocator: std.mem.Allocator,
    editor: *state.Editor,
    ps: *ParseState,
    full_scan: bool,
) bool {
    var rep_count: isize = 0;
    var rep_sym: types.LeadParam = .LeadParamNone;
    if (!scanLeadingParam(ps, &rep_sym, &rep_count)) {
        return false;
    }

    if (ps.key >= 0 and ps.key <= types.MaxSetRange) {
        ps.key = @intCast(@import("chars.zig").ChToUpper(@intCast(ps.key)));
    }

    var command = editor.Lookup[@intCast(ps.key)].Command;
    while (editor.Prefixes.isSet(@intFromEnum(command))) {
        if (!nextKey(ps)) {
            return false;
        }
        if (ps.key < 0 or ps.key > types.MaxSetRange) {
            return compileError(ps, "Command not valid");
        }
        const bounds = lookupExpansionRange(editor, command);
        var index = bounds.@"0";
        const target = @import("chars.zig").ChToUpper(@intCast(ps.key));
        while (index < bounds.@"1" and target != editor.LookupExp[index].Extn) : (index += 1) {}
        if (index < bounds.@"1") {
            command = editor.LookupExp[index].Command;
        } else {
            return compileError(ps, "Command not valid");
        }
    }

    var pc1: isize = 0;
    if (ps.key == '(') {
        var pc2: isize = 0;
        var pc3: isize = 0;
        if (!scanCompoundCommand(allocator, editor, ps, rep_sym, rep_count, &pc1, &pc2, &pc3)) {
            return false;
        }
    } else if (command != .CmdNoop) {
        if (!scanSimpleCommand(allocator, editor, ps, command, rep_sym, &rep_count, &pc1, full_scan)) {
            return false;
        }
    } else {
        return compileError(ps, "Command not valid");
    }

    if (full_scan) {
        var pc4: isize = 0;
        return scanExitHandler(allocator, editor, ps, pc1, &pc4, full_scan);
    }
    return true;
}

pub fn CodeDiscard(editor: *state.Editor, code_head: *?*types.CodeHeader) void {
    code_store.CodeDiscard(editor, code_head);
}

fn compileParsed(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    span: *types.SpanObject,
    ps: *ParseState,
    full_scan: bool,
) !bool {
    if (span.Code != null) {
        CodeDiscard(editor, &span.Code);
    }

    ps.codeBase = editor.CodeTop;
    ps.pc = 0;
    ps.verifyCount = 0;

    if (!nextNonBl(ps)) {
        editor.ExitAbort = true;
        return false;
    }
    if (ps.key == 0) {
        editor.ExitAbort = true;
        return false;
    }

    if (full_scan) {
        while (ps.key != 0) {
            if (!scanCommand(allocator, editor, ps, true)) {
                editor.ExitAbort = true;
                return false;
            }
        }
    } else {
        if (!scanCommand(allocator, editor, ps, false)) {
            editor.ExitAbort = true;
            return false;
        }
    }

    if (!generate(editor, ps, .LeadParamPInt, 1, .CmdExitSuccess, null, 0, null)) {
        editor.ExitAbort = true;
        return false;
    }

    const header = try allocator.create(types.CodeHeader);
    header.* = .{
        .Ref = 1,
        .Code = ps.codeBase + 1,
        .Len = ps.pc,
        .FLink = editor.CodeList.?.FLink,
        .BLink = editor.CodeList,
    };
    editor.CodeList.?.FLink.?.BLink = header;
    editor.CodeList.?.FLink = header;
    editor.CodeTop = ps.codeBase + ps.pc;
    span.Code = header;
    return true;
}

pub fn CodeCompile(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    span: *types.SpanObject,
    from_span: bool,
) !bool {
    var ps = ParseState{
        .fromSpan = from_span,
    };
    var uses_immediate_input = false;
    _ = frame;

    defer if (uses_immediate_input) {
        editor.ImmediateInputIndex = ps.inputIndex;
        if (editor.ImmediateInput) |buffer| {
            if (editor.ImmediateInputIndex >= buffer.len) {
                editor.clearImmediateInput();
            }
        }
    };

    if (!from_span) {
        if (editor.ImmediateInput) |buffer| {
            ps.inputBuffer = buffer;
            ps.inputIndex = editor.ImmediateInputIndex;
            uses_immediate_input = true;
        } else if (editor.LudwigMode == .LudwigScreen) {
            ps.liveInput = true;
        } else {
            editor.ExitAbort = true;
            return false;
        }
    }
    if (from_span and (span.MarkOne == null or span.MarkTwo == null)) {
        editor.ExitAbort = true;
        return false;
    }
    if (from_span) {
        ps.startPoint = span.MarkOne.?.*;
        ps.endPoint = span.MarkTwo.?.*;
        ps.currentPoint = ps.startPoint;
    }

    return compileParsed(editor, allocator, span, &ps, from_span);
}

pub fn CodeCompileString(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    span: *types.SpanObject,
    source: []const u8,
) !bool {
    var ps = ParseState{
        .fromSpan = false,
        .inputBuffer = source,
    };
    return compileParsed(editor, allocator, span, &ps, false);
}

fn codeCompileBuffer(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    span: *types.SpanObject,
    source: []const u8,
    full_scan: bool,
) !bool {
    var ps = ParseState{
        .fromSpan = false,
        .inputBuffer = source,
    };
    return compileParsed(editor, allocator, span, &ps, full_scan);
}

fn resolveLeadMark(frame: *types.FrameObject, count: isize) ?*types.MarkObject {
    if (count < 0 or count > types.MaxMarkNumber) {
        return null;
    }
    return frame.Marks[@intCast(count)];
}

fn markModifiedAtDot(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !void {
    frame.TextModified = true;
    if (frame.Dot) |dot| {
        try mark_ops.MarkCreate(allocator, dot.Line, dot.Col, &frame.Marks[types.MarkModified]);
    }
}

fn findSpanByName(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    name: []const u8,
) !?*types.SpanObject {
    var span_ptr: ?*types.SpanObject = null;
    var span_prev: ?*types.SpanObject = null;
    if (try span_ops.SpanFind(editor, allocator, name, &span_ptr, &span_prev)) {
        return span_ptr;
    }
    return null;
}

fn emitBatchMessage(editor: *const state.Editor, message: []const u8) void {
    switch (editor.LudwigMode) {
        .LudwigScreen => interactive_io.queueStatusMessage(message),
        .LudwigBatch, .LudwigHardcopy => {
            if (editor.BatchOutputEnabled) {
                batch_output.printMessage(message);
            }
        },
    }
}

fn findSpanByNameOrMessage(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    name: []const u8,
) !?*types.SpanObject {
    const span_ptr = try findSpanByName(editor, allocator, name);
    if (span_ptr == null) {
        emitBatchMessage(editor, "No such span.");
    }
    return span_ptr;
}

fn createNamedSpan(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    name: []const u8,
    first_mark: *types.MarkObject,
    last_mark: *types.MarkObject,
) !bool {
    return span_ops.SpanCreate(editor, allocator, name, first_mark, last_mark);
}

fn destroyNamedSpan(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    span_slot: *?*types.SpanObject,
) bool {
    return span_ops.SpanDestroy(editor, allocator, span_slot);
}

fn executeAdvance(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
    target_mark: ?*types.MarkObject,
) !bool {
    var new_line = frame.Dot.?.Line;
    var remaining = count;
    var success = rept == .LeadParamPIndef or rept == .LeadParamNIndef or rept == .LeadParamMarker;

    switch (rept) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            while (remaining > 0) : (remaining -= 1) {
                new_line = new_line.FLink orelse return false;
            }
            if (new_line.FLink == null) return false;
            success = true;
        },
        .LeadParamMinus, .LeadParamNInt => {
            remaining = -remaining;
            while (remaining > 0) : (remaining -= 1) {
                new_line = new_line.BLink orelse return false;
            }
            success = true;
        },
        .LeadParamPIndef => new_line = frame.LastGroup.?.LastLine.?,
        .LeadParamNIndef => new_line = frame.FirstGroup.?.FirstLine.?,
        .LeadParamMarker => new_line = target_mark.?.Line,
    }

    if (success) {
        try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkEquals]);
        try mark_ops.MarkCreate(allocator, new_line, 1, &frame.Dot);
    }
    return success;
}

fn executeArrowCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    command: types.Commands,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var new_eql = frame.Dot.?.*;
    const used_split_line = command == .CmdReturn and
        editor.EditMode == .ModeInsert and
        types.frameOptionsHas(frame.Options, .OptNewLine) and
        frame.Dot.?.Line.FLink != null;

    const cmd_success = switch (command) {
        .CmdLeft => arrow.doCmdLeft(frame, rept, count, &new_eql),
        .CmdRight => arrow.doCmdRight(frame, rept, count, &new_eql),
        .CmdTab => arrow.doCmdTabBacktab(frame, 1, count, &new_eql),
        .CmdBacktab => arrow.doCmdTabBacktab(frame, -1, count, &new_eql),
        .CmdHome => arrow.doCmdHome(&editor.Screen, frame, &new_eql),
        .CmdUp => try arrow.doCmdUp(allocator, frame, rept, count, &new_eql),
        .CmdDown => try arrow.doCmdDown(
            allocator,
            frame,
            rept,
            count,
            &new_eql,
            line_ops.LineToNumber(frame.LastGroup.?.LastLine.?),
        ),
        .CmdReturn => blk: {
            if (editor.EditMode == .ModeInsert and types.frameOptionsHas(frame.Options, .OptNewLine)) {
                if (frame.Dot.?.Line.FLink == null) {
                    try text.TextRealizeNull(allocator, frame.Dot.?.Line);
                    var eop_line_nr = line_ops.LineToNumber(frame.LastGroup.?.LastLine.?);
                    break :blk try arrow.doCmdReturn(allocator, frame, count, &new_eql, &eop_line_nr);
                }
                break :blk try text.TextSplitLine(allocator, frame.Dot.?, 0, &frame.Marks[types.MarkEquals]);
            }
            var eop_line_nr = line_ops.LineToNumber(frame.LastGroup.?.LastLine.?);
            break :blk try arrow.doCmdReturn(allocator, frame, count, &new_eql, &eop_line_nr);
        },
        else => false,
    };

    var final_success = cmd_success;
    if (cmd_success and !used_split_line) {
        try mark_ops.MarkCreate(allocator, new_eql.Line, new_eql.Col, &frame.Marks[types.MarkEquals]);
        if (command == .CmdDown and rept != .LeadParamPIndef and frame.Dot.?.Line.FLink == null) {
            final_success = false;
        }
    }
    return final_success;
}

const LineSelection = struct {
    first: ?*types.LineHdrObject = null,
    last: ?*types.LineHdrObject = null,
};

fn computeLineRange(
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
    mark: ?*types.MarkObject,
) ?LineSelection {
    const dot = frame.Dot orelse return null;
    var first_line: ?*types.LineHdrObject = dot.Line;
    var last_line: ?*types.LineHdrObject = dot.Line;

    switch (rept) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            if (count == 0) {
                first_line = null;
            } else if (count <= 20) {
                var line_nr: isize = 1;
                while (line_nr < count) : (line_nr += 1) {
                    last_line = last_line.?.FLink orelse return null;
                }
                if (last_line.?.FLink == null) {
                    return null;
                }
            } else {
                const line_nr = line_ops.LineToNumber(first_line.?);
                last_line = line_ops.LineFromNumber(frame, line_nr + count - 1) orelse return null;
                if (last_line.?.FLink == null) {
                    return null;
                }
            }
        },
        .LeadParamMinus, .LeadParamNInt => {
            const abs_count = -count;
            last_line = dot.Line.BLink orelse return null;
            if (abs_count <= 20) {
                var line_nr: isize = 1;
                while (line_nr <= abs_count) : (line_nr += 1) {
                    first_line = first_line.?.BLink orelse return null;
                }
            } else {
                var line_nr = line_ops.LineToNumber(last_line.?);
                if (abs_count > line_nr) {
                    return null;
                }
                line_nr = line_nr - abs_count + 1;
                first_line = line_ops.LineFromNumber(frame, line_nr);
            }
        },
        .LeadParamPIndef => {
            if (dot.Line.FLink == null) {
                first_line = null;
            } else {
                last_line = frame.LastGroup.?.LastLine.?.BLink;
            }
        },
        .LeadParamNIndef => {
            last_line = dot.Line.BLink;
            if (last_line == null) {
                first_line = null;
            } else {
                first_line = frame.FirstGroup.?.FirstLine;
            }
        },
        .LeadParamMarker => {
            const mark_line = mark orelse return null;
            if (mark_line.Line == first_line.?) {
                first_line = null;
            } else if (mark_line.Line.FLink == first_line.?) {
                first_line = mark_line.Line;
                last_line = mark_line.Line;
            } else if (mark_line.Line.BLink == first_line.?) {
                last_line = first_line.?;
            } else {
                const mark_line_nr = line_ops.LineToNumber(mark_line.Line);
                const line_nr = line_ops.LineToNumber(dot.Line);
                if (mark_line_nr < line_nr) {
                    first_line = mark_line.Line;
                    last_line = last_line.?.BLink;
                } else {
                    last_line = mark_line.Line.BLink;
                }
            }
        },
    }

    return .{
        .first = first_line,
        .last = last_line,
    };
}

fn markSortOrder(left: *types.MarkObject, right: *types.MarkObject) std.math.Order {
    const left_line = line_ops.LineToNumber(left.Line);
    const right_line = line_ops.LineToNumber(right.Line);
    if (left_line < right_line) return .lt;
    if (left_line > right_line) return .gt;
    return std.math.order(left.Col, right.Col);
}

fn joinLines(allocator: std.mem.Allocator, frame: *types.FrameObject) !bool {
    if (!types.frameOptionsHas(frame.Options, .OptNewLine)) {
        return false;
    }
    const previous = frame.Dot.?.Line.BLink orelse return false;
    var other_mark: ?*types.MarkObject = null;
    defer mark_ops.MarkDestroy(allocator, &other_mark);
    try mark_ops.MarkCreate(allocator, previous, previous.Used + 1, &other_mark);
    if (!try text.TextRemove(allocator, other_mark.?, frame.Dot.?)) {
        return false;
    }
    frame.TextModified = true;
    try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkModified]);
    return true;
}

fn executeInsertChar(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var rept_mut = rept;
    if (rept_mut == .LeadParamMinus) {
        rept_mut = .LeadParamNInt;
    }

    const count_abs: isize = @intCast(@abs(count));
    const maximum = if (frame.Dot.?.Col <= frame.Dot.?.Line.Used)
        types.MaxStrLen - frame.Dot.?.Line.Used
    else
        types.MaxStrLen - frame.Dot.?.Col;
    if (count_abs > maximum) {
        return false;
    }

    if (!try text.TextInsert(allocator, true, 1, editor.BlankString.?, count_abs, frame.Dot.?)) {
        return false;
    }

    const eql_col = if (rept_mut == .LeadParamNInt)
        frame.Dot.?.Col - count_abs
    else
        frame.Dot.?.Col;
    if (rept_mut != .LeadParamNInt) {
        try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col - count_abs, &frame.Dot);
    }
    frame.TextModified = true;
    try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkModified]);
    try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, eql_col, &frame.Marks[types.MarkEquals]);
    return true;
}

fn executeDeleteMarkedRange(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    oops_frame: *types.FrameObject,
    the_mark: *types.MarkObject,
) !bool {
    var start = frame.Dot.?;
    var finish = the_mark;
    if (markSortOrder(start, finish) == .gt) {
        start = the_mark;
        finish = frame.Dot.?;
    }

    if (frame != oops_frame) {
        const oops_span = oops_frame.Span orelse return false;
        try mark_ops.MarkCreate(allocator, oops_frame.LastGroup.?.LastLine.?, 1, &oops_span.MarkTwo);
        if (!try text.TextMove(
            allocator,
            false,
            1,
            start,
            finish,
            oops_span.MarkTwo.?,
            &oops_frame.Marks[types.MarkEquals],
            &oops_frame.Dot,
        )) {
            return false;
        }
        oops_frame.TextModified = true;
        try mark_ops.MarkCreate(allocator, oops_frame.Dot.?.Line, oops_frame.Dot.?.Col, &oops_frame.Marks[types.MarkModified]);
    } else if (!try text.TextRemove(allocator, start, finish)) {
        return false;
    }

    frame.TextModified = true;
    try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkModified]);
    return true;
}

fn executeDeleteChar(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    oops_frame: ?*types.FrameObject,
    rept: types.LeadParam,
    count: isize,
    the_mark: ?*types.MarkObject,
    from_span: bool,
) !bool {
    if (rept == .LeadParamMarker) {
        const oops = oops_frame orelse return false;
        const marker = the_mark orelse return false;
        return executeDeleteMarkedRange(allocator, frame, oops, marker);
    }

    var count_mut = count;
    switch (rept) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            if (count_mut > types.MaxStrLenP - frame.Dot.?.Col) {
                return false;
            }
        },
        .LeadParamPIndef => {
            count_mut = types.MaxStrLenP - frame.Dot.?.Col;
        },
        .LeadParamMinus, .LeadParamNInt => {
            count_mut = -count_mut;
            if (count_mut < frame.Dot.?.Col) {
                try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col - count_mut, &frame.Dot);
            } else if (!from_span and count_mut == 1 and frame.Dot.?.Col == 1 and try joinLines(allocator, frame)) {
                mark_ops.MarkDestroy(allocator, &frame.Marks[types.MarkEquals]);
                return true;
            } else {
                return false;
            }
        },
        .LeadParamNIndef => {
            count_mut = frame.Dot.?.Col - 1;
            try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, 1, &frame.Dot);
        },
        .LeadParamMarker => unreachable,
    }

    var end_mark: ?*types.MarkObject = null;
    defer mark_ops.MarkDestroy(allocator, &end_mark);
    try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col + count_mut, &end_mark);
    if (!try text.TextRemove(allocator, frame.Dot.?, end_mark.?)) {
        return false;
    }

    frame.TextModified = true;
    try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkModified]);
    mark_ops.MarkDestroy(allocator, &frame.Marks[types.MarkEquals]);
    return true;
}

fn executeDeleteLine(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    oops_frame: ?*types.FrameObject,
    rept: types.LeadParam,
    count: isize,
    the_mark: ?*types.MarkObject,
) !bool {
    const range = computeLineRange(frame, rept, count, the_mark) orelse return false;
    if (range.first == null) {
        return true;
    }

    const first = range.first.?;
    const last = range.last.?;
    const after = last.FLink orelse return false;
    const dot_col = frame.Dot.?.Col;
    const oops = oops_frame orelse return false;

    try mark_ops.MarksSqueeze(allocator, first, 1, after, 1);
    line_ops.LinesExtract(first, last);

    if (frame != oops) {
        try line_ops.LinesInject(allocator, first, last, oops.LastGroup.?.LastLine.?);
        try mark_ops.MarkCreate(allocator, first, 1, &oops.Marks[types.MarkEquals]);
        try mark_ops.MarkCreate(allocator, oops.LastGroup.?.LastLine.?, 1, &oops.Dot);
        oops.TextModified = true;
        try mark_ops.MarkCreate(allocator, oops.Dot.?.Line, oops.Dot.?.Col, &oops.Marks[types.MarkModified]);
    }

    frame.Dot.?.Col = dot_col;
    frame.TextModified = true;
    try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkModified]);
    return true;
}

fn executeRubout(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
    from_span: bool,
) !bool {
    if (editor.EditMode == .ModeInsert) {
        const delete_rept: types.LeadParam = if (rept == .LeadParamPIndef) .LeadParamNIndef else .LeadParamNInt;
        return executeDeleteChar(allocator, frame, null, delete_rept, -count, null, from_span);
    }

    var count_mut = count;
    if (rept == .LeadParamPIndef) {
        count_mut = frame.Dot.?.Col - 1;
    }
    if (count_mut > frame.Dot.?.Col - 1) {
        return false;
    }

    const eql_col = frame.Dot.?.Col;
    try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col - count_mut, &frame.Dot);
    if (!try text.TextOvertype(allocator, true, 1, editor.BlankString.?, count_mut, frame.Dot.?)) {
        return false;
    }
    try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col - count_mut, &frame.Dot);

    frame.TextModified = true;
    try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkModified]);
    try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, eql_col, &frame.Marks[types.MarkEquals]);
    return true;
}

fn executeJump(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
    the_mark: ?*types.MarkObject,
) !bool {
    switch (rept) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            if (frame.Dot.?.Col + count > types.MaxStrLenP) {
                return false;
            }
            try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col + count, &frame.Dot);
        },
        .LeadParamMinus, .LeadParamNInt => {
            if (frame.Dot.?.Col <= -count) {
                return false;
            }
            try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col + count, &frame.Dot);
        },
        .LeadParamPIndef => {
            if (frame.Dot.?.Col > frame.Dot.?.Line.Used + 1) {
                return false;
            }
            try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Line.Used + 1, &frame.Dot);
        },
        .LeadParamNIndef => {
            try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, 1, &frame.Dot);
        },
        .LeadParamMarker => {
            const marker = the_mark orelse return false;
            try mark_ops.MarkCreate(allocator, marker.Line, marker.Col, &frame.Dot);
        },
    }
    return true;
}

fn clampOpsysTabWidth(editor: *const state.Editor) usize {
    return @intCast(@min(@as(isize, 8), @max(@as(isize, 2), editor.FileData.TabWidth)));
}

fn isOpsysLineTerminator(byte: u8) bool {
    return switch (byte) {
        '\n', '\r', 0x0b, 0x0c => true,
        else => false,
    };
}

fn isPrintableOpsysByte(byte: u8) bool {
    return byte >= 0x20 and byte != 0x7f;
}

fn appendOpsysLine(
    allocator: std.mem.Allocator,
    first: *?*types.LineHdrObject,
    last: *?*types.LineHdrObject,
    content: []const u8,
) !void {
    const range = try line_ops.LinesCreate(allocator, 1);
    if (content.len > 0) {
        try line_ops.LineChangeLength(allocator, range.first, @intCast(content.len));
        try line_ops.setLineContent(range.first, content);
    } else {
        range.first.Used = 0;
    }

    if (last.*) |tail| {
        tail.FLink = range.first;
        range.first.BLink = tail;
    } else {
        first.* = range.first;
    }
    last.* = range.last;
}

fn buildOpsysLineRange(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    output: []const u8,
) !?line_ops.LineRange {
    var first: ?*types.LineHdrObject = null;
    var last: ?*types.LineHdrObject = null;
    var line_buffer: std.ArrayListUnmanaged(u8) = .{};
    defer line_buffer.deinit(allocator);

    const tab_width = clampOpsysTabWidth(editor);
    for (output) |byte| {
        if (isOpsysLineTerminator(byte)) {
            try appendOpsysLine(allocator, &first, &last, line_buffer.items);
            line_buffer.clearRetainingCapacity();
            continue;
        }

        if (byte == '\t') {
            var spaces = tab_width - (line_buffer.items.len % tab_width);
            while (spaces > 0) : (spaces -= 1) {
                if (line_buffer.items.len == types.MaxStrLen) {
                    try appendOpsysLine(allocator, &first, &last, line_buffer.items);
                    line_buffer.clearRetainingCapacity();
                }
                try line_buffer.append(allocator, ' ');
            }
            continue;
        }

        if (!isPrintableOpsysByte(byte)) {
            continue;
        }

        if (line_buffer.items.len == types.MaxStrLen) {
            try appendOpsysLine(allocator, &first, &last, line_buffer.items);
            line_buffer.clearRetainingCapacity();
        }
        try line_buffer.append(allocator, byte);
    }

    if (line_buffer.items.len > 0 or (output.len > 0 and !isOpsysLineTerminator(output[output.len - 1]))) {
        try appendOpsysLine(allocator, &first, &last, line_buffer.items);
    }

    if (first == null or last == null) {
        return null;
    }
    return .{
        .first = first.?,
        .last = last.?,
    };
}

fn runOpsysCommand(
    allocator: std.mem.Allocator,
    command_text: []const u8,
) ![]u8 {
    const shell_script = try std.fmt.allocPrint(allocator, "exec 2>&1; {s}", .{command_text});
    defer allocator.free(shell_script);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "sh", "-c", shell_script },
        .max_output_bytes = @intCast(types.MaxSpace),
    });

    if (result.stderr.len == 0) {
        return result.stdout;
    }
    if (result.stdout.len == 0) {
        allocator.free(result.stdout);
        return result.stderr;
    }

    const combined = try allocator.alloc(u8, result.stdout.len + result.stderr.len);
    @memcpy(combined[0..result.stdout.len], result.stdout);
    @memcpy(combined[result.stdout.len..], result.stderr);
    allocator.free(result.stdout);
    allocator.free(result.stderr);
    return combined;
}

fn executeOpsysCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    tparam: ?*types.TParObject,
) !bool {
    var request: types.TParObject = .{};
    if (!try tpar_ops.TparGet1(allocator, editor, frame, tparam, .CmdOpSysCommand, &request)) {
        return false;
    }
    if (request.Len == 0 or request.Len > types.FileNameLen) {
        return false;
    }

    const output = runOpsysCommand(allocator, request.Str.?.Slice(1, request.Len)) catch return false;
    defer allocator.free(output);

    const range = (try buildOpsysLineRange(editor, allocator, output)) orelse return false;
    try line_ops.LinesInject(allocator, range.first, range.last, frame.Dot.?.Line);
    try mark_ops.MarkCreate(allocator, range.first, 1, &frame.Marks[types.MarkEquals]);
    try mark_ops.MarkCreate(allocator, range.last.FLink.?, 1, &frame.Dot);
    try markModifiedAtDot(allocator, frame);
    return true;
}

fn Execute(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame_slot: **types.FrameObject,
    special_frames: *types.SpecialFrames,
    command: types.Commands,
    rept: types.LeadParam,
    count: isize,
    tparam: ?*types.TParObject,
    from_span: bool,
) anyerror!bool {
    var current_frame = frame_slot.*;
    defer frame_slot.* = current_frame;
    const old_dot = current_frame.Dot.?.*;
    const old_frame = current_frame;
    var cmd_success = false;
    const the_mark = if (rept == .LeadParamMarker) resolveLeadMark(current_frame, count) else null;
    if (rept == .LeadParamMarker and the_mark == null) {
        emitBatchMessage(editor, "Mark Not Defined.");
        return false;
    }

    switch (command) {
        .CmdAdvance => {
            cmd_success = try executeAdvance(allocator, current_frame, rept, count, the_mark);
        },
        .CmdBacktab, .CmdDown, .CmdHome, .CmdLeft, .CmdReturn, .CmdRight, .CmdTab, .CmdUp => {
            cmd_success = try executeArrowCommand(editor, allocator, current_frame, command, rept, count);
        },
        .CmdBridge, .CmdNext => {
            var request: types.TParObject = .{};
            if (try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                cmd_success = try nextbridge.NextbridgeCommand(allocator, current_frame, count, &request, command == .CmdBridge);
            }
        },
        .CmdCaseEdit, .CmdCaseLow, .CmdCaseUp, .CmdDittoDown, .CmdDittoUp => {
            cmd_success = try caseditto.CaseDittoCommand(
                allocator,
                current_frame,
                command,
                rept,
                count,
                true,
                editor.EditMode,
                editor.PreviousMode,
            );
        },
        .CmdDeleteChar => {
            cmd_success = try executeDeleteChar(allocator, current_frame, special_frames.Oops, rept, count, the_mark, from_span);
        },
        .CmdDeleteLine => {
            cmd_success = try executeDeleteLine(allocator, current_frame, special_frames.Oops, rept, count, the_mark);
        },
        .CmdDump => {
            cmd_success = false;
        },
        .CmdEqualColumn => {
            var request: types.TParObject = .{};
            if (try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                var index: isize = 1;
                if (tpar_ops.TparToIntMessage(editor, &request, &index)) |column| {
                    cmd_success = switch (rept) {
                        .LeadParamNone, .LeadParamPlus => current_frame.Dot.?.Col == column,
                        .LeadParamMinus => current_frame.Dot.?.Col != column,
                        .LeadParamPIndef => current_frame.Dot.?.Col >= column,
                        .LeadParamNIndef => current_frame.Dot.?.Col <= column,
                        else => false,
                    };
                }
            }
        },
        .CmdEqualEol => {
            const eol_col = current_frame.Dot.?.Line.Used + 1;
            cmd_success = switch (rept) {
                .LeadParamNone, .LeadParamPlus => current_frame.Dot.?.Col == eol_col,
                .LeadParamMinus => current_frame.Dot.?.Col != eol_col,
                .LeadParamPIndef => current_frame.Dot.?.Col >= eol_col,
                .LeadParamNIndef => current_frame.Dot.?.Col <= eol_col,
                else => false,
            };
        },
        .CmdEqualEop, .CmdEqualEof => {
            cmd_success = current_frame.Dot.?.Line.FLink == null;
            if (command == .CmdEqualEof and current_frame.InputFile != 0) {
                const input_file = editor.Files[@intCast(current_frame.InputFile)];
                if (input_file != null and !input_file.?.Eof) {
                    cmd_success = false;
                }
            }
            if (rept == .LeadParamMinus) {
                cmd_success = !cmd_success;
            }
        },
        .CmdEqualMark => {
            var request: types.TParObject = .{};
            if (try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                if (tpar_ops.TparToMarkMessage(editor, &request)) |mark_index| {
                    if (resolveLeadMark(current_frame, mark_index)) |mark| {
                        cmd_success = switch (rept) {
                            .LeadParamNone, .LeadParamPlus => mark.Line == current_frame.Dot.?.Line and mark.Col == current_frame.Dot.?.Col,
                            .LeadParamMinus => !(mark.Line == current_frame.Dot.?.Line and mark.Col == current_frame.Dot.?.Col),
                            .LeadParamPIndef => blk: {
                                if (mark.Line == current_frame.Dot.?.Line) {
                                    break :blk current_frame.Dot.?.Col >= mark.Col;
                                }
                                break :blk line_ops.LineToNumber(current_frame.Dot.?.Line) >= line_ops.LineToNumber(mark.Line);
                            },
                            .LeadParamNIndef => blk: {
                                if (mark.Line == current_frame.Dot.?.Line) {
                                    break :blk current_frame.Dot.?.Col <= mark.Col;
                                }
                                break :blk line_ops.LineToNumber(current_frame.Dot.?.Line) <= line_ops.LineToNumber(mark.Line);
                            },
                            else => false,
                        };
                    }
                }
            }
        },
        .CmdEqualString => {
            var request: types.TParObject = .{};
            if (try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                if (request.Len == 0) {
                    request = current_frame.EqsTpar;
                    if (request.Len == 0) return false;
                } else {
                    current_frame.EqsTpar = request;
                }
                cmd_success = try eqsgetrep.EqsGetRepEqs(allocator, current_frame, rept, &request);
            }
        },
        .CmdDoLastCommand, .CmdExecuteString => {
            const cmd_frame = special_frames.Cmd orelse return false;
            const cmd_span = cmd_frame.Span orelse return false;
            if (current_frame == cmd_frame) {
                return false;
            }

            if (command == .CmdExecuteString) {
                var request: types.TParObject = .{};
                if (!try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                    return false;
                }
                if (request.Len == 0) {
                    return false;
                }
                if (!try codeCompileBuffer(editor, allocator, cmd_span, request.Str.?.Slice(1, request.Len), true)) {
                    return false;
                }
            } else if (cmd_span.Code == null) {
                if (!try CodeCompile(editor, allocator, cmd_frame, cmd_span, true)) {
                    return false;
                }
            }

            const outcome = try CodeInterpretFrame(
                editor,
                allocator,
                current_frame,
                special_frames,
                rept,
                count,
                cmd_span.Code.?,
                true,
            );
            current_frame = outcome.frame;
            cmd_success = outcome.ok;
        },
        .CmdFileExecute => {
            const cmd_frame = special_frames.Cmd orelse return false;
            const cmd_span = cmd_frame.Span orelse return false;
            if (current_frame == cmd_frame) {
                return false;
            }

            var request: types.TParObject = .{};
            if (!try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                return false;
            }
            if (request.Len == 0) {
                return false;
            }
            if (!try file_ops.LoadBufferedFileIntoFrameByName(editor, allocator, cmd_frame, request.Str.?.Slice(1, request.Len))) {
                return false;
            }
            if (!try CodeCompile(editor, allocator, current_frame, cmd_span, true)) {
                return false;
            }

            const outcome = try CodeInterpretFrame(
                editor,
                allocator,
                current_frame,
                special_frames,
                rept,
                count,
                cmd_span.Code.?,
                true,
            );
            current_frame = outcome.frame;
            cmd_success = outcome.ok;
        },
        .CmdFrameEdit => {
            var request: types.TParObject = .{};
            if (try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                const frame_name = if (request.Len == 0) "" else request.Str.?.Slice(1, request.Len);
                current_frame = (try frame_ops.FrameEdit(editor, allocator, current_frame, frame_name)) orelse return false;
                cmd_success = true;
            }
        },
        .CmdFrameKill => {
            var request: types.TParObject = .{};
            if (try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                if (request.Len == 0) {
                    return false;
                }
                cmd_success = try frame_ops.FrameKill(editor, allocator, current_frame, request.Str.?.Slice(1, request.Len));
            }
        },
        .CmdFrameParameters => {
            cmd_success = try frame_ops.FrameParameter(editor, allocator, current_frame, tparam);
        },
        .CmdFrameReturn => {
            var iteration: isize = 1;
            while (iteration <= count) : (iteration += 1) {
                if (current_frame.ReturnFrame == null) {
                    current_frame = old_frame;
                    return false;
                }
                current_frame = current_frame.ReturnFrame.?;
            }
            cmd_success = true;
        },
        .CmdGet => {
            var request: types.TParObject = .{};
            if (try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                if (request.Len == 0) {
                    request = current_frame.GetTpar;
                    if (request.Len == 0) return false;
                } else {
                    current_frame.GetTpar = request;
                }
                cmd_success = try eqsgetrep.EqsGetRepGet(allocator, current_frame, count, &request, true);
            }
        },
        .CmdHelp => {
            var request: types.TParObject = .{};
            if (try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                const topic = if (request.Len == 0) "" else request.Str.?.Slice(1, request.Len);
                if (editor.LudwigMode == .LudwigScreen) {
                    cmd_success = try help_ops.HelpInteractive(editor, allocator, topic);
                } else {
                    const oops = special_frames.Oops orelse return false;
                    cmd_success = try help_ops.HelpCommand(editor, allocator, oops, topic);
                }
            }
        },
        .CmdJump => {
            cmd_success = try executeJump(allocator, current_frame, rept, count, the_mark);
        },
        .CmdInsertChar => {
            cmd_success = try executeInsertChar(editor, allocator, current_frame, rept, count);
        },
        .CmdInsertLine => {
            if (count != 0) {
                const abs_count: isize = if (count < 0) -count else count;
                const range = try line_ops.LinesCreate(allocator, @intCast(abs_count));
                try line_ops.LinesInject(allocator, range.first, range.last, current_frame.Dot.?.Line);
                if (count > 0) {
                    try mark_ops.MarkCreate(allocator, current_frame.Dot.?.Line, current_frame.Dot.?.Col, &current_frame.Marks[types.MarkEquals]);
                    try mark_ops.MarkCreate(allocator, range.first, current_frame.Dot.?.Col, &current_frame.Dot);
                } else {
                    try mark_ops.MarkCreate(allocator, range.first, current_frame.Dot.?.Col, &current_frame.Marks[types.MarkEquals]);
                }
                try markModifiedAtDot(allocator, current_frame);
            } else {
                try mark_ops.MarkCreate(allocator, current_frame.Dot.?.Line, current_frame.Dot.?.Col, &current_frame.Marks[types.MarkEquals]);
            }
            cmd_success = true;
        },
        .CmdInsertMode => {
            editor.EditMode = .ModeInsert;
            cmd_success = true;
        },
        .CmdInsertInvisible => {
            cmd_success = false;
        },
        .CmdInsertText => {
            if (editor.FileData.OldCmds and !from_span) {
                if (rept == .LeadParamNone) {
                    editor.EditMode = .ModeInsert;
                    cmd_success = true;
                } else {
                    return false;
                }
            } else {
                var request: types.TParObject = .{};
                if (try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                    if (request.Con == null) {
                        cmd_success = try text.TextInsert(allocator, true, count, request.Str.?, request.Len, current_frame.Dot.?);
                    } else {
                        var iteration: isize = 0;
                        cmd_success = true;
                        while (iteration < count) : (iteration += 1) {
                            if (!try text.TextInsertTpar(allocator, &request, current_frame.Dot.?, &current_frame.Marks[types.MarkEquals])) {
                                cmd_success = false;
                                break;
                            }
                        }
                    }
                    if (cmd_success and count * request.Len != 0) {
                        try markModifiedAtDot(allocator, current_frame);
                    }
                }
            }
        },
        .CmdLineCentre => {
            cmd_success = try word.WordCentre(allocator, current_frame, rept, count);
        },
        .CmdLineFill => {
            cmd_success = try word.WordFill(allocator, current_frame, rept, count);
        },
        .CmdLineJustify => {
            cmd_success = try word.WordJustify(allocator, current_frame, rept, count);
        },
        .CmdLineLeft => {
            cmd_success = try word.WordLeft(allocator, current_frame, rept, count);
        },
        .CmdLineRight => {
            cmd_success = try word.WordRight(allocator, current_frame, rept, count);
        },
        .CmdLineSquash => {
            cmd_success = try word.WordSqueeze(allocator, current_frame, rept, count);
        },
        .CmdMark => {
            const abs_count: isize = if (count < 0) -count else count;
            if (abs_count == 0 or abs_count > types.MaxUserMarkNumber) {
                emitBatchMessage(editor, "Illegal mark number.");
                return false;
            }
            if (count < 0) {
                mark_ops.MarkDestroy(allocator, &current_frame.Marks[@intCast(-count)]);
            } else {
                try mark_ops.MarkCreate(allocator, current_frame.Dot.?.Line, current_frame.Dot.?.Col, &current_frame.Marks[@intCast(count)]);
            }
            cmd_success = true;
        },
        .CmdReplace => {
            var request1: types.TParObject = .{};
            var request2: types.TParObject = .{};
            if (try tpar_ops.TparGet2(allocator, editor, current_frame, tparam, command, &request1, &request2)) {
                if (request1.Len == 0) {
                    if (current_frame.Rep1Tpar.Len == 0) return false;
                } else {
                    current_frame.Rep1Tpar = request1;
                    current_frame.Rep2Tpar = request2;
                }
                cmd_success = try eqsgetrep.EqsGetRepRep(
                    allocator,
                    current_frame,
                    rept,
                    count,
                    &current_frame.Rep1Tpar,
                    &current_frame.Rep2Tpar,
                    true,
                );
            }
        },
        .CmdRubout => {
            cmd_success = try executeRubout(editor, allocator, current_frame, rept, count, from_span);
        },
        .CmdSetMarginLeft => {
            if (rept == .LeadParamMinus) {
                current_frame.MarginLeft = editor.InitialMarginLeft;
                cmd_success = true;
            } else if (current_frame.Dot.?.Col < current_frame.MarginRight) {
                current_frame.MarginLeft = current_frame.Dot.?.Col;
                cmd_success = true;
            }
        },
        .CmdSetMarginRight => {
            if (rept == .LeadParamMinus) {
                current_frame.MarginRight = editor.InitialMarginRight;
                cmd_success = true;
            } else if (current_frame.Dot.?.Col > current_frame.MarginLeft) {
                current_frame.MarginRight = current_frame.Dot.?.Col;
                cmd_success = true;
            }
        },
        .CmdSpanIndex => {
            const oops = special_frames.Oops orelse return false;
            cmd_success = try span_ops.SpanIndex(editor, allocator, oops);
        },
        .CmdSpanCompile,
        .CmdSpanCopy,
        .CmdSpanDefine,
        .CmdSpanExecute,
        .CmdSpanExecuteNoRecompile,
        .CmdSpanAssign,
        .CmdSpanJump,
        .CmdSpanTransfer,
        => {
            if (command == .CmdSpanAssign) {
                var request1: types.TParObject = .{};
                var request2: types.TParObject = .{};
                if (!try tpar_ops.TparGet2(allocator, editor, current_frame, tparam, command, &request1, &request2)) {
                    return false;
                }
                if (request1.Len == 0) {
                    return false;
                }
                const oops_frame = special_frames.Oops orelse return false;
                const oops_span = oops_frame.Span orelse return false;
                const heap_frame = special_frames.Heap orelse return false;
                const heap_span = heap_frame.Span orelse return false;
                const span_name = request1.Str.?.Slice(1, request1.Len);

                var span_ptr = try findSpanByName(editor, allocator, span_name);
                if (span_ptr) |existing| {
                    if (oops_span == existing) {
                        if (!try text.TextRemove(allocator, oops_span.MarkOne.?, oops_span.MarkTwo.?)) {
                            return false;
                        }
                    } else {
                        try mark_ops.MarkCreate(allocator, oops_frame.LastGroup.?.LastLine.?, 1, &oops_span.MarkTwo);
                        if (!try text.TextMove(
                            allocator,
                            false,
                            1,
                            existing.MarkOne.?,
                            existing.MarkTwo.?,
                            oops_span.MarkTwo.?,
                            &oops_frame.Marks[types.MarkEquals],
                            &oops_frame.Dot,
                        )) {
                            return false;
                        }
                    }
                } else {
                    try mark_ops.MarkCreate(allocator, heap_frame.LastGroup.?.LastLine.?, 1, &heap_span.MarkTwo);
                    if (!try createNamedSpan(editor, allocator, span_name, heap_span.MarkTwo.?, heap_span.MarkTwo.?)) {
                        return false;
                    }
                    span_ptr = (try findSpanByName(editor, allocator, span_name)) orelse return false;
                }

                if (!try text.TextInsertTpar(allocator, &request2, span_ptr.?.MarkTwo.?, &span_ptr.?.MarkOne)) {
                    return false;
                }
                const span_frame = span_ptr.?.MarkTwo.?.Line.Group.?.Frame;
                span_frame.TextModified = true;
                try mark_ops.MarkCreate(
                    allocator,
                    span_ptr.?.MarkTwo.?.Line,
                    span_ptr.?.MarkTwo.?.Col,
                    &span_frame.Marks[types.MarkModified],
                );
                cmd_success = true;
            } else {
                var request: types.TParObject = .{};
                if (try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                    if (request.Len == 0) {
                        return false;
                    }
                    const span_name = request.Str.?.Slice(1, request.Len);
                    switch (command) {
                        .CmdSpanDefine => {
                            if (rept == .LeadParamMinus) {
                                var span_ptr = try findSpanByName(editor, allocator, span_name);
                                if (span_ptr == null) {
                                    emitBatchMessage(editor, "No such span.");
                                    return false;
                                }
                                cmd_success = destroyNamedSpan(editor, allocator, &span_ptr);
                            } else {
                                const span_rept = switch (rept) {
                                    .LeadParamNone, .LeadParamPlus, .LeadParamPInt => types.LeadParam.LeadParamMarker,
                                    else => rept,
                                };
                                const span_count = if (rept == .LeadParamNone or rept == .LeadParamPlus) @as(isize, 1) else count;
                                if (span_rept == .LeadParamMarker and (span_count < 0 or span_count > types.MaxMarkNumber)) {
                                    emitBatchMessage(editor, "Illegal mark number.");
                                    return false;
                                }
                                const span_mark = if (span_rept == .LeadParamMarker) resolveLeadMark(current_frame, span_count) else null;
                                if (span_mark == null) {
                                    emitBatchMessage(editor, "Mark Not Defined.");
                                    return false;
                                }
                                cmd_success = try createNamedSpan(editor, allocator, span_name, span_mark.?, current_frame.Dot.?);
                            }
                        },
                        .CmdSpanJump => {
                            const span_ptr = (try findSpanByNameOrMessage(editor, allocator, span_name)) orelse return false;
                            const target = if (rept == .LeadParamMinus) span_ptr.MarkOne.? else span_ptr.MarkTwo.?;
                            if (target.Line.Group.?.Frame == current_frame) {
                                try mark_ops.MarkCreate(allocator, current_frame.Dot.?.Line, current_frame.Dot.?.Col, &current_frame.Marks[types.MarkEquals]);
                                try mark_ops.MarkCreate(allocator, target.Line, target.Col, &current_frame.Dot);
                                cmd_success = true;
                            } else {
                                const target_frame = target.Line.Group.?.Frame;
                                current_frame = (try frame_ops.FrameEdit(editor, allocator, current_frame, target_frame.Span.?.Name)) orelse return false;
                                mark_ops.MarkDestroy(allocator, &target_frame.Marks[types.MarkEquals]);
                                try mark_ops.MarkCreate(allocator, target.Line, target.Col, &target_frame.Dot);
                                cmd_success = true;
                            }
                        },
                        .CmdSpanCopy, .CmdSpanTransfer => {
                            const span_ptr = (try findSpanByNameOrMessage(editor, allocator, span_name)) orelse return false;
                            cmd_success = try text.TextMove(
                                allocator,
                                command == .CmdSpanCopy,
                                count,
                                span_ptr.MarkOne.?,
                                span_ptr.MarkTwo.?,
                                current_frame.Dot.?,
                                &current_frame.Marks[types.MarkEquals],
                                &current_frame.Dot,
                            );
                            if (command == .CmdSpanTransfer and span_ptr.Frame == null and cmd_success) {
                                try mark_ops.MarkCreate(
                                    allocator,
                                    current_frame.Marks[types.MarkEquals].?.Line,
                                    current_frame.Marks[types.MarkEquals].?.Col,
                                    &span_ptr.MarkOne,
                                );
                                try mark_ops.MarkCreate(
                                    allocator,
                                    current_frame.Dot.?.Line,
                                    current_frame.Dot.?.Col,
                                    &span_ptr.MarkTwo,
                                );
                            }
                        },
                        .CmdSpanCompile, .CmdSpanExecute, .CmdSpanExecuteNoRecompile => {
                            const span_ptr = (try findSpanByNameOrMessage(editor, allocator, span_name)) orelse return false;
                            if (span_ptr.Code == null or command != .CmdSpanExecuteNoRecompile) {
                                if (!try CodeCompile(editor, allocator, current_frame, span_ptr, true)) {
                                    return false;
                                }
                            }
                            if (command == .CmdSpanCompile) {
                                cmd_success = true;
                            } else {
                                const outcome = try CodeInterpretFrame(
                                    editor,
                                    allocator,
                                    current_frame,
                                    special_frames,
                                    rept,
                                    count,
                                    span_ptr.Code.?,
                                    true,
                                );
                                current_frame = outcome.frame;
                                cmd_success = outcome.ok;
                            }
                        },
                        else => unreachable,
                    }
                }
            }
        },
        .CmdOvertypeMode => {
            editor.EditMode = .ModeOvertype;
            cmd_success = true;
        },
        .CmdOvertypeText => {
            if (editor.FileData.OldCmds and !from_span) {
                if (rept == .LeadParamNone) {
                    editor.EditMode = .ModeOvertype;
                    cmd_success = true;
                } else {
                    return false;
                }
            } else {
                var request: types.TParObject = .{};
                if (try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                    cmd_success = try text.TextOvertype(allocator, true, count, request.Str.?, request.Len, current_frame.Dot.?);
                    if (cmd_success and count * request.Len != 0) {
                        try markModifiedAtDot(allocator, current_frame);
                    }
                }
            }
        },
        .CmdPositionColumn => {
            if (count > types.MaxStrLen) {
                return false;
            }
            current_frame.Dot.?.Col = count;
            cmd_success = true;
        },
        .CmdPositionLine => {
            const new_line = line_ops.LineFromNumber(current_frame, count) orelse return false;
            try mark_ops.MarkCreate(allocator, current_frame.Dot.?.Line, current_frame.Dot.?.Col, &current_frame.Marks[types.MarkEquals]);
            try mark_ops.MarkCreate(allocator, new_line, 1, &current_frame.Dot);
            cmd_success = true;
        },
        .CmdOpSysCommand => {
            cmd_success = try executeOpsysCommand(editor, allocator, current_frame, tparam);
        },
        .CmdQuit => {
            if (editor.LudwigMode != .LudwigBatch) {
                editor.LudwigAborted = false;
                editor.QuitRequested = true;
                cmd_success = true;
            } else {
                editor.LudwigAborted = false;
                if (try file_ops.QuitCloseFiles(editor, allocator)) {
                    editor.Hangup = true;
                    editor.QuitRequested = true;
                    cmd_success = true;
                } else {
                    cmd_success = false;
                }
            }
        },
        .CmdSplitLine => {
            if (current_frame.Dot.?.Line.FLink == null) {
                try text.TextRealizeNull(allocator, current_frame.Dot.?.Line);
            }
            cmd_success = try text.TextSplitLine(allocator, current_frame.Dot.?, 0, &current_frame.Marks[types.MarkEquals]);
        },
        .CmdSwapLine => {
            cmd_success = try swap.SwapLine(allocator, current_frame, rept, count);
        },
        .CmdUserCommandIntroducer => {
            if (editor.LudwigMode != .LudwigScreen) {
                return false;
            }
            cmd_success = try user_ops.UserCommandIntroducer(editor, allocator, current_frame);
        },
        .CmdUserKey => {
            if (editor.LudwigMode != .LudwigScreen) {
                return false;
            }
            var request: types.TParObject = .{};
            var request2: types.TParObject = .{};
            if (try tpar_ops.TparGet2(allocator, editor, current_frame, tparam, command, &request, &request2)) {
                if (request.Len == 0) {
                    return false;
                }
                const key_code = user_ops.ResolveUserKeyCode(editor, &request) orelse return false;
                const heap_frame = special_frames.Heap orelse return false;
                const heap_span = heap_frame.Span orelse return false;
                try mark_ops.MarkCreate(allocator, heap_frame.LastGroup.?.LastLine.?, 1, &heap_span.MarkTwo);
                if (!try createNamedSpan(editor, allocator, types.BlankFrameName, heap_span.MarkTwo.?, heap_span.MarkTwo.?)) {
                    return false;
                }

                var key_span = (try findSpanByName(editor, allocator, types.BlankFrameName)) orelse return false;
                defer {
                    var key_span_slot: ?*types.SpanObject = key_span;
                    _ = destroyNamedSpan(editor, allocator, &key_span_slot);
                }

                if (!try text.TextInsertTpar(allocator, &request2, key_span.MarkTwo.?, &key_span.MarkOne)) {
                    return false;
                }
                if (!try CodeCompile(editor, allocator, current_frame, key_span, true)) {
                    return false;
                }
                cmd_success = user_ops.BindCompiledKey(editor, key_code, key_span);
            }
        },
        .CmdUserParent, .CmdUserSubprocess => {
            cmd_success = false;
        },
        .CmdUserUndo => {
            cmd_success = user_ops.UserUndo();
        },
        .CmdWordAdvance => {
            cmd_success = if (editor.FileData.OldCmds)
                try word.WordAdvanceWord(allocator, current_frame, rept, count)
            else
                try newword.NewwordAdvanceWord(allocator, current_frame, rept, count);
        },
        .CmdWordDelete => {
            const oops = special_frames.Oops orelse return false;
            cmd_success = if (editor.FileData.OldCmds)
                try word.WordDeleteWord(allocator, current_frame, oops, rept, count)
            else
                try newword.NewwordDeleteWord(allocator, current_frame, oops, rept, count);
        },
        .CmdAdvanceParagraph => {
            cmd_success = try newword.NewwordAdvanceParagraph(allocator, current_frame, rept, count);
        },
        .CmdDeleteParagraph => {
            const oops = special_frames.Oops orelse return false;
            cmd_success = try newword.NewwordDeleteParagraph(allocator, current_frame, oops, rept, count);
        },
        .CmdCommand => {
            if (rept == .LeadParamMinus) {
                if (editor.EditMode != .ModeCommand) {
                    editor.PreviousMode = editor.EditMode;
                    editor.EditMode = .ModeCommand;
                    cmd_success = true;
                } else {
                    return false;
                }
            } else {
                if (editor.EditMode == .ModeCommand) {
                    editor.EditMode = editor.PreviousMode;
                    cmd_success = true;
                } else {
                    return false;
                }
            }
        },
        .CmdWindowBackward,
        .CmdWindowEnd,
        .CmdWindowForward,
        .CmdWindowLeft,
        .CmdWindowMiddle,
        .CmdWindowNew,
        .CmdWindowRight,
        .CmdWindowScroll,
        .CmdWindowSetHeight,
        .CmdWindowTop,
        .CmdWindowUpdate,
        .CmdResizeWindow,
        => {
            cmd_success = try window_ops.WindowCommand(editor, allocator, current_frame, command, rept, count, from_span);
        },
        .CmdFileRead => {
            cmd_success = try file_ops.FileReadCommand(editor, allocator, current_frame, rept, count);
        },
        .CmdFileWrite => {
            cmd_success = try file_ops.FileWriteCommand(editor, allocator, current_frame, rept, count, the_mark);
        },
        .CmdFileRewind => {
            cmd_success = try file_ops.FileRewindCommand(editor, allocator, current_frame);
        },
        .CmdFileGlobalRewind => {
            cmd_success = try file_ops.FileGlobalRewindCommand(editor, allocator);
        },
        .CmdPage => {
            cmd_success = try file_ops.FilePage(editor, allocator, current_frame);
        },
        .CmdFileSave => {
            cmd_success = try file_ops.FileSaveCommand(editor, allocator, current_frame);
        },
        .CmdFileKill => {
            cmd_success = try file_ops.FileKillCommand(editor, allocator, current_frame);
        },
        .CmdFileGlobalKill => {
            cmd_success = try file_ops.FileGlobalKillCommand(editor, allocator);
        },
        .CmdFileInput,
        .CmdFileOutput,
        .CmdFileEdit,
        .CmdFileGlobalInput,
        .CmdFileGlobalOutput,
        => {
            if (rept == .LeadParamMinus) {
                cmd_success = try file_ops.FileCloseCommand(editor, allocator, current_frame, command);
            } else {
                var request: types.TParObject = .{};
                if (!try tpar_ops.TparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                    return false;
                }
                const file_name = if (request.Len == 0) "" else request.Str.?.Slice(1, request.Len);
                cmd_success = try file_ops.FileOpenCommand(editor, allocator, current_frame, command, file_name);
            }
        },
        .CmdFileTable => {
            const oops = special_frames.Oops orelse return false;
            cmd_success = try file_ops.FileTable(editor, allocator, oops);
        },
        .CmdValidate => {
            cmd_success = validate_ops.ValidateCommand(editor, current_frame, special_frames);
        },
        .CmdBlockDefine, .CmdBlockTransfer, .CmdBlockCopy => {
            cmd_success = false;
        },
        .CmdNoop => {
            cmd_success = true;
        },
        else => {
            return false;
        },
    }

    if (cmd_success) {
        switch (editor.CmdAttrib[cmdIndex(command)].EqAction) {
            .EqOld => try mark_ops.MarkCreate(allocator, old_dot.Line, old_dot.Col, &old_frame.Marks[types.MarkEquals]),
            .EqDel => mark_ops.MarkDestroy(allocator, &old_frame.Marks[types.MarkEquals]),
            .EqNil => {},
        }
    }
    return cmd_success;
}

pub fn ExecuteSingle(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame_slot: **types.FrameObject,
    special_frames: *types.SpecialFrames,
    command: types.Commands,
    rept: types.LeadParam,
    count: isize,
    tparam: ?*types.TParObject,
    from_span: bool,
) !bool {
    return Execute(editor, allocator, frame_slot, special_frames, command, rept, count, tparam, from_span);
}

pub fn CodeInterpretFrame(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    special_frames: *types.SpecialFrames,
    rept: types.LeadParam,
    count: isize,
    code_head: *types.CodeHeader,
    from_span: bool,
) anyerror!InterpretResult {
    var labels: [max_level + 1]Labels = [_]Labels{.{}} ** (max_level + 1);
    var code_ref: ?*types.CodeHeader = code_head;
    code_head.Ref += 1;
    defer CodeDiscard(editor, &code_ref);
    const top_level = editor.ExecLevel == 0;
    if (top_level) {
        editor.QuitRequested = false;
    }
    editor.ExecLevel += 1;
    defer editor.ExecLevel -= 1;

    var current_frame = frame;
    var outer_count = count;
    var verify_always = editor.InitialVerify;
    if (rept == .LeadParamPIndef) {
        outer_count = -1;
    }

    var interp_status: InterpStatus = .success;
    var span_mode = from_span;
    while (outer_count != 0 and interp_status == .success) {
        outer_count -= 1;
        var level: usize = 1;
        labels[1] = .{};
        var pc: isize = 1;

        while (pc != 0) {
            if (pc > code_head.Len) {
                return .{ .frame = current_frame, .ok = false };
            }

            interp_status = .success;
            const cc = &editor.CompilerCode[@intCast(code_head.Code - 1 + pc)];
            const curr_lbl = cc.Lbl;
            const curr_op = cc.Op;
            const curr_rep = cc.Rep;
            const curr_cnt = cc.Cnt;
            const curr_tpar = cc.Tpar;
            const curr_code = cc.Code;
            pc += 1;

            if (isInterpCmd(curr_op)) {
                switch (curr_op) {
                    .CmdPcJump => pc = curr_lbl,
                    .CmdExitTo => {
                        span_mode = true;
                        level += 1;
                        labels[level] = .{ .exitLabel = curr_lbl };
                    },
                    .CmdFailTo => labels[level].failLabel = curr_lbl,
                    .CmdIterate => {
                        if (labels[level].count == curr_cnt) {
                            pc = labels[level].exitLabel;
                            level -= 1;
                        } else {
                            labels[level].count += 1;
                        }
                    },
                    .CmdExitSuccess => {
                        var effective = curr_cnt;
                        if (curr_rep == .LeadParamPIndef) effective = @intCast(level);
                        if (effective > 0) {
                            if (effective >= level) {
                                level = 0;
                            } else {
                                level -= @intCast(effective);
                            }
                        }
                        pc = labels[level + 1].exitLabel;
                    },
                    .CmdExitFail => {
                        interp_status = .failure;
                        var effective = curr_cnt;
                        if (curr_rep == .LeadParamPIndef) effective = @intCast(level);
                        if (effective > 0) {
                            if (effective >= level) {
                                level = 0;
                            } else {
                                level -= @intCast(effective);
                            }
                        }
                        pc = labels[level + 1].failLabel;
                    },
                    .CmdExitAbort => {
                        editor.ExitAbort = true;
                        interp_status = .fail_forever;
                        pc = 0;
                    },
                    .CmdExtended => {
                        if (curr_code == null) return .{ .frame = current_frame, .ok = false };
                        const outcome = try CodeInterpretFrame(editor, allocator, current_frame, special_frames, curr_rep, curr_cnt, curr_code.?, true);
                        current_frame = outcome.frame;
                        if (!outcome.ok) {
                            interp_status = .failure;
                            pc = curr_lbl;
                        }
                    },
                    .CmdVerify => {
                        if (!verify_always[@intCast(curr_cnt)]) {
                            if (editor.LudwigMode == .LudwigBatch) {
                                editor.ExitAbort = true;
                                interp_status = .fail_forever;
                                pc = 0;
                            } else blk: {
                                var request: types.TParObject = .{};
                                if (!try tpar_ops.TparGet1(allocator, editor, current_frame, curr_tpar, .CmdVerify, &request)) {
                                    break :blk;
                                }
                                if (request.Len == 0) {
                                    request = current_frame.VerifyTpar;
                                    if (request.Len == 0) {
                                        return .{ .frame = current_frame, .ok = false };
                                    }
                                } else {
                                    current_frame.VerifyTpar = request;
                                }

                                switch (request.Str.?.Get(1)) {
                                    'Y' => {},
                                    'A' => verify_always[@intCast(curr_cnt)] = true,
                                    'Q' => {
                                        editor.ExitAbort = true;
                                        interp_status = .fail_forever;
                                        pc = 0;
                                    },
                                    else => {
                                        interp_status = .failure;
                                        pc = curr_lbl;
                                    },
                                }
                            }
                        }
                    },
                    .CmdNoop => return .{ .frame = current_frame, .ok = false },
                    else => unreachable,
                }
            } else {
                const ok = try Execute(editor, allocator, &current_frame, special_frames, curr_op, curr_rep, curr_cnt, curr_tpar, span_mode);
                if (!ok) {
                    interp_status = .failure;
                    pc = curr_lbl;
                }
                if (editor.ExitAbort) {
                    interp_status = .fail_forever;
                    pc = 0;
                }
            }

            if (editor.QuitRequested) {
                interp_status = .success;
                pc = 0;
            }
            if (editor.TtControlC) {
                interp_status = .fail_forever;
                pc = 0;
            }
            if (interp_status == .failure) {
                while (pc == 0 and level >= 1) {
                    pc = labels[level].failLabel;
                    if (level == 0) break;
                    level -= 1;
                }
            }
        }
    }

    return .{
        .frame = current_frame,
        .ok = interp_status == .success,
    };
}

pub fn CodeInterpret(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    special_frames: *types.SpecialFrames,
    rept: types.LeadParam,
    count: isize,
    code_head: *types.CodeHeader,
    from_span: bool,
) anyerror!bool {
    return (try CodeInterpretFrame(editor, allocator, frame, special_frames, rept, count, code_head, from_span)).ok;
}

fn makeCommandSpan(
    allocator: std.mem.Allocator,
    contents: []const []const u8,
) !struct {
    fixture: line_ops.FrameFixture,
    span: *types.SpanObject,
} {
    const fixture = try line_ops.createContentFrame(allocator, contents);
    var mark_one: ?*types.MarkObject = null;
    var mark_two: ?*types.MarkObject = null;
    try mark_ops.MarkCreate(allocator, fixture.content_lines[0], 1, &mark_one);
    const last = fixture.content_lines[contents.len - 1];
    try mark_ops.MarkCreate(allocator, last, last.Used + 1, &mark_two);
    const span = try allocator.create(types.SpanObject);
    span.* = .{
        .Name = "CMD",
        .MarkOne = mark_one,
        .MarkTwo = mark_two,
    };
    return .{
        .fixture = fixture,
        .span = span,
    };
}

fn makeSpecialFrame(
    allocator: std.mem.Allocator,
    name: []const u8,
    contents: []const []const u8,
) !line_ops.FrameFixture {
    const fixture = try line_ops.createContentFrame(allocator, contents);
    const span = try allocator.create(types.SpanObject);
    span.* = .{
        .Name = name,
        .Frame = fixture.frame,
    };
    fixture.frame.Span = span;
    try mark_ops.MarkCreate(allocator, fixture.frame.FirstGroup.?.FirstLine.?, 1, &span.MarkOne);
    try mark_ops.MarkCreate(allocator, fixture.frame.LastGroup.?.LastLine.?, 1, &span.MarkTwo);
    return fixture;
}

fn expectFrameLines(frame: *types.FrameObject, expected: []const []const u8) !void {
    const sentinel = frame.LastGroup.?.LastLine.?;
    var line = frame.FirstGroup.?.FirstLine.?;
    for (expected) |content| {
        try std.testing.expect(line != sentinel);
        try std.testing.expectEqualStrings(content, line_ops.getLineContent(line));
        line = line.FLink.?;
    }
    try std.testing.expect(line == sentinel);
}

fn makeBufferedFile(
    allocator: std.mem.Allocator,
    contents: []const []const u8,
    output_flag: bool,
) !*types.FileObject {
    return file_ops.MakeBufferedFile(allocator, contents, output_flag);
}

fn tmpFilePath(allocator: std.mem.Allocator, tmp_dir: *std.testing.TmpDir, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/{s}", .{ tmp_dir.sub_path, name });
}

fn writeTmpFile(
    allocator: std.mem.Allocator,
    tmp_dir: *std.testing.TmpDir,
    name: []const u8,
    contents: []const u8,
) ![]const u8 {
    try tmp_dir.dir.writeFile(.{
        .sub_path = name,
        .data = contents,
    });
    return tmpFilePath(allocator, tmp_dir, name);
}

fn commandWithPath(
    allocator: std.mem.Allocator,
    prefix: []const u8,
    path: []const u8,
    suffix: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}|{s}|{s}", .{ prefix, path, suffix });
}

test "code compile string supports immediate commands and prompt placeholders" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
    });
    var special_frames: types.SpecialFrames = .{};

    var advance_span = types.SpanObject{ .Name = "ADV" };
    try std.testing.expect(try CodeCompileString(&editor, allocator, &advance_span, "A"));
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, advance_span.Code.?, false));
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[1]);

    var mode_span = types.SpanObject{ .Name = "MODE" };
    editor.EditMode = .ModeInsert;
    try std.testing.expect(try CodeCompileString(&editor, allocator, &mode_span, "O"));
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, mode_span.Code.?, false));
    try std.testing.expectEqual(types.ModeType.ModeOvertype, editor.EditMode);

    var prompt_span = types.SpanObject{ .Name = "PROMPT" };
    try std.testing.expect(try CodeCompileString(&editor, allocator, &prompt_span, "R"));
    const compiled = &editor.CompilerCode[@intCast(prompt_span.Code.?.Code)];
    try std.testing.expectEqual(types.Commands.CmdReplace, compiled.Op);
    try std.testing.expect(compiled.Tpar != null);
    try std.testing.expectEqual(types.TpdPrompt, compiled.Tpar.?.Dlm);
    try std.testing.expect(compiled.Tpar.?.Nxt != null);
    try std.testing.expectEqual(types.TpdPrompt, compiled.Tpar.?.Nxt.?.Dlm);
}

test "code compile can consume queued immediate input" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
    });
    var special_frames: types.SpecialFrames = .{};

    var immediate_span = types.SpanObject{ .Name = "IMM" };
    try editor.setImmediateInput("A");
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, &immediate_span, false));
    try std.testing.expect(editor.ImmediateInput == null);
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, immediate_span.Code.?, false));
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[1]);
}

test "code compile can consume live interactive input" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.LudwigMode = .LudwigScreen;

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});

    var live_span = types.SpanObject{ .Name = "LIVE" };
    interactive_io.testing.installInput("A");
    defer interactive_io.testing.clearInput();

    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, &live_span, false));
    const compiled = &editor.CompilerCode[@intCast(live_span.Code.?.Code)];
    try std.testing.expectEqual(types.Commands.CmdAdvance, compiled.Op);
}

test "code compile live input accepts special keys as commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.LudwigMode = .LudwigScreen;
    try user_ops.UserKeyInitialize(&editor, allocator);

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});

    var live_span = types.SpanObject{ .Name = "LIVE" };
    interactive_io.testing.installInput("\x1b[6~");
    defer interactive_io.testing.clearInput();

    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, &live_span, false));
    const compiled = &editor.CompilerCode[@intCast(live_span.Code.?.Code)];
    try std.testing.expectEqual(types.Commands.CmdWindowForward, compiled.Op);
}

test "code compile live input supports prefix commands with prompted parameters" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.LudwigMode = .LudwigScreen;

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});
    var live_span = types.SpanObject{ .Name = "LIVE" };
    interactive_io.testing.installInput("EPc=/\r");
    defer interactive_io.testing.clearInput();

    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, &live_span, false));
    const compiled = &editor.CompilerCode[@intCast(live_span.Code.?.Code)];
    try std.testing.expectEqual(types.Commands.CmdFrameParameters, compiled.Op);
    try std.testing.expect(compiled.Tpar != null);
    try std.testing.expectEqual(types.TpdPrompt, compiled.Tpar.?.Dlm);
    try std.testing.expectEqual(@as(?u8, 'c'), try interactive_io.readKey());
}

test "code compile false preserves immediate prompt placeholders" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});
    var prompt_span = types.SpanObject{ .Name = "PROMPT" };
    try editor.setImmediateInput("R");
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, &prompt_span, false));
    const compiled = &editor.CompilerCode[@intCast(prompt_span.Code.?.Code)];
    try std.testing.expectEqual(types.Commands.CmdReplace, compiled.Op);
    try std.testing.expect(compiled.Tpar != null);
    try std.testing.expectEqual(types.TpdPrompt, compiled.Tpar.?.Dlm);
    try std.testing.expect(compiled.Tpar.?.Nxt != null);
    try std.testing.expectEqual(types.TpdPrompt, compiled.Tpar.?.Nxt.?.Dlm);
}

test "code interpreter can insert spaces with insert char command" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"ab"});
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 2, &target.frame.Dot);

    const command = try makeCommandSpan(allocator, &[_][]const u8{"2C"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqualStrings("a  b", line_ops.getLineContent(target.content_lines[0]));
    try std.testing.expectEqual(@as(isize, 2), target.frame.Dot.?.Col);
    try std.testing.expectEqual(@as(isize, 4), target.frame.Marks[types.MarkEquals].?.Col);
}

test "code interpreter can delete a marked character range into oops" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"abcdef"});
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 5, &target.frame.Dot);
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 2, &target.frame.Marks[1]);

    const oops = try makeSpecialFrame(allocator, "OOPS", &[_][]const u8{""});
    var special_frames: types.SpecialFrames = .{
        .Oops = oops.frame,
    };

    const command = try makeCommandSpan(allocator, &[_][]const u8{"@1D"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{"aef"});
    try std.testing.expectEqualStrings("bcd", line_ops.getLineContent(oops.frame.LastGroup.?.LastLine.?.BLink));
}

test "code interpreter can delete a line into oops" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
        "three",
    });
    try mark_ops.MarkCreate(allocator, target.content_lines[1], 2, &target.frame.Dot);

    const oops = try makeSpecialFrame(allocator, "OOPS", &[_][]const u8{""});
    var special_frames: types.SpecialFrames = .{
        .Oops = oops.frame,
    };

    const command = try makeCommandSpan(allocator, &[_][]const u8{"K"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{
        "one",
        "three",
    });
    try std.testing.expectEqualStrings("two", line_ops.getLineContent(oops.frame.LastGroup.?.LastLine.?.BLink));
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[2]);
    try std.testing.expectEqual(@as(isize, 2), target.frame.Dot.?.Col);
}

test "code interpreter can jump by character count" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"abcdef"});
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);

    const command = try makeCommandSpan(allocator, &[_][]const u8{"2J"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 3), target.frame.Dot.?.Col);
    try std.testing.expectEqual(@as(isize, 1), target.frame.Marks[types.MarkEquals].?.Col);
}

test "code interpreter can centre a line" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"cat"});
    target.frame.MarginLeft = 1;
    target.frame.MarginRight = 10;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"YC"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqualStrings("   cat", line_ops.getLineContent(target.content_lines[0]));
}

test "code interpreter can set margins from dot" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"abcdef"});
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 3, &target.frame.Dot);

    const left_command = try makeCommandSpan(allocator, &[_][]const u8{"{"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, left_command.span, true));
    try std.testing.expect((try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, left_command.span.Code.?, true)).ok);
    try std.testing.expectEqual(@as(isize, 3), target.frame.MarginLeft);

    try mark_ops.MarkCreate(allocator, target.content_lines[0], 5, &target.frame.Dot);
    const right_command = try makeCommandSpan(allocator, &[_][]const u8{"}"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, right_command.span, true));
    try std.testing.expect((try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, right_command.span.Code.?, true)).ok);
    try std.testing.expectEqual(@as(isize, 5), target.frame.MarginRight);
}

test "code interpreter can report help topics into oops frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const current = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const oops = try makeSpecialFrame(allocator, "OOPS", &[_][]const u8{""});
    var special_frames: types.SpecialFrames = .{
        .Oops = oops.frame,
    };

    const command = try makeCommandSpan(allocator, &[_][]const u8{"H/Q/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, current.frame, command.span, true));

    const outcome = try CodeInterpretFrame(&editor, allocator, current.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(outcome.frame == current.frame);

    const first = oops.frame.FirstGroup.?.FirstLine.?;
    try std.testing.expectEqualStrings("Q       QUIT", line_ops.getLineContent(first));
    try std.testing.expectEqualStrings("=       ====", line_ops.getLineContent(first.FLink));
}

test "code interpreter can insert opsys command output into frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.loadCommandTable(false);
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"tail"});
    const command = try makeCommandSpan(allocator, &[_][]const u8{"OX|printf \"alpha\\nbeta\\n\"|"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));

    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{
        "alpha",
        "beta",
        "tail",
    });
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[0]);
    try std.testing.expectEqual(@as(isize, 1), target.frame.Dot.?.Col);
    try std.testing.expectEqualStrings("alpha", line_ops.getLineContent(target.frame.Marks[types.MarkEquals].?.Line));
}

test "code interpreter captures opsys stderr with tab expansion" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.loadCommandTable(false);
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"tail"});
    const command = try makeCommandSpan(allocator, &[_][]const u8{"OX|printf \"\\tX\\n\" >&2|"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));

    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{
        "        X",
        "tail",
    });
}

test "code compile and interpret resolve prefix equal string commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"hello world"});
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);

    const command = try makeCommandSpan(allocator, &[_][]const u8{"EQS/hello/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    var special_frames: types.SpecialFrames = .{};
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true));
    try std.testing.expectEqual(@as(isize, 6), target.frame.Marks[types.MarkEquals].?.Col);
}

test "code interpreter executes success and fail handlers" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const success_target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "hello world",
        "second",
    });
    try mark_ops.MarkCreate(allocator, success_target.content_lines[0], 1, &success_target.frame.Dot);
    const success_cmd = try makeCommandSpan(allocator, &[_][]const u8{"G/world/[A]"});
    try std.testing.expect(try CodeCompile(&editor, allocator, success_target.frame, success_cmd.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, success_target.frame, &special_frames, .LeadParamNone, 1, success_cmd.span.Code.?, true));
    try std.testing.expect(success_target.frame.Dot.?.Line == success_target.content_lines[1]);

    const fail_target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "hello world",
        "second",
    });
    try mark_ops.MarkCreate(allocator, fail_target.content_lines[0], 1, &fail_target.frame.Dot);
    const fail_cmd = try makeCommandSpan(allocator, &[_][]const u8{"G/missing/[:A]"});
    try std.testing.expect(try CodeCompile(&editor, allocator, fail_target.frame, fail_cmd.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, fail_target.frame, &special_frames, .LeadParamNone, 1, fail_cmd.span.Code.?, true));
    try std.testing.expect(fail_target.frame.Dot.?.Line == fail_target.content_lines[1]);
}

test "code interpreter executes compound loops using iterate opcodes" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
        "three",
    });
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);
    const command = try makeCommandSpan(allocator, &[_][]const u8{"2(A)"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    var special_frames: types.SpecialFrames = .{};
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true));
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[2]);
}

test "code interpreter executes compiled arrow and insert text commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "hello",
        "second",
    });
    try mark_ops.MarkCreate(allocator, target.content_lines[1], 1, &target.frame.Dot);
    const command = try makeCommandSpan(allocator, &[_][]const u8{"ZU I/abc/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    var special_frames: types.SpecialFrames = .{};
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true));
    try std.testing.expectEqualStrings("abchello", line_ops.getLineContent(target.content_lines[0]));
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[0]);
    try std.testing.expectEqual(@as(isize, 4), target.frame.Dot.?.Col);
}

test "code interpreter executes span assign with heap and oops special frames" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const current = try line_ops.createContentFrame(allocator, &[_][]const u8{"ignored"});
    const oops = try makeSpecialFrame(allocator, "OOPS", &[_][]const u8{""});
    const heap = try makeSpecialFrame(allocator, "HEAP", &[_][]const u8{""});
    var special_frames: types.SpecialFrames = .{
        .Oops = oops.frame,
        .Heap = heap.frame,
    };

    const source = try line_ops.createContentFrame(allocator, &[_][]const u8{"stale"});
    var source_mark_one: ?*types.MarkObject = null;
    var source_mark_two: ?*types.MarkObject = null;
    try mark_ops.MarkCreate(allocator, source.content_lines[0], 1, &source_mark_one);
    try mark_ops.MarkCreate(allocator, source.content_lines[0], 6, &source_mark_two);
    try std.testing.expect(try span_ops.SpanCreate(&editor, allocator, "NAME", source_mark_one.?, source_mark_two.?));

    const assign_existing = try makeCommandSpan(allocator, &[_][]const u8{"SA/NAME/new/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, current.frame, assign_existing.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, current.frame, &special_frames, .LeadParamNone, 1, assign_existing.span.Code.?, true));

    const assigned_span = (try findSpanByName(&editor, allocator, "NAME")) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("new", line_ops.getLineContent(assigned_span.MarkOne.?.Line));
    try std.testing.expectEqualStrings("stale", line_ops.getLineContent(oops.frame.LastGroup.?.LastLine.?.BLink));

    const assign_new = try makeCommandSpan(allocator, &[_][]const u8{"SA/NEW/alpha/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, current.frame, assign_new.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, current.frame, &special_frames, .LeadParamNone, 1, assign_new.span.Code.?, true));

    const new_span = (try findSpanByName(&editor, allocator, "NEW")) orelse return error.TestUnexpectedResult;
    try std.testing.expect(new_span.MarkOne.?.Line.Group.?.Frame == heap.frame);
    try std.testing.expectEqualStrings("alpha", line_ops.getLineContent(new_span.MarkOne.?.Line));
}

test "code interpreter executes span define jump and destroy commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"hello world"});
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Marks[1]);
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 6, &target.frame.Dot);

    const define_command = try makeCommandSpan(allocator, &[_][]const u8{"SD/TEST/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, define_command.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, define_command.span.Code.?, true));

    const defined_span = (try findSpanByName(&editor, allocator, "TEST")) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(isize, 1), defined_span.MarkOne.?.Col);
    try std.testing.expectEqual(@as(isize, 6), defined_span.MarkTwo.?.Col);

    try mark_ops.MarkCreate(allocator, target.content_lines[0], 11, &target.frame.Dot);
    const jump_command = try makeCommandSpan(allocator, &[_][]const u8{"-SJ/TEST/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, jump_command.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, jump_command.span.Code.?, true));
    try std.testing.expectEqual(@as(isize, 1), target.frame.Dot.?.Col);

    const destroy_command = try makeCommandSpan(allocator, &[_][]const u8{"-SD/TEST/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, destroy_command.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, destroy_command.span.Code.?, true));
    try std.testing.expect((try findSpanByName(&editor, allocator, "TEST")) == null);
}

test "code interpreter executes command strings and replays last command" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
        "three",
    });
    const cmd_frame = try makeSpecialFrame(allocator, "COMMAND", &[_][]const u8{""});
    var special_frames: types.SpecialFrames = .{
        .Cmd = cmd_frame.frame,
    };
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);

    const exec_command = try makeCommandSpan(allocator, &[_][]const u8{"^/AA/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, exec_command.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, exec_command.span.Code.?, true));
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[2]);
    try std.testing.expect(cmd_frame.frame.Span.?.Code != null);

    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);
    const repeat_command = try makeCommandSpan(allocator, &[_][]const u8{"\x07"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, repeat_command.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, repeat_command.span.Code.?, true));
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[2]);
}

test "code interpreter can edit and return frames" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const origin = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});

    const edit_command = try makeCommandSpan(allocator, &[_][]const u8{"ED/WORK/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, origin.frame, edit_command.span, true));
    const edit_outcome = try CodeInterpretFrame(&editor, allocator, origin.frame, &special_frames, .LeadParamNone, 1, edit_command.span.Code.?, true);
    try std.testing.expect(edit_outcome.ok);
    try std.testing.expect(edit_outcome.frame != origin.frame);
    try std.testing.expectEqualStrings("WORK", edit_outcome.frame.Span.?.Name);
    try std.testing.expect(edit_outcome.frame.ReturnFrame == origin.frame);

    const return_command = try makeCommandSpan(allocator, &[_][]const u8{"ER"});
    try std.testing.expect(try CodeCompile(&editor, allocator, edit_outcome.frame, return_command.span, true));
    const return_outcome = try CodeInterpretFrame(&editor, allocator, edit_outcome.frame, &special_frames, .LeadParamNone, 1, return_command.span.Code.?, true);
    try std.testing.expect(return_outcome.ok);
    try std.testing.expect(return_outcome.frame == origin.frame);
}

test "code interpreter can kill another frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const origin = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    _ = (try frame_ops.FrameEdit(&editor, allocator, origin.frame, "WORK")).?;

    const kill_command = try makeCommandSpan(allocator, &[_][]const u8{"EK/WORK/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, origin.frame, kill_command.span, true));
    const kill_outcome = try CodeInterpretFrame(&editor, allocator, origin.frame, &special_frames, .LeadParamNone, 1, kill_command.span.Code.?, true);
    try std.testing.expect(kill_outcome.ok);
    try std.testing.expect(kill_outcome.frame == origin.frame);
    try std.testing.expect((try findSpanByName(&editor, allocator, "WORK")) == null);
}

test "code interpreter can apply frame parameters" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.TerminalInfo = .{ .Width = 160, .Height = 48 };
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    const param_command = try makeCommandSpan(allocator, &[_][]const u8{"EP/K=O,H=24,W=100,O=(I,-N)/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, param_command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, param_command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(types.ModeType.ModeOvertype, editor.EditMode);
    try std.testing.expectEqual(@as(isize, 24), target.frame.ScrHeight);
    try std.testing.expectEqual(@as(isize, 100), target.frame.ScrWidth);
    try std.testing.expect(types.frameOptionsHas(target.frame.Options, .OptAutoIndent));
    try std.testing.expect(!types.frameOptionsHas(target.frame.Options, .OptNewLine));
}

test "code interpreter can validate linked frame/span state" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.TerminalInfo = .{ .Width = 160, .Height = 48 };
    const allocator = editor.allocator();

    const root_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const current = (try frame_ops.FrameEdit(&editor, allocator, root_fixture.frame, "MAIN")).?;
    const cmd = (try frame_ops.FrameEdit(&editor, allocator, current, "COMMAND")).?;
    const oops = (try frame_ops.FrameEdit(&editor, allocator, current, "OOPS")).?;
    const heap = (try frame_ops.FrameEdit(&editor, allocator, current, "HEAP")).?;
    types.frameOptionsSet(&cmd.Options, .OptSpecialFrame);
    types.frameOptionsSet(&oops.Options, .OptSpecialFrame);
    types.frameOptionsSet(&heap.Options, .OptSpecialFrame);
    var special_frames: types.SpecialFrames = .{
        .Cmd = cmd,
        .Oops = oops,
        .Heap = heap,
    };

    var span_mark_one: ?*types.MarkObject = null;
    var span_mark_two: ?*types.MarkObject = null;
    try mark_ops.MarkCreate(allocator, current.FirstGroup.?.FirstLine.?, 1, &span_mark_one);
    try mark_ops.MarkCreate(allocator, current.LastGroup.?.LastLine.?, 1, &span_mark_two);
    try std.testing.expect(try span_ops.SpanCreate(&editor, allocator, "WORK", span_mark_one.?, span_mark_two.?));

    const validate_command = try makeCommandSpan(allocator, &[_][]const u8{"~V"});
    try std.testing.expect(try CodeCompile(&editor, allocator, current, validate_command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, current, &special_frames, .LeadParamNone, 1, validate_command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(outcome.frame == current);
}

test "code interpreter can insert user command introducer in screen mode" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.LudwigMode = .LudwigScreen;
    editor.CommandIntroducer = '@';
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"ab"});
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 2, &target.frame.Dot);

    const command = try makeCommandSpan(allocator, &[_][]const u8{"UC"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqualStrings("a@b", line_ops.getLineContent(target.content_lines[0]));
}

test "code interpreter can bind simple user key commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.LudwigMode = .LudwigScreen;
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    const heap = (try frame_ops.FrameEdit(&editor, allocator, target.frame, "HEAP")).?;
    types.frameOptionsSet(&heap.Options, .OptSpecialFrame);
    var special_frames: types.SpecialFrames = .{
        .Heap = heap,
    };

    const command = try makeCommandSpan(allocator, &[_][]const u8{"UK/A/A/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(types.Commands.CmdAdvance, editor.Lookup['A'].Command);
    try std.testing.expect(editor.Lookup['A'].Code == null);
    try std.testing.expect(editor.Lookup['A'].Tpar == null);
}

test "code interpreter can bind extended user key commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.LudwigMode = .LudwigScreen;
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    const heap = (try frame_ops.FrameEdit(&editor, allocator, target.frame, "HEAP")).?;
    types.frameOptionsSet(&heap.Options, .OptSpecialFrame);
    var special_frames: types.SpecialFrames = .{
        .Heap = heap,
    };

    const command = try makeCommandSpan(allocator, &[_][]const u8{"UK/B/A A/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(types.Commands.CmdExtended, editor.Lookup['B'].Command);
    try std.testing.expect(editor.Lookup['B'].Code != null);
    try std.testing.expect(editor.Lookup['B'].Tpar == null);
}

test "code interpreter can apply window movement commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
        "three",
        "four",
        "five",
    });
    target.frame.ScrHeight = 2;
    try mark_ops.MarkCreate(allocator, target.content_lines[2], 1, &target.frame.Dot);

    const command = try makeCommandSpan(allocator, &[_][]const u8{"WF"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[4]);
    try std.testing.expect(target.frame.Marks[types.MarkEquals] != null);
    try std.testing.expect(target.frame.Marks[types.MarkEquals].?.Line == target.content_lines[2]);
}

test "code interpreter can apply window height command" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.TerminalInfo = .{ .Width = 120, .Height = 24 };
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});
    const command = try makeCommandSpan(allocator, &[_][]const u8{"WH"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 24), target.frame.ScrHeight);
}

test "code interpreter can read from the global input file buffer" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"tail"});
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);

    const input_file = try makeBufferedFile(allocator, &[_][]const u8{
        "alpha",
        "beta",
    }, false);
    input_file.Eof = true;
    editor.Files[1] = input_file;
    editor.FgiFile = 1;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"2FGR"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{
        "alpha",
        "beta",
        "tail",
    });
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[0]);
    try std.testing.expect(target.frame.Marks[types.MarkEquals] != null);
    try std.testing.expectEqualStrings("alpha", line_ops.getLineContent(target.frame.Marks[types.MarkEquals].?.Line));
}

test "code interpreter can write the selected range to the global output file buffer" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
        "three",
    });
    try mark_ops.MarkCreate(allocator, target.content_lines[1], 1, &target.frame.Dot);

    const output_file = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    editor.Files[1] = output_file;
    editor.FgoFile = 1;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FGW"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 1), output_file.LineCount);
    try std.testing.expectEqualStrings("two", line_ops.getLineContent(output_file.FirstLine));
}

test "code interpreter can page buffered file contents" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "old1",
        "old2",
    });
    try mark_ops.MarkCreate(allocator, target.content_lines[1], 1, &target.frame.Dot);

    const input_file = try makeBufferedFile(allocator, &[_][]const u8{
        "new1",
        "new2",
    }, false);
    input_file.Eof = true;
    editor.Files[1] = input_file;
    editor.FilesFrames[1] = target.frame;
    target.frame.InputFile = 1;

    const output_file = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    editor.Files[2] = output_file;
    editor.FilesFrames[2] = target.frame;
    target.frame.OutputFile = 2;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FP"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{
        "old2",
        "new1",
        "new2",
    });
    try std.testing.expectEqualStrings("old1", line_ops.getLineContent(output_file.FirstLine));
    try std.testing.expectEqualStrings("<End of File>", line_ops.getDisplayLineContent(target.frame.LastGroup.?.LastLine.?));
}

test "code interpreter can rewind attached input file buffer" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"stale"});
    try mark_ops.MarkCreate(allocator, target.frame.LastGroup.?.LastLine.?, 1, &target.frame.Dot);

    const input_file = try makeBufferedFile(allocator, &[_][]const u8{
        "alpha",
        "beta",
    }, false);
    input_file.FirstLine = null;
    input_file.LastLine = null;
    input_file.LineCount = 0;
    input_file.Eof = true;
    editor.Files[1] = input_file;
    editor.FilesFrames[1] = target.frame;
    target.frame.InputFile = 1;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FB"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{
        "alpha",
        "beta",
    });
    try std.testing.expectEqual(@as(isize, 0), input_file.LineCount);
    try std.testing.expectEqualStrings("<End of File>", line_ops.getDisplayLineContent(target.frame.LastGroup.?.LastLine.?));
}

test "code interpreter can rewind the global input file buffer" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"visible"});
    const input_file = try makeBufferedFile(allocator, &[_][]const u8{
        "alpha",
        "beta",
    }, false);
    input_file.FirstLine = null;
    input_file.LastLine = null;
    input_file.LineCount = 0;
    input_file.Eof = true;
    editor.Files[1] = input_file;
    editor.FgiFile = 1;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FGB"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 2), input_file.LineCount);
    try std.testing.expect(!input_file.Eof);
    try std.testing.expectEqualStrings("alpha", line_ops.getLineContent(input_file.FirstLine));
}

test "code interpreter can execute a buffered file into the command frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
    });
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);

    const cmd_frame = try makeSpecialFrame(allocator, "COMMAND", &[_][]const u8{"old"});
    var special_frames: types.SpecialFrames = .{
        .Cmd = cmd_frame.frame,
    };

    const source_file = try makeBufferedFile(allocator, &[_][]const u8{"A"}, false);
    source_file.Filename = "proc.lud";
    editor.Files[1] = source_file;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FX/proc.lud/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[1]);
    try expectFrameLines(cmd_frame.frame, &[_][]const u8{"A"});
}

test "code interpreter can open a disk input file into a blank frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try writeTmpFile(allocator, &tmp_dir, "input.txt", "alpha\nbeta\n");
    const root = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const target = (try frame_ops.FrameEdit(&editor, allocator, root.frame, "WORK")).?;

    const open_text = try commandWithPath(allocator, "FI", path, "");
    const command = try makeCommandSpan(allocator, &[_][]const u8{open_text});
    try std.testing.expect(try CodeCompile(&editor, allocator, target, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target, &[_][]const u8{
        "alpha",
        "beta",
    });
    try std.testing.expect(target.InputFile != 0);
    const expanded = (try sys_ops.expandFilename(allocator, path)) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(expanded, editor.Files[@intCast(target.InputFile)].?.Filename);
}

test "code interpreter can open a disk global input file and read from it" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try writeTmpFile(allocator, &tmp_dir, "global.in", "alpha\nbeta\n");
    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"tail"});
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);

    const command_text = try commandWithPath(allocator, "FGI", path, " 2FGR -FGI||");
    const command = try makeCommandSpan(allocator, &[_][]const u8{command_text});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{
        "alpha",
        "beta",
        "tail",
    });
    try std.testing.expectEqual(@as(isize, 0), editor.FgiFile);
}

test "code interpreter can edit a disk file and save on close" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try writeTmpFile(allocator, &tmp_dir, "edit.txt", "alpha\n");
    const root = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const target = (try frame_ops.FrameEdit(&editor, allocator, root.frame, "WORK")).?;

    const command_text = try commandWithPath(allocator, "FE", path, " I/edited / -FE||");
    const command = try makeCommandSpan(allocator, &[_][]const u8{command_text});
    try std.testing.expect(try CodeCompile(&editor, allocator, target, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target, &[_][]const u8{"edited alpha"});
    try std.testing.expectEqual(@as(isize, 0), target.InputFile);
    try std.testing.expectEqual(@as(isize, 0), target.OutputFile);

    const saved = try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    try std.testing.expectEqualStrings("edited alpha\n", saved);
}

test "code interpreter can write and close a disk global output file" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try tmpFilePath(allocator, &tmp_dir, "global.out");
    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"hello"});
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);

    const command_text = try commandWithPath(allocator, "FGO", path, " FGW -FGO||");
    const command = try makeCommandSpan(allocator, &[_][]const u8{command_text});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 0), editor.FgoFile);

    const saved = try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    try std.testing.expectEqualStrings("hello\n", saved);
}

test "code interpreter can quit in batch mode after closing open files" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const edit_path = try writeTmpFile(allocator, &tmp_dir, "quit-edit.txt", "alpha\n");
    const global_path = try tmpFilePath(allocator, &tmp_dir, "quit-global.out");
    const root = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const target = (try frame_ops.FrameEdit(&editor, allocator, root.frame, "WORK")).?;

    const edit_command = try commandWithPath(allocator, "FE", edit_path, " I/edited /");
    const global_command = try commandWithPath(allocator, "FGO", global_path, " FGW Q I/ignored/");
    const command_text = try std.fmt.allocPrint(allocator, "{s} {s}", .{ edit_command, global_command });
    const command = try makeCommandSpan(allocator, &[_][]const u8{command_text});
    try std.testing.expect(try CodeCompile(&editor, allocator, target, command.span, true));

    const outcome = try CodeInterpretFrame(&editor, allocator, target, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(outcome.frame == target);
    try std.testing.expect(editor.QuitRequested);
    try std.testing.expect(editor.Hangup);
    try std.testing.expectEqual(@as(isize, 0), target.InputFile);
    try std.testing.expectEqual(@as(isize, 0), target.OutputFile);
    try std.testing.expectEqual(@as(isize, 0), editor.FgoFile);
    try expectFrameLines(target, &[_][]const u8{"edited alpha"});

    const saved_edit = try std.fs.cwd().readFileAlloc(allocator, edit_path, std.math.maxInt(usize));
    try std.testing.expectEqualStrings("edited alpha\n", saved_edit);

    const saved_global = try std.fs.cwd().readFileAlloc(allocator, global_path, std.math.maxInt(usize));
    try std.testing.expectEqualStrings("edited alpha\n", saved_global);
}

test "code interpreter can execute a disk file into the command frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = try writeTmpFile(allocator, &tmp_dir, "proc.lud", "A");
    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
    });
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);

    const cmd_frame = try makeSpecialFrame(allocator, "COMMAND", &[_][]const u8{"old"});
    var special_frames: types.SpecialFrames = .{
        .Cmd = cmd_frame.frame,
    };

    const command_text = try commandWithPath(allocator, "FX", path, "");
    const command = try makeCommandSpan(allocator, &[_][]const u8{command_text});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[1]);
    try expectFrameLines(cmd_frame.frame, &[_][]const u8{"A"});
}

test "code interpreter can save to attached output file buffer" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"visible"});
    const output_file = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    editor.Files[1] = output_file;
    editor.FilesFrames[1] = target.frame;
    target.frame.OutputFile = 1;
    target.frame.TextModified = true;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FS"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(!target.frame.TextModified);
    try std.testing.expectEqual(@as(isize, 1), output_file.LineCount);
    try std.testing.expectEqualStrings("visible", line_ops.getLineContent(output_file.FirstLine));
}

test "code interpreter can kill attached output file buffer" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"visible"});
    const output_file = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    editor.Files[1] = output_file;
    editor.FilesFrames[1] = target.frame;
    target.frame.OutputFile = 1;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FK"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 0), target.frame.OutputFile);
    try std.testing.expect(editor.Files[1] == null);
}

test "code interpreter can close attached input file with empty parameter" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"visible"});
    const input_file = try makeBufferedFile(allocator, &[_][]const u8{"tail"}, false);
    editor.Files[1] = input_file;
    editor.FilesFrames[1] = target.frame;
    target.frame.InputFile = 1;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"-FI//"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 0), target.frame.InputFile);
    try std.testing.expect(editor.Files[1] == null);
    try std.testing.expectEqualStrings("<End of File>", line_ops.getDisplayLineContent(target.frame.LastGroup.?.LastLine.?));
}

test "code interpreter can table files into oops frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const root = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const current = (try frame_ops.FrameEdit(&editor, allocator, root.frame, "WORK")).?;
    const oops = (try frame_ops.FrameEdit(&editor, allocator, current, "OOPS")).?;
    types.frameOptionsSet(&oops.Options, .OptSpecialFrame);
    var special_frames: types.SpecialFrames = .{
        .Oops = oops,
    };

    const input = try allocator.create(types.FileObject);
    input.* = .{
        .Filename = "input.txt",
        .Eof = true,
    };
    editor.Files[1] = input;
    editor.FilesFrames[1] = current;
    current.InputFile = 1;
    current.TextModified = true;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FT"});
    try std.testing.expect(try CodeCompile(&editor, allocator, current, command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, current, &special_frames, .LeadParamNone, 1, command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(outcome.frame == current);
    try expectFrameLines(oops, &[_][]const u8{
        "Usage   Mod Frame  Filename",
        "------- --- ------ --------",
        "",
        "FI  EOF  * WORK   input.txt",
    });
}

test "code interpreter can index spans into oops frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"alphabet soup"});
    var mark_one: ?*types.MarkObject = null;
    var mark_two: ?*types.MarkObject = null;
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &mark_one);
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 6, &mark_two);
    try std.testing.expect(try span_ops.SpanCreate(&editor, allocator, "NAME", mark_one.?, mark_two.?));

    const oops = (try frame_ops.FrameEdit(&editor, allocator, target.frame, "OOPS")).?;
    types.frameOptionsSet(&oops.Options, .OptSpecialFrame);
    var special_frames: types.SpecialFrames = .{
        .Oops = oops,
    };

    const index_command = try makeCommandSpan(allocator, &[_][]const u8{"SI"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, index_command.span, true));
    const outcome = try CodeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, index_command.span.Code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(outcome.frame == target.frame);
    try expectFrameLines(oops, &[_][]const u8{
        "Spans",
        "=====",
        "NAME : alpha",
        "",
        "Frames",
        "======",
        "OOPS",
    });
}

test "code interpreter can jump to spans in other frames" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const origin = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    const other = (try frame_ops.FrameEdit(&editor, allocator, origin.frame, "OTHER")).?;
    try text.TextRealizeNull(allocator, other.LastGroup.?.LastLine.?);
    const content_line = other.LastGroup.?.LastLine.?.BLink.?;
    try line_ops.LineChangeLength(allocator, content_line, 4);
    try line_ops.setLineContent(content_line, "dest");
    var span_mark_one: ?*types.MarkObject = null;
    var span_mark_two: ?*types.MarkObject = null;
    try mark_ops.MarkCreate(allocator, content_line, 1, &span_mark_one);
    try mark_ops.MarkCreate(allocator, content_line, 5, &span_mark_two);
    try std.testing.expect(try span_ops.SpanCreate(&editor, allocator, "DEST", span_mark_one.?, span_mark_two.?));

    const jump_command = try makeCommandSpan(allocator, &[_][]const u8{"SJ/DEST/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, origin.frame, jump_command.span, true));
    const jump_outcome = try CodeInterpretFrame(&editor, allocator, origin.frame, &special_frames, .LeadParamNone, 1, jump_command.span.Code.?, true);
    try std.testing.expect(jump_outcome.ok);
    try std.testing.expect(jump_outcome.frame == other);
    try std.testing.expect(jump_outcome.frame.Dot.?.Line == content_line);
    try std.testing.expectEqual(@as(isize, 5), jump_outcome.frame.Dot.?.Col);
}

test "code interpreter can compile command frame for do last command" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
    });
    const cmd_frame = try makeSpecialFrame(allocator, "COMMAND", &[_][]const u8{"A"});
    var special_frames: types.SpecialFrames = .{
        .Cmd = cmd_frame.frame,
    };
    cmd_frame.frame.Span.?.Code = null;
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);

    const repeat_command = try makeCommandSpan(allocator, &[_][]const u8{"\x07"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, repeat_command.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, repeat_command.span.Code.?, true));
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[1]);
}

test "code interpreter executes named span compile and execute variants" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const command_source = try makeCommandSpan(allocator, &[_][]const u8{"A"});
    try std.testing.expect(try span_ops.SpanCreate(&editor, allocator, "CMD", command_source.span.MarkOne.?, command_source.span.MarkTwo.?));

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
        "three",
    });
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);

    const compile_command = try makeCommandSpan(allocator, &[_][]const u8{"SR/CMD/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, compile_command.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, compile_command.span.Code.?, true));
    const compiled_span = (try findSpanByName(&editor, allocator, "CMD")) orelse return error.TestUnexpectedResult;
    try std.testing.expect(compiled_span.Code != null);

    try line_ops.setLineContent(command_source.fixture.content_lines[0], "2A");
    try mark_ops.MarkCreate(allocator, compiled_span.MarkTwo.?.Line, 3, &compiled_span.MarkTwo);

    const no_recompile_command = try makeCommandSpan(allocator, &[_][]const u8{"EN/CMD/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, no_recompile_command.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, no_recompile_command.span.Code.?, true));
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[1]);

    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);
    const execute_command = try makeCommandSpan(allocator, &[_][]const u8{"EX/CMD/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, execute_command.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, execute_command.span.Code.?, true));
    try std.testing.expect(target.frame.Dot.?.Line == target.content_lines[2]);
}

test "code interpreter executes span copy and transfer commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const copy_target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "hello",
        "target",
    });
    var span_start: ?*types.MarkObject = null;
    var span_end: ?*types.MarkObject = null;
    try mark_ops.MarkCreate(allocator, copy_target.content_lines[0], 1, &span_start);
    try mark_ops.MarkCreate(allocator, copy_target.content_lines[0], 6, &span_end);
    try std.testing.expect(try span_ops.SpanCreate(&editor, allocator, "COPY", span_start.?, span_end.?));
    try mark_ops.MarkCreate(allocator, copy_target.content_lines[1], 1, &copy_target.frame.Dot);

    const copy_command = try makeCommandSpan(allocator, &[_][]const u8{"SC/COPY/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, copy_target.frame, copy_command.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, copy_target.frame, &special_frames, .LeadParamNone, 1, copy_command.span.Code.?, true));
    try std.testing.expectEqualStrings("hello", line_ops.getLineContent(copy_target.content_lines[0]));
    try std.testing.expectEqualStrings("hellotarget", line_ops.getLineContent(copy_target.content_lines[1]));

    const transfer_target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "hello",
        "target",
    });
    span_start = null;
    span_end = null;
    try mark_ops.MarkCreate(allocator, transfer_target.content_lines[0], 1, &span_start);
    try mark_ops.MarkCreate(allocator, transfer_target.content_lines[0], 6, &span_end);
    try std.testing.expect(try span_ops.SpanCreate(&editor, allocator, "MOVE", span_start.?, span_end.?));
    try mark_ops.MarkCreate(allocator, transfer_target.content_lines[1], 1, &transfer_target.frame.Dot);

    const transfer_command = try makeCommandSpan(allocator, &[_][]const u8{"ST/MOVE/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, transfer_target.frame, transfer_command.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, transfer_target.frame, &special_frames, .LeadParamNone, 1, transfer_command.span.Code.?, true));
    try std.testing.expectEqualStrings("", line_ops.getLineContent(transfer_target.content_lines[0]));
    try std.testing.expectEqualStrings("hellotarget", line_ops.getLineContent(transfer_target.content_lines[1]));
    const moved_span = (try findSpanByName(&editor, allocator, "MOVE")) orelse return error.TestUnexpectedResult;
    try std.testing.expect(moved_span.MarkOne.?.Line == transfer_target.content_lines[1]);
    try std.testing.expectEqual(@as(isize, 1), moved_span.MarkOne.?.Col);
}

test "code interpreter executes compiled split line and equal-eol commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const split_target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "hello world",
        "second",
    });
    try mark_ops.MarkCreate(allocator, split_target.content_lines[0], 6, &split_target.frame.Dot);
    const split_command = try makeCommandSpan(allocator, &[_][]const u8{"SL"});
    try std.testing.expect(try CodeCompile(&editor, allocator, split_target.frame, split_command.span, true));
    var special_frames: types.SpecialFrames = .{};
    try std.testing.expect(try CodeInterpret(&editor, allocator, split_target.frame, &special_frames, .LeadParamNone, 1, split_command.span.Code.?, true));
    const inserted_line = split_target.content_lines[0].FLink.?;
    try std.testing.expectEqualStrings("hello", line_ops.getLineContent(split_target.content_lines[0]));
    try std.testing.expectEqualStrings(" world", line_ops.getLineContent(inserted_line));
    try std.testing.expectEqualStrings("second", line_ops.getLineContent(inserted_line.FLink));
    try line_ops.validateFrameShape(split_target.frame);

    const eql_target = try line_ops.createContentFrame(allocator, &[_][]const u8{"abc"});
    try mark_ops.MarkCreate(allocator, eql_target.content_lines[0], 4, &eql_target.frame.Dot);
    const eql_command = try makeCommandSpan(allocator, &[_][]const u8{"EOL"});
    try std.testing.expect(try CodeCompile(&editor, allocator, eql_target.frame, eql_command.span, true));
    try std.testing.expect(try CodeInterpret(&editor, allocator, eql_target.frame, &special_frames, .LeadParamNone, 1, eql_command.span.Code.?, true));
}

test "code interpreter executes compiled replace commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"hello world"});
    try mark_ops.MarkCreate(allocator, target.content_lines[0], 1, &target.frame.Dot);
    const command = try makeCommandSpan(allocator, &[_][]const u8{"R/world/earth/"});
    try std.testing.expect(try CodeCompile(&editor, allocator, target.frame, command.span, true));
    var special_frames: types.SpecialFrames = .{};
    try std.testing.expect(try CodeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.Code.?, true));
    try std.testing.expectEqualStrings("hello earth", target.content_lines[0].Str.?.Slice(1, 11));
}
