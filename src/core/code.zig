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
    code_base: isize = 0,
    current_point: types.MarkObject = undefined,
    start_point: types.MarkObject = undefined,
    end_point: types.MarkObject = undefined,
    verify_count: isize = 0,
    from_span: bool = false,
    input_buffer: ?[]const u8 = null,
    input_index: usize = 0,
    live_input: bool = false,
};

const Labels = struct {
    exit_label: isize = 0,
    fail_label: isize = 0,
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
        .Cmdexit_abort,
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
    if (ps.input_buffer) |buffer| {
        while (ps.input_index < buffer.len and (buffer[ps.input_index] == '\r' or buffer[ps.input_index] == '\n')) : (ps.input_index += 1) {}
        if (ps.input_index >= buffer.len) {
            ps.key = 0;
        } else {
            ps.key = buffer[ps.input_index];
            ps.input_index += 1;
        }
        return true;
    }

    if (ps.live_input) {
        const key = interactive_io.readInputKey() catch return false;
        if (key) |live_key| {
            ps.key = live_key;
        } else {
            ps.key = 0;
        }
        return true;
    }

    if (!ps.from_span) {
        ps.key = 0;
        return false;
    }

    if (ps.current_point.line == ps.end_point.line and ps.current_point.col == ps.end_point.col) {
        ps.key = 0;
        return true;
    }

    if (ps.current_point.col <= ps.current_point.line.used) {
        ps.key = ps.current_point.line.str.?.get(ps.current_point.col);
        ps.current_point.col += 1;
    } else if (ps.current_point.line != ps.end_point.line) {
        ps.key = ' ';
        ps.eoln = true;
        ps.current_point.line = ps.current_point.line.f_link.?;
        ps.current_point.col = 1;
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
            if (ps.from_span and ps.key == '<' and ps.current_point.col <= ps.current_point.line.used and ps.current_point.line.str.?.get(ps.current_point.col) == '>') {
                ps.key = 0;
            }
            if (ps.key != ' ') {
                break;
            }
        }
        if (ps.key != '!') {
            return true;
        }
        if (!ps.from_span) {
            ps.status = "Comments illegal";
            return false;
        }
        ps.current_point.col = ps.current_point.line.used + 1;
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
    if (ps.code_base + ps.pc > types.max_code) {
        ps.status = "Compiler code overflow";
        return false;
    }
    const cc = &editor.compiler_code[@intCast(ps.code_base + ps.pc)];
    cc.rep = rep;
    cc.cnt = cnt;
    cc.op = op;
    cc.tpar = tpar;
    cc.lbl = lbl;
    cc.code = code;
    return true;
}

fn poke(editor: *state.Editor, code_base: isize, location: isize, new_label: isize) void {
    editor.compiler_code[@intCast(code_base + location)].lbl = new_label;
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
            if (rep_count.* <= 0 or rep_count.* > types.max_user_mark_number) {
                return compileError(ps, "Illegal mark number");
            }
        },
        '=' => {
            if (!nextKey(ps)) return false;
            rep_sym.* = .LeadParamMarker;
            rep_count.* = types.mark_equals;
        },
        '%' => {
            if (!nextKey(ps)) return false;
            rep_sym.* = .LeadParamMarker;
            rep_count.* = types.mark_modified;
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
        .str = try str_object.newBlankStrObject(allocator, types.max_str_len),
        .dlm = types.tpd_prompt,
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
    var tp_count = editor.cmd_attrib[cmdIndex(command)].tp_count;
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
                tail.?.nxt = node;
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
    if (ps.key < 0 or ps.key > types.max_set_range or !@import("chars.zig").chIsPunctuation(@intCast(ps.key))) {
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
            const par_string = str_object.newBlankStrObject(allocator, types.max_str_len) catch return compileError(ps, "Out of memory");
            while (true) {
                if (!nextKey(ps)) {
                    return false;
                }
                if (ps.key == 0) {
                    return compileError(ps, "Missing trailing delimiter");
                }
                par_length += 1;
                par_string.set(par_length, @intCast(ps.key));
                if (ps.eoln or ps.key == par_delim) {
                    break;
                }
            }
            par_length -= 1;
            if (ps.eoln and !editor.cmd_attrib[cmdIndex(command)].tpar_info[@intCast(tci)].ml_allowed) {
                return compileError(ps, "Missing trailing delimiter");
            }

            const node = allocator.create(types.TParObject) catch return compileError(ps, "Out of memory");
            node.* = .{
                .len = par_length,
                .dlm = @intCast(par_delim),
                .str = par_string,
            };
            if (param_head == null) {
                param_head = node;
            } else {
                param_tail.?.con = node;
            }
            param_tail = node;

            if (ps.key == par_delim) {
                break;
            }
        }

        if (head == null) {
            head = param_head;
        } else {
            prev_param.?.nxt = param_head;
        }
        prev_param = param_head;
    }

    result.* = head;
    return true;
}

fn lookupExpansionRange(editor: *state.Editor, command: types.Commands) struct { usize, usize } {
    const start = editor.lookup_exp_ptr[cmdIndex(command)];
    var next = cmdIndex(command) + 1;
    while (next < editor.lookup_exp_ptr.len and editor.lookup_exp_ptr[next] == 0) : (next += 1) {}
    const end = if (next < editor.lookup_exp_ptr.len) editor.lookup_exp_ptr[next] else types.lookup_exp_count;
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
    const lp_allowed = editor.cmd_attrib[cmdIndex(command)].lp_allowed;
    if ((lp_allowed & (@as(u32, 1) << @intCast(@intFromEnum(rep_sym)))) == 0) {
        return compileError(ps, "Illegal leading parameter");
    }

    if (command == .CmdVerify) {
        ps.verify_count += 1;
        if (ps.verify_count > types.max_verify) {
            return compileError(ps, "Too many verify commands in span");
        }
        rep_count.* = ps.verify_count;
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
            poke(editor, ps.code_base, pc1, ps.pc + 1);
            if (!nextNonBl(ps)) {
                return false;
            }
            while (ps.key != ']') {
                if (!scanCommand(allocator, editor, ps, full_scan)) {
                    return false;
                }
            }
            poke(editor, ps.code_base, pc4.*, ps.pc + 1);
        } else {
            poke(editor, ps.code_base, pc1, ps.pc + 1);
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
    poke(editor, ps.code_base, pc2.*, ps.pc + 1);
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

    if (ps.key >= 0 and ps.key <= types.max_set_range) {
        ps.key = @intCast(@import("chars.zig").chToUpper(@intCast(ps.key)));
    }

    var command = editor.lookup[@intCast(ps.key)].command;
    while (editor.prefixes.isSet(@intFromEnum(command))) {
        if (!nextKey(ps)) {
            return false;
        }
        if (ps.key < 0 or ps.key > types.max_set_range) {
            return compileError(ps, "Command not valid");
        }
        const bounds = lookupExpansionRange(editor, command);
        var index = bounds.@"0";
        const target = @import("chars.zig").chToUpper(@intCast(ps.key));
        while (index < bounds.@"1" and target != editor.lookup_exp[index].extn) : (index += 1) {}
        if (index < bounds.@"1") {
            command = editor.lookup_exp[index].command;
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

pub fn codeDiscard(editor: *state.Editor, code_head: *?*types.CodeHeader) void {
    code_store.codeDiscard(editor, code_head);
}

fn compileParsed(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    span: *types.SpanObject,
    ps: *ParseState,
    full_scan: bool,
) !bool {
    if (span.code != null) {
        codeDiscard(editor, &span.code);
    }

    ps.code_base = editor.code_top;
    ps.pc = 0;
    ps.verify_count = 0;

    if (!nextNonBl(ps)) {
        editor.exit_abort = true;
        return false;
    }
    if (ps.key == 0) {
        editor.exit_abort = true;
        return false;
    }

    if (full_scan) {
        while (ps.key != 0) {
            if (!scanCommand(allocator, editor, ps, true)) {
                editor.exit_abort = true;
                return false;
            }
        }
    } else {
        if (!scanCommand(allocator, editor, ps, false)) {
            editor.exit_abort = true;
            return false;
        }
    }

    if (!generate(editor, ps, .LeadParamPInt, 1, .CmdExitSuccess, null, 0, null)) {
        editor.exit_abort = true;
        return false;
    }

    const header = try allocator.create(types.CodeHeader);
    header.* = .{
        .ref = 1,
        .code = ps.code_base + 1,
        .len = ps.pc,
        .f_link = editor.code_list.?.f_link,
        .b_link = editor.code_list,
    };
    editor.code_list.?.f_link.?.b_link = header;
    editor.code_list.?.f_link = header;
    editor.code_top = ps.code_base + ps.pc;
    span.code = header;
    return true;
}

pub fn codeCompile(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    span: *types.SpanObject,
    from_span: bool,
) !bool {
    var ps = ParseState{
        .from_span = from_span,
    };
    var uses_immediate_input = false;
    _ = frame;

    defer if (uses_immediate_input) {
        editor.immediate_input_index = ps.input_index;
        if (editor.immediate_input) |buffer| {
            if (editor.immediate_input_index >= buffer.len) {
                editor.clearImmediateInput();
            }
        }
    };

    if (!from_span) {
        if (editor.immediate_input) |buffer| {
            ps.input_buffer = buffer;
            ps.input_index = editor.immediate_input_index;
            uses_immediate_input = true;
        } else if (editor.ludwig_mode == .ludwig_screen) {
            ps.live_input = true;
        } else {
            editor.exit_abort = true;
            return false;
        }
    }
    if (from_span and (span.mark_one == null or span.mark_two == null)) {
        editor.exit_abort = true;
        return false;
    }
    if (from_span) {
        ps.start_point = span.mark_one.?.*;
        ps.end_point = span.mark_two.?.*;
        ps.current_point = ps.start_point;
    }

    return compileParsed(editor, allocator, span, &ps, from_span);
}

pub fn codeCompileString(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    span: *types.SpanObject,
    source: []const u8,
) !bool {
    var ps = ParseState{
        .from_span = false,
        .input_buffer = source,
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
        .from_span = false,
        .input_buffer = source,
    };
    return compileParsed(editor, allocator, span, &ps, full_scan);
}

fn resolveLeadMark(frame: *types.FrameObject, count: isize) ?*types.MarkObject {
    if (count < 0 or count > types.max_mark_number) {
        return null;
    }
    return frame.marks[@intCast(count)];
}

fn markModifiedAtDot(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !void {
    frame.text_modified = true;
    if (frame.dot) |dot| {
        try mark_ops.markCreate(allocator, dot.line, dot.col, &frame.marks[types.mark_modified]);
    }
}

fn findSpanByName(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    name: []const u8,
) !?*types.SpanObject {
    var span_ptr: ?*types.SpanObject = null;
    var span_prev: ?*types.SpanObject = null;
    if (try span_ops.spanFind(editor, allocator, name, &span_ptr, &span_prev)) {
        return span_ptr;
    }
    return null;
}

fn emitBatchMessage(editor: *const state.Editor, message: []const u8) void {
    switch (editor.ludwig_mode) {
        .ludwig_screen => interactive_io.queueStatusMessage(message),
        .ludwig_batch, .ludwig_hardcopy => {
            if (editor.batch_output_enabled) {
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
    return span_ops.spanCreate(editor, allocator, name, first_mark, last_mark);
}

fn destroyNamedSpan(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    span_slot: *?*types.SpanObject,
) bool {
    return span_ops.spanDestroy(editor, allocator, span_slot);
}

fn executeAdvance(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
    target_mark: ?*types.MarkObject,
) !bool {
    var new_line = frame.dot.?.line;
    var remaining = count;
    var success = rept == .LeadParamPIndef or rept == .LeadParamNIndef or rept == .LeadParamMarker;

    switch (rept) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            while (remaining > 0) : (remaining -= 1) {
                new_line = new_line.f_link orelse return false;
            }
            if (new_line.f_link == null) return false;
            success = true;
        },
        .LeadParamMinus, .LeadParamNInt => {
            remaining = -remaining;
            while (remaining > 0) : (remaining -= 1) {
                new_line = new_line.b_link orelse return false;
            }
            success = true;
        },
        .LeadParamPIndef => new_line = frame.last_group.?.last_line.?,
        .LeadParamNIndef => new_line = frame.first_group.?.first_line.?,
        .LeadParamMarker => new_line = target_mark.?.line,
    }

    if (success) {
        try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col, &frame.marks[types.mark_equals]);
        try mark_ops.markCreate(allocator, new_line, 1, &frame.dot);
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
    var new_eql = frame.dot.?.*;
    const used_split_line = command == .CmdReturn and
        editor.edit_mode == .mode_insert and
        frame.options.newLine and
        frame.dot.?.line.f_link != null;

    const cmd_success = switch (command) {
        .CmdLeft => arrow.doCmdLeft(frame, rept, count, &new_eql),
        .CmdRight => arrow.doCmdRight(frame, rept, count, &new_eql),
        .CmdTab => arrow.doCmdTabBacktab(frame, 1, count, &new_eql),
        .CmdBacktab => arrow.doCmdTabBacktab(frame, -1, count, &new_eql),
        .CmdHome => arrow.doCmdHome(&editor.screen, frame, &new_eql),
        .CmdUp => try arrow.doCmdUp(allocator, frame, rept, count, &new_eql),
        .CmdDown => try arrow.doCmdDown(
            allocator,
            frame,
            rept,
            count,
            &new_eql,
            line_ops.lineToNumber(frame.last_group.?.last_line.?),
        ),
        .CmdReturn => blk: {
            if (editor.edit_mode == .mode_insert and frame.options.newLine) {
                if (frame.dot.?.line.f_link == null) {
                    try text.textRealizeNull(allocator, frame.dot.?.line);
                    var eop_line_nr = line_ops.lineToNumber(frame.last_group.?.last_line.?);
                    break :blk try arrow.doCmdReturn(allocator, frame, count, &new_eql, &eop_line_nr);
                }
                break :blk try text.textSplitLine(allocator, frame.dot.?, 0, &frame.marks[types.mark_equals]);
            }
            var eop_line_nr = line_ops.lineToNumber(frame.last_group.?.last_line.?);
            break :blk try arrow.doCmdReturn(allocator, frame, count, &new_eql, &eop_line_nr);
        },
        else => false,
    };

    var final_success = cmd_success;
    if (cmd_success and !used_split_line) {
        try mark_ops.markCreate(allocator, new_eql.line, new_eql.col, &frame.marks[types.mark_equals]);
        if (command == .CmdDown and rept != .LeadParamPIndef and frame.dot.?.line.f_link == null) {
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
    const dot = frame.dot orelse return null;
    var first_line: ?*types.LineHdrObject = dot.line;
    var last_line: ?*types.LineHdrObject = dot.line;

    switch (rept) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            if (count == 0) {
                first_line = null;
            } else if (count <= 20) {
                var line_nr: isize = 1;
                while (line_nr < count) : (line_nr += 1) {
                    last_line = last_line.?.f_link orelse return null;
                }
                if (last_line.?.f_link == null) {
                    return null;
                }
            } else {
                const line_nr = line_ops.lineToNumber(first_line.?);
                last_line = line_ops.lineFromNumber(frame, line_nr + count - 1) orelse return null;
                if (last_line.?.f_link == null) {
                    return null;
                }
            }
        },
        .LeadParamMinus, .LeadParamNInt => {
            const abs_count = -count;
            last_line = dot.line.b_link orelse return null;
            if (abs_count <= 20) {
                var line_nr: isize = 1;
                while (line_nr <= abs_count) : (line_nr += 1) {
                    first_line = first_line.?.b_link orelse return null;
                }
            } else {
                var line_nr = line_ops.lineToNumber(last_line.?);
                if (abs_count > line_nr) {
                    return null;
                }
                line_nr = line_nr - abs_count + 1;
                first_line = line_ops.lineFromNumber(frame, line_nr);
            }
        },
        .LeadParamPIndef => {
            if (dot.line.f_link == null) {
                first_line = null;
            } else {
                last_line = frame.last_group.?.last_line.?.b_link;
            }
        },
        .LeadParamNIndef => {
            last_line = dot.line.b_link;
            if (last_line == null) {
                first_line = null;
            } else {
                first_line = frame.first_group.?.first_line;
            }
        },
        .LeadParamMarker => {
            const mark_line = mark orelse return null;
            if (mark_line.line == first_line.?) {
                first_line = null;
            } else if (mark_line.line.f_link == first_line.?) {
                first_line = mark_line.line;
                last_line = mark_line.line;
            } else if (mark_line.line.b_link == first_line.?) {
                last_line = first_line.?;
            } else {
                const mark_line_nr = line_ops.lineToNumber(mark_line.line);
                const line_nr = line_ops.lineToNumber(dot.line);
                if (mark_line_nr < line_nr) {
                    first_line = mark_line.line;
                    last_line = last_line.?.b_link;
                } else {
                    last_line = mark_line.line.b_link;
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
    const left_line = line_ops.lineToNumber(left.line);
    const right_line = line_ops.lineToNumber(right.line);
    if (left_line < right_line) return .lt;
    if (left_line > right_line) return .gt;
    return std.math.order(left.col, right.col);
}

fn joinLines(allocator: std.mem.Allocator, frame: *types.FrameObject) !bool {
    if (!frame.options.newLine) {
        return false;
    }
    const previous = frame.dot.?.line.b_link orelse return false;
    var other_mark: ?*types.MarkObject = null;
    defer mark_ops.markDestroy(allocator, &other_mark);
    try mark_ops.markCreate(allocator, previous, previous.used + 1, &other_mark);
    if (!try text.textRemove(allocator, other_mark.?, frame.dot.?)) {
        return false;
    }
    frame.text_modified = true;
    try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col, &frame.marks[types.mark_modified]);
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
    const maximum = if (frame.dot.?.col <= frame.dot.?.line.used)
        types.max_str_len - frame.dot.?.line.used
    else
        types.max_str_len - frame.dot.?.col;
    if (count_abs > maximum) {
        return false;
    }

    if (!try text.textInsert(allocator, true, 1, editor.blank_string.?, count_abs, frame.dot.?)) {
        return false;
    }

    const eql_col = if (rept_mut == .LeadParamNInt)
        frame.dot.?.col - count_abs
    else
        frame.dot.?.col;
    if (rept_mut != .LeadParamNInt) {
        try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col - count_abs, &frame.dot);
    }
    frame.text_modified = true;
    try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col, &frame.marks[types.mark_modified]);
    try mark_ops.markCreate(allocator, frame.dot.?.line, eql_col, &frame.marks[types.mark_equals]);
    return true;
}

fn executeDeleteMarkedRange(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    oops_frame: *types.FrameObject,
    the_mark: *types.MarkObject,
) !bool {
    var start = frame.dot.?;
    var finish = the_mark;
    if (markSortOrder(start, finish) == .gt) {
        start = the_mark;
        finish = frame.dot.?;
    }

    if (frame != oops_frame) {
        const oops_span = oops_frame.span orelse return false;
        try mark_ops.markCreate(allocator, oops_frame.last_group.?.last_line.?, 1, &oops_span.mark_two);
        if (!try text.textMove(
            allocator,
            false,
            1,
            start,
            finish,
            oops_span.mark_two.?,
            &oops_frame.marks[types.mark_equals],
            &oops_frame.dot,
        )) {
            return false;
        }
        oops_frame.text_modified = true;
        try mark_ops.markCreate(allocator, oops_frame.dot.?.line, oops_frame.dot.?.col, &oops_frame.marks[types.mark_modified]);
    } else if (!try text.textRemove(allocator, start, finish)) {
        return false;
    }

    frame.text_modified = true;
    try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col, &frame.marks[types.mark_modified]);
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
            if (count_mut > types.max_str_len_p1 - frame.dot.?.col) {
                return false;
            }
        },
        .LeadParamPIndef => {
            count_mut = types.max_str_len_p1 - frame.dot.?.col;
        },
        .LeadParamMinus, .LeadParamNInt => {
            count_mut = -count_mut;
            if (count_mut < frame.dot.?.col) {
                try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col - count_mut, &frame.dot);
            } else if (!from_span and count_mut == 1 and frame.dot.?.col == 1 and try joinLines(allocator, frame)) {
                mark_ops.markDestroy(allocator, &frame.marks[types.mark_equals]);
                return true;
            } else {
                return false;
            }
        },
        .LeadParamNIndef => {
            count_mut = frame.dot.?.col - 1;
            try mark_ops.markCreate(allocator, frame.dot.?.line, 1, &frame.dot);
        },
        .LeadParamMarker => unreachable,
    }

    var end_mark: ?*types.MarkObject = null;
    defer mark_ops.markDestroy(allocator, &end_mark);
    try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col + count_mut, &end_mark);
    if (!try text.textRemove(allocator, frame.dot.?, end_mark.?)) {
        return false;
    }

    frame.text_modified = true;
    try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col, &frame.marks[types.mark_modified]);
    mark_ops.markDestroy(allocator, &frame.marks[types.mark_equals]);
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
    const after = last.f_link orelse return false;
    const dot_col = frame.dot.?.col;
    const oops = oops_frame orelse return false;

    try mark_ops.marksSqueeze(allocator, first, 1, after, 1);
    line_ops.linesExtract(first, last);

    if (frame != oops) {
        try line_ops.linesInject(allocator, first, last, oops.last_group.?.last_line.?);
        try mark_ops.markCreate(allocator, first, 1, &oops.marks[types.mark_equals]);
        try mark_ops.markCreate(allocator, oops.last_group.?.last_line.?, 1, &oops.dot);
        oops.text_modified = true;
        try mark_ops.markCreate(allocator, oops.dot.?.line, oops.dot.?.col, &oops.marks[types.mark_modified]);
    }

    frame.dot.?.col = dot_col;
    frame.text_modified = true;
    try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col, &frame.marks[types.mark_modified]);
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
    if (editor.edit_mode == .mode_insert) {
        const delete_rept: types.LeadParam = if (rept == .LeadParamPIndef) .LeadParamNIndef else .LeadParamNInt;
        return executeDeleteChar(allocator, frame, null, delete_rept, -count, null, from_span);
    }

    var count_mut = count;
    if (rept == .LeadParamPIndef) {
        count_mut = frame.dot.?.col - 1;
    }
    if (count_mut > frame.dot.?.col - 1) {
        return false;
    }

    const eql_col = frame.dot.?.col;
    try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col - count_mut, &frame.dot);
    if (!try text.textOvertype(allocator, true, 1, editor.blank_string.?, count_mut, frame.dot.?)) {
        return false;
    }
    try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col - count_mut, &frame.dot);

    frame.text_modified = true;
    try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col, &frame.marks[types.mark_modified]);
    try mark_ops.markCreate(allocator, frame.dot.?.line, eql_col, &frame.marks[types.mark_equals]);
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
            if (frame.dot.?.col + count > types.max_str_len_p1) {
                return false;
            }
            try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col + count, &frame.dot);
        },
        .LeadParamMinus, .LeadParamNInt => {
            if (frame.dot.?.col <= -count) {
                return false;
            }
            try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col + count, &frame.dot);
        },
        .LeadParamPIndef => {
            if (frame.dot.?.col > frame.dot.?.line.used + 1) {
                return false;
            }
            try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.line.used + 1, &frame.dot);
        },
        .LeadParamNIndef => {
            try mark_ops.markCreate(allocator, frame.dot.?.line, 1, &frame.dot);
        },
        .LeadParamMarker => {
            const marker = the_mark orelse return false;
            try mark_ops.markCreate(allocator, marker.line, marker.col, &frame.dot);
        },
    }
    return true;
}

fn clampOpsysTabWidth(editor: *const state.Editor) usize {
    return @intCast(@min(@as(isize, 8), @max(@as(isize, 2), editor.file_data.tab_width)));
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
    const range = try line_ops.linesCreate(allocator, 1);
    if (content.len > 0) {
        try line_ops.lineChangeLength(allocator, range.first, @intCast(content.len));
        try line_ops.setLineContent(range.first, content);
    } else {
        range.first.used = 0;
    }

    if (last.*) |tail| {
        tail.f_link = range.first;
        range.first.b_link = tail;
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
    var line_buffer: std.ArrayList(u8) = .{};
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
                if (line_buffer.items.len == types.max_str_len) {
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

        if (line_buffer.items.len == types.max_str_len) {
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
        .max_output_bytes = @intCast(types.max_space),
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
    if (!try tpar_ops.tparGet1(allocator, editor, frame, tparam, .CmdOpSysCommand, &request)) {
        return false;
    }
    if (request.len == 0 or request.len > types.file_name_len) {
        return false;
    }

    const output = runOpsysCommand(allocator, request.str.?.slice(1, request.len)) catch return false;
    defer allocator.free(output);

    const range = (try buildOpsysLineRange(editor, allocator, output)) orelse return false;
    try line_ops.linesInject(allocator, range.first, range.last, frame.dot.?.line);
    try mark_ops.markCreate(allocator, range.first, 1, &frame.marks[types.mark_equals]);
    try mark_ops.markCreate(allocator, range.last.f_link.?, 1, &frame.dot);
    try markModifiedAtDot(allocator, frame);
    return true;
}

fn execute(
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
    const old_dot = current_frame.dot.?.*;
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
            if (try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                cmd_success = try nextbridge.nextbridgeCommand(allocator, current_frame, count, &request, command == .CmdBridge);
            }
        },
        .CmdCaseEdit, .CmdCaseLow, .CmdCaseUp, .CmdDittoDown, .CmdDittoUp => {
            cmd_success = try caseditto.caseDittoCommand(
                allocator,
                current_frame,
                command,
                rept,
                count,
                true,
                editor.edit_mode,
                editor.previous_mode,
            );
        },
        .CmdDeleteChar => {
            cmd_success = try executeDeleteChar(allocator, current_frame, special_frames.oops, rept, count, the_mark, from_span);
        },
        .CmdDeleteLine => {
            cmd_success = try executeDeleteLine(allocator, current_frame, special_frames.oops, rept, count, the_mark);
        },
        .CmdDump => {
            cmd_success = false;
        },
        .CmdEqualColumn => {
            var request: types.TParObject = .{};
            if (try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                var index: isize = 1;
                if (tpar_ops.tparToIntMessage(editor, &request, &index)) |column| {
                    cmd_success = switch (rept) {
                        .LeadParamNone, .LeadParamPlus => current_frame.dot.?.col == column,
                        .LeadParamMinus => current_frame.dot.?.col != column,
                        .LeadParamPIndef => current_frame.dot.?.col >= column,
                        .LeadParamNIndef => current_frame.dot.?.col <= column,
                        else => false,
                    };
                }
            }
        },
        .CmdEqualEol => {
            const eol_col = current_frame.dot.?.line.used + 1;
            cmd_success = switch (rept) {
                .LeadParamNone, .LeadParamPlus => current_frame.dot.?.col == eol_col,
                .LeadParamMinus => current_frame.dot.?.col != eol_col,
                .LeadParamPIndef => current_frame.dot.?.col >= eol_col,
                .LeadParamNIndef => current_frame.dot.?.col <= eol_col,
                else => false,
            };
        },
        .CmdEqualEop, .CmdEqualEof => {
            cmd_success = current_frame.dot.?.line.f_link == null;
            if (command == .CmdEqualEof and current_frame.input_file != 0) {
                const input_file = editor.files[@intCast(current_frame.input_file)];
                if (input_file != null and !input_file.?.eof) {
                    cmd_success = false;
                }
            }
            if (rept == .LeadParamMinus) {
                cmd_success = !cmd_success;
            }
        },
        .CmdEqualMark => {
            var request: types.TParObject = .{};
            if (try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                if (tpar_ops.tparToMarkMessage(editor, &request)) |mark_index| {
                    if (resolveLeadMark(current_frame, mark_index)) |mark| {
                        cmd_success = switch (rept) {
                            .LeadParamNone, .LeadParamPlus => mark.line == current_frame.dot.?.line and mark.col == current_frame.dot.?.col,
                            .LeadParamMinus => !(mark.line == current_frame.dot.?.line and mark.col == current_frame.dot.?.col),
                            .LeadParamPIndef => blk: {
                                if (mark.line == current_frame.dot.?.line) {
                                    break :blk current_frame.dot.?.col >= mark.col;
                                }
                                break :blk line_ops.lineToNumber(current_frame.dot.?.line) >= line_ops.lineToNumber(mark.line);
                            },
                            .LeadParamNIndef => blk: {
                                if (mark.line == current_frame.dot.?.line) {
                                    break :blk current_frame.dot.?.col <= mark.col;
                                }
                                break :blk line_ops.lineToNumber(current_frame.dot.?.line) <= line_ops.lineToNumber(mark.line);
                            },
                            else => false,
                        };
                    }
                }
            }
        },
        .CmdEqualString => {
            var request: types.TParObject = .{};
            if (try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                if (request.len == 0) {
                    request = current_frame.eqs_tpar;
                    if (request.len == 0) return false;
                } else {
                    current_frame.eqs_tpar = request;
                }
                cmd_success = try eqsgetrep.eqsGetRepEqs(allocator, current_frame, rept, &request);
            }
        },
        .CmdDoLastCommand, .CmdExecuteString => {
            const cmd_frame = special_frames.cmd orelse return false;
            const cmd_span = cmd_frame.span orelse return false;
            if (current_frame == cmd_frame) {
                return false;
            }

            if (command == .CmdExecuteString) {
                var request: types.TParObject = .{};
                if (!try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                    return false;
                }
                if (request.len == 0) {
                    return false;
                }
                if (!try codeCompileBuffer(editor, allocator, cmd_span, request.str.?.slice(1, request.len), true)) {
                    return false;
                }
            } else if (cmd_span.code == null) {
                if (!try codeCompile(editor, allocator, cmd_frame, cmd_span, true)) {
                    return false;
                }
            }

            const outcome = try codeInterpretFrame(
                editor,
                allocator,
                current_frame,
                special_frames,
                rept,
                count,
                cmd_span.code.?,
                true,
            );
            current_frame = outcome.frame;
            cmd_success = outcome.ok;
        },
        .CmdFileExecute => {
            const cmd_frame = special_frames.cmd orelse return false;
            const cmd_span = cmd_frame.span orelse return false;
            if (current_frame == cmd_frame) {
                return false;
            }

            var request: types.TParObject = .{};
            if (!try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                return false;
            }
            if (request.len == 0) {
                return false;
            }
            if (!try file_ops.loadBufferedFileIntoFrameByName(editor, allocator, cmd_frame, request.str.?.slice(1, request.len))) {
                return false;
            }
            if (!try codeCompile(editor, allocator, current_frame, cmd_span, true)) {
                return false;
            }

            const outcome = try codeInterpretFrame(
                editor,
                allocator,
                current_frame,
                special_frames,
                rept,
                count,
                cmd_span.code.?,
                true,
            );
            current_frame = outcome.frame;
            cmd_success = outcome.ok;
        },
        .CmdFrameEdit => {
            var request: types.TParObject = .{};
            if (try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                const frame_name = if (request.len == 0) "" else request.str.?.slice(1, request.len);
                current_frame = (try frame_ops.frameEdit(editor, allocator, current_frame, frame_name)) orelse return false;
                cmd_success = true;
            }
        },
        .CmdFrameKill => {
            var request: types.TParObject = .{};
            if (try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                if (request.len == 0) {
                    return false;
                }
                cmd_success = try frame_ops.frameKill(editor, allocator, current_frame, request.str.?.slice(1, request.len));
            }
        },
        .CmdFrameParameters => {
            cmd_success = try frame_ops.frameParameter(editor, allocator, current_frame, tparam);
        },
        .CmdFrameReturn => {
            var iteration: isize = 1;
            while (iteration <= count) : (iteration += 1) {
                if (current_frame.return_frame == null) {
                    current_frame = old_frame;
                    return false;
                }
                current_frame = current_frame.return_frame.?;
            }
            cmd_success = true;
        },
        .CmdGet => {
            var request: types.TParObject = .{};
            if (try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                if (request.len == 0) {
                    request = current_frame.get_tpar;
                    if (request.len == 0) return false;
                } else {
                    current_frame.get_tpar = request;
                }
                cmd_success = try eqsgetrep.eqsGetRepGet(allocator, current_frame, count, &request, true);
            }
        },
        .CmdHelp => {
            var request: types.TParObject = .{};
            if (try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                const topic = if (request.len == 0) "" else request.str.?.slice(1, request.len);
                if (editor.ludwig_mode == .ludwig_screen) {
                    cmd_success = try help_ops.helpInteractive(editor, allocator, topic);
                } else {
                    const oops = special_frames.oops orelse return false;
                    cmd_success = try help_ops.helpCommand(editor, allocator, oops, topic);
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
                const range = try line_ops.linesCreate(allocator, @intCast(abs_count));
                try line_ops.linesInject(allocator, range.first, range.last, current_frame.dot.?.line);
                if (count > 0) {
                    try mark_ops.markCreate(allocator, current_frame.dot.?.line, current_frame.dot.?.col, &current_frame.marks[types.mark_equals]);
                    try mark_ops.markCreate(allocator, range.first, current_frame.dot.?.col, &current_frame.dot);
                } else {
                    try mark_ops.markCreate(allocator, range.first, current_frame.dot.?.col, &current_frame.marks[types.mark_equals]);
                }
                try markModifiedAtDot(allocator, current_frame);
            } else {
                try mark_ops.markCreate(allocator, current_frame.dot.?.line, current_frame.dot.?.col, &current_frame.marks[types.mark_equals]);
            }
            cmd_success = true;
        },
        .CmdInsertMode => {
            editor.edit_mode = .mode_insert;
            cmd_success = true;
        },
        .CmdInsertInvisible => {
            cmd_success = false;
        },
        .CmdInsertText => {
            if (editor.file_data.old_cmds and !from_span) {
                if (rept == .LeadParamNone) {
                    editor.edit_mode = .mode_insert;
                    cmd_success = true;
                } else {
                    return false;
                }
            } else {
                var request: types.TParObject = .{};
                if (try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                    if (request.con == null) {
                        cmd_success = try text.textInsert(allocator, true, count, request.str.?, request.len, current_frame.dot.?);
                    } else {
                        var iteration: isize = 0;
                        cmd_success = true;
                        while (iteration < count) : (iteration += 1) {
                            if (!try text.textInsertTpar(allocator, &request, current_frame.dot.?, &current_frame.marks[types.mark_equals])) {
                                cmd_success = false;
                                break;
                            }
                        }
                    }
                    if (cmd_success and count * request.len != 0) {
                        try markModifiedAtDot(allocator, current_frame);
                    }
                }
            }
        },
        .CmdLineCentre => {
            cmd_success = try word.wordCentre(allocator, current_frame, rept, count);
        },
        .CmdLineFill => {
            cmd_success = try word.wordFill(allocator, current_frame, rept, count);
        },
        .CmdLineJustify => {
            cmd_success = try word.wordJustify(allocator, current_frame, rept, count);
        },
        .CmdLineLeft => {
            cmd_success = try word.wordLeft(allocator, current_frame, rept, count);
        },
        .CmdLineRight => {
            cmd_success = try word.wordRight(allocator, current_frame, rept, count);
        },
        .CmdLineSquash => {
            cmd_success = try word.wordSqueeze(allocator, current_frame, rept, count);
        },
        .CmdMark => {
            const abs_count: isize = if (count < 0) -count else count;
            if (abs_count == 0 or abs_count > types.max_user_mark_number) {
                emitBatchMessage(editor, "Illegal mark number.");
                return false;
            }
            if (count < 0) {
                mark_ops.markDestroy(allocator, &current_frame.marks[@intCast(-count)]);
            } else {
                try mark_ops.markCreate(allocator, current_frame.dot.?.line, current_frame.dot.?.col, &current_frame.marks[@intCast(count)]);
            }
            cmd_success = true;
        },
        .CmdReplace => {
            var request1: types.TParObject = .{};
            var request2: types.TParObject = .{};
            if (try tpar_ops.tparGet2(allocator, editor, current_frame, tparam, command, &request1, &request2)) {
                if (request1.len == 0) {
                    if (current_frame.rep_1_tpar.len == 0) return false;
                } else {
                    current_frame.rep_1_tpar = request1;
                    current_frame.rep_2_tpar = request2;
                }
                cmd_success = try eqsgetrep.eqsGetRepRep(
                    allocator,
                    current_frame,
                    rept,
                    count,
                    &current_frame.rep_1_tpar,
                    &current_frame.rep_2_tpar,
                    true,
                );
            }
        },
        .CmdRubout => {
            cmd_success = try executeRubout(editor, allocator, current_frame, rept, count, from_span);
        },
        .CmdSetMarginLeft => {
            if (rept == .LeadParamMinus) {
                current_frame.margin_left = editor.initial_margin_left;
                cmd_success = true;
            } else if (current_frame.dot.?.col < current_frame.margin_right) {
                current_frame.margin_left = current_frame.dot.?.col;
                cmd_success = true;
            }
        },
        .CmdSetMarginRight => {
            if (rept == .LeadParamMinus) {
                current_frame.margin_right = editor.initial_margin_right;
                cmd_success = true;
            } else if (current_frame.dot.?.col > current_frame.margin_left) {
                current_frame.margin_right = current_frame.dot.?.col;
                cmd_success = true;
            }
        },
        .CmdSpanIndex => {
            const oops = special_frames.oops orelse return false;
            cmd_success = try span_ops.spanIndex(editor, allocator, oops);
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
                if (!try tpar_ops.tparGet2(allocator, editor, current_frame, tparam, command, &request1, &request2)) {
                    return false;
                }
                if (request1.len == 0) {
                    return false;
                }
                const oops_frame = special_frames.oops orelse return false;
                const oops_span = oops_frame.span orelse return false;
                const heap_frame = special_frames.heap orelse return false;
                const heap_span = heap_frame.span orelse return false;
                const span_name = request1.str.?.slice(1, request1.len);

                var span_ptr = try findSpanByName(editor, allocator, span_name);
                if (span_ptr) |existing| {
                    if (oops_span == existing) {
                        if (!try text.textRemove(allocator, oops_span.mark_one.?, oops_span.mark_two.?)) {
                            return false;
                        }
                    } else {
                        try mark_ops.markCreate(allocator, oops_frame.last_group.?.last_line.?, 1, &oops_span.mark_two);
                        if (!try text.textMove(
                            allocator,
                            false,
                            1,
                            existing.mark_one.?,
                            existing.mark_two.?,
                            oops_span.mark_two.?,
                            &oops_frame.marks[types.mark_equals],
                            &oops_frame.dot,
                        )) {
                            return false;
                        }
                    }
                } else {
                    try mark_ops.markCreate(allocator, heap_frame.last_group.?.last_line.?, 1, &heap_span.mark_two);
                    if (!try createNamedSpan(editor, allocator, span_name, heap_span.mark_two.?, heap_span.mark_two.?)) {
                        return false;
                    }
                    span_ptr = (try findSpanByName(editor, allocator, span_name)) orelse return false;
                }

                if (!try text.textInsertTpar(allocator, &request2, span_ptr.?.mark_two.?, &span_ptr.?.mark_one)) {
                    return false;
                }
                const span_frame = span_ptr.?.mark_two.?.line.group.?.frame;
                span_frame.text_modified = true;
                try mark_ops.markCreate(
                    allocator,
                    span_ptr.?.mark_two.?.line,
                    span_ptr.?.mark_two.?.col,
                    &span_frame.marks[types.mark_modified],
                );
                cmd_success = true;
            } else {
                var request: types.TParObject = .{};
                if (try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                    if (request.len == 0) {
                        return false;
                    }
                    const span_name = request.str.?.slice(1, request.len);
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
                                if (span_rept == .LeadParamMarker and (span_count < 0 or span_count > types.max_mark_number)) {
                                    emitBatchMessage(editor, "Illegal mark number.");
                                    return false;
                                }
                                const span_mark = if (span_rept == .LeadParamMarker) resolveLeadMark(current_frame, span_count) else null;
                                if (span_mark == null) {
                                    emitBatchMessage(editor, "Mark Not Defined.");
                                    return false;
                                }
                                cmd_success = try createNamedSpan(editor, allocator, span_name, span_mark.?, current_frame.dot.?);
                            }
                        },
                        .CmdSpanJump => {
                            const span_ptr = (try findSpanByNameOrMessage(editor, allocator, span_name)) orelse return false;
                            const target = if (rept == .LeadParamMinus) span_ptr.mark_one.? else span_ptr.mark_two.?;
                            if (target.line.group.?.frame == current_frame) {
                                try mark_ops.markCreate(allocator, current_frame.dot.?.line, current_frame.dot.?.col, &current_frame.marks[types.mark_equals]);
                                try mark_ops.markCreate(allocator, target.line, target.col, &current_frame.dot);
                                cmd_success = true;
                            } else {
                                const target_frame = target.line.group.?.frame;
                                current_frame = (try frame_ops.frameEdit(editor, allocator, current_frame, target_frame.span.?.name)) orelse return false;
                                mark_ops.markDestroy(allocator, &target_frame.marks[types.mark_equals]);
                                try mark_ops.markCreate(allocator, target.line, target.col, &target_frame.dot);
                                cmd_success = true;
                            }
                        },
                        .CmdSpanCopy, .CmdSpanTransfer => {
                            const span_ptr = (try findSpanByNameOrMessage(editor, allocator, span_name)) orelse return false;
                            cmd_success = try text.textMove(
                                allocator,
                                command == .CmdSpanCopy,
                                count,
                                span_ptr.mark_one.?,
                                span_ptr.mark_two.?,
                                current_frame.dot.?,
                                &current_frame.marks[types.mark_equals],
                                &current_frame.dot,
                            );
                            if (command == .CmdSpanTransfer and span_ptr.frame == null and cmd_success) {
                                try mark_ops.markCreate(
                                    allocator,
                                    current_frame.marks[types.mark_equals].?.line,
                                    current_frame.marks[types.mark_equals].?.col,
                                    &span_ptr.mark_one,
                                );
                                try mark_ops.markCreate(
                                    allocator,
                                    current_frame.dot.?.line,
                                    current_frame.dot.?.col,
                                    &span_ptr.mark_two,
                                );
                            }
                        },
                        .CmdSpanCompile, .CmdSpanExecute, .CmdSpanExecuteNoRecompile => {
                            const span_ptr = (try findSpanByNameOrMessage(editor, allocator, span_name)) orelse return false;
                            if (span_ptr.code == null or command != .CmdSpanExecuteNoRecompile) {
                                if (!try codeCompile(editor, allocator, current_frame, span_ptr, true)) {
                                    return false;
                                }
                            }
                            if (command == .CmdSpanCompile) {
                                cmd_success = true;
                            } else {
                                const outcome = try codeInterpretFrame(
                                    editor,
                                    allocator,
                                    current_frame,
                                    special_frames,
                                    rept,
                                    count,
                                    span_ptr.code.?,
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
            editor.edit_mode = .mode_overtype;
            cmd_success = true;
        },
        .CmdOvertypeText => {
            if (editor.file_data.old_cmds and !from_span) {
                if (rept == .LeadParamNone) {
                    editor.edit_mode = .mode_overtype;
                    cmd_success = true;
                } else {
                    return false;
                }
            } else {
                var request: types.TParObject = .{};
                if (try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                    cmd_success = try text.textOvertype(allocator, true, count, request.str.?, request.len, current_frame.dot.?);
                    if (cmd_success and count * request.len != 0) {
                        try markModifiedAtDot(allocator, current_frame);
                    }
                }
            }
        },
        .CmdPositionColumn => {
            if (count > types.max_str_len) {
                return false;
            }
            current_frame.dot.?.col = count;
            cmd_success = true;
        },
        .CmdPositionLine => {
            const new_line = line_ops.lineFromNumber(current_frame, count) orelse return false;
            try mark_ops.markCreate(allocator, current_frame.dot.?.line, current_frame.dot.?.col, &current_frame.marks[types.mark_equals]);
            try mark_ops.markCreate(allocator, new_line, 1, &current_frame.dot);
            cmd_success = true;
        },
        .CmdOpSysCommand => {
            cmd_success = try executeOpsysCommand(editor, allocator, current_frame, tparam);
        },
        .CmdQuit => {
            if (editor.ludwig_mode != .ludwig_batch) {
                editor.ludwig_aborted = false;
                editor.quit_requested = true;
                cmd_success = true;
            } else {
                editor.ludwig_aborted = false;
                if (try file_ops.quitCloseFiles(editor, allocator)) {
                    editor.hangup = true;
                    editor.quit_requested = true;
                    cmd_success = true;
                } else {
                    cmd_success = false;
                }
            }
        },
        .CmdSplitLine => {
            if (current_frame.dot.?.line.f_link == null) {
                try text.textRealizeNull(allocator, current_frame.dot.?.line);
            }
            cmd_success = try text.textSplitLine(allocator, current_frame.dot.?, 0, &current_frame.marks[types.mark_equals]);
        },
        .CmdSwapLine => {
            cmd_success = try swap.swapLine(allocator, current_frame, rept, count);
        },
        .Cmdusercommand_introducer => {
            if (editor.ludwig_mode != .ludwig_screen) {
                return false;
            }
            cmd_success = try user_ops.userCommandIntroducer(editor, allocator, current_frame);
        },
        .CmdUserKey => {
            if (editor.ludwig_mode != .ludwig_screen) {
                return false;
            }
            var request: types.TParObject = .{};
            var request2: types.TParObject = .{};
            if (try tpar_ops.tparGet2(allocator, editor, current_frame, tparam, command, &request, &request2)) {
                if (request.len == 0) {
                    return false;
                }
                const key_code = user_ops.resolveUserKeyCode(editor, &request) orelse return false;
                const heap_frame = special_frames.heap orelse return false;
                const heap_span = heap_frame.span orelse return false;
                try mark_ops.markCreate(allocator, heap_frame.last_group.?.last_line.?, 1, &heap_span.mark_two);
                if (!try createNamedSpan(editor, allocator, types.blank_frame_name, heap_span.mark_two.?, heap_span.mark_two.?)) {
                    return false;
                }

                var key_span = (try findSpanByName(editor, allocator, types.blank_frame_name)) orelse return false;
                defer {
                    var key_span_slot: ?*types.SpanObject = key_span;
                    _ = destroyNamedSpan(editor, allocator, &key_span_slot);
                }

                if (!try text.textInsertTpar(allocator, &request2, key_span.mark_two.?, &key_span.mark_one)) {
                    return false;
                }
                if (!try codeCompile(editor, allocator, current_frame, key_span, true)) {
                    return false;
                }
                cmd_success = user_ops.bindCompiledKey(editor, key_code, key_span);
            }
        },
        .CmdUserParent, .CmdUserSubprocess => {
            cmd_success = false;
        },
        .CmdWordAdvance => {
            cmd_success = if (editor.file_data.old_cmds)
                try word.wordAdvanceWord(allocator, current_frame, rept, count)
            else
                try newword.newwordAdvanceWord(allocator, current_frame, rept, count);
        },
        .CmdWordDelete => {
            const oops = special_frames.oops orelse return false;
            cmd_success = if (editor.file_data.old_cmds)
                try word.wordDeleteWord(allocator, current_frame, oops, rept, count)
            else
                try newword.newwordDeleteWord(allocator, current_frame, oops, rept, count);
        },
        .CmdAdvanceParagraph => {
            cmd_success = try newword.newwordAdvanceParagraph(allocator, current_frame, rept, count);
        },
        .CmdDeleteParagraph => {
            const oops = special_frames.oops orelse return false;
            cmd_success = try newword.newwordDeleteParagraph(allocator, current_frame, oops, rept, count);
        },
        .CmdCommand => {
            if (rept == .LeadParamMinus) {
                if (editor.edit_mode != .mode_command) {
                    editor.previous_mode = editor.edit_mode;
                    editor.edit_mode = .mode_command;
                    cmd_success = true;
                } else {
                    return false;
                }
            } else {
                if (editor.edit_mode == .mode_command) {
                    editor.edit_mode = editor.previous_mode;
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
            cmd_success = try window_ops.windowCommand(editor, allocator, current_frame, command, rept, count, from_span);
        },
        .CmdFileRead => {
            cmd_success = try file_ops.fileReadCommand(editor, allocator, current_frame, rept, count);
        },
        .CmdFileWrite => {
            cmd_success = try file_ops.fileWriteCommand(editor, allocator, current_frame, rept, count, the_mark);
        },
        .CmdFileRewind => {
            cmd_success = try file_ops.fileRewindCommand(editor, allocator, current_frame);
        },
        .CmdFileGlobalRewind => {
            cmd_success = try file_ops.fileGlobalRewindCommand(editor, allocator);
        },
        .CmdPage => {
            cmd_success = try file_ops.filePage(editor, allocator, current_frame);
        },
        .CmdFileSave => {
            cmd_success = try file_ops.fileSaveCommand(editor, allocator, current_frame);
        },
        .CmdFileKill => {
            cmd_success = try file_ops.fileKillCommand(editor, allocator, current_frame);
        },
        .CmdFileGlobalKill => {
            cmd_success = try file_ops.fileGlobalKillCommand(editor, allocator);
        },
        .CmdFileInput,
        .CmdFileOutput,
        .CmdFileEdit,
        .CmdFileGlobalInput,
        .CmdFileGlobalOutput,
        => {
            if (rept == .LeadParamMinus) {
                cmd_success = try file_ops.fileCloseCommand(editor, allocator, current_frame, command);
            } else {
                var request: types.TParObject = .{};
                if (!try tpar_ops.tparGet1(allocator, editor, current_frame, tparam, command, &request)) {
                    return false;
                }
                const file_name = if (request.len == 0) "" else request.str.?.slice(1, request.len);
                cmd_success = try file_ops.fileOpenCommand(editor, allocator, current_frame, command, file_name);
            }
        },
        .CmdFileTable => {
            const oops = special_frames.oops orelse return false;
            cmd_success = try file_ops.fileTable(editor, allocator, oops);
        },
        .CmdValidate => {
            cmd_success = validate_ops.validateCommand(editor, current_frame, special_frames);
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
        switch (editor.cmd_attrib[cmdIndex(command)].eq_action) {
            .EqOld => try mark_ops.markCreate(allocator, old_dot.line, old_dot.col, &old_frame.marks[types.mark_equals]),
            .EqDel => mark_ops.markDestroy(allocator, &old_frame.marks[types.mark_equals]),
            .EqNil => {},
        }
    }
    return cmd_success;
}

pub fn executeSingle(
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
    return execute(editor, allocator, frame_slot, special_frames, command, rept, count, tparam, from_span);
}

pub fn codeInterpretFrame(
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
    code_head.ref += 1;
    defer codeDiscard(editor, &code_ref);
    const top_level = editor.exec_level == 0;
    if (top_level) {
        editor.quit_requested = false;
    }
    editor.exec_level += 1;
    defer editor.exec_level -= 1;

    var current_frame = frame;
    var outer_count = count;
    var verify_always = editor.initial_verify;
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
            if (pc > code_head.len) {
                return .{ .frame = current_frame, .ok = false };
            }

            interp_status = .success;
            const cc = &editor.compiler_code[@intCast(code_head.code - 1 + pc)];
            const curr_lbl = cc.lbl;
            const curr_op = cc.op;
            const curr_rep = cc.rep;
            const curr_cnt = cc.cnt;
            const curr_tpar = cc.tpar;
            const curr_code = cc.code;
            pc += 1;

            if (isInterpCmd(curr_op)) {
                switch (curr_op) {
                    .CmdPcJump => pc = curr_lbl,
                    .CmdExitTo => {
                        span_mode = true;
                        level += 1;
                        labels[level] = .{ .exit_label = curr_lbl };
                    },
                    .CmdFailTo => labels[level].fail_label = curr_lbl,
                    .CmdIterate => {
                        if (labels[level].count == curr_cnt) {
                            pc = labels[level].exit_label;
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
                        pc = labels[level + 1].exit_label;
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
                        pc = labels[level + 1].fail_label;
                    },
                    .Cmdexit_abort => {
                        editor.exit_abort = true;
                        interp_status = .fail_forever;
                        pc = 0;
                    },
                    .CmdExtended => {
                        if (curr_code == null) return .{ .frame = current_frame, .ok = false };
                        const outcome = try codeInterpretFrame(editor, allocator, current_frame, special_frames, curr_rep, curr_cnt, curr_code.?, true);
                        current_frame = outcome.frame;
                        if (!outcome.ok) {
                            interp_status = .failure;
                            pc = curr_lbl;
                        }
                    },
                    .CmdVerify => {
                        if (!verify_always[@intCast(curr_cnt)]) {
                            if (editor.ludwig_mode == .ludwig_batch) {
                                editor.exit_abort = true;
                                interp_status = .fail_forever;
                                pc = 0;
                            } else blk: {
                                var request: types.TParObject = .{};
                                if (!try tpar_ops.tparGet1(allocator, editor, current_frame, curr_tpar, .CmdVerify, &request)) {
                                    break :blk;
                                }
                                if (request.len == 0) {
                                    request = current_frame.verify_tpar;
                                    if (request.len == 0) {
                                        return .{ .frame = current_frame, .ok = false };
                                    }
                                } else {
                                    current_frame.verify_tpar = request;
                                }

                                switch (request.str.?.get(1)) {
                                    'Y' => {},
                                    'A' => verify_always[@intCast(curr_cnt)] = true,
                                    'Q' => {
                                        editor.exit_abort = true;
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
                const ok = try execute(editor, allocator, &current_frame, special_frames, curr_op, curr_rep, curr_cnt, curr_tpar, span_mode);
                if (!ok) {
                    interp_status = .failure;
                    pc = curr_lbl;
                }
                if (editor.exit_abort) {
                    interp_status = .fail_forever;
                    pc = 0;
                }
            }

            if (editor.quit_requested) {
                interp_status = .success;
                pc = 0;
            }
            if (editor.tt_control_c) {
                interp_status = .fail_forever;
                pc = 0;
            }
            if (interp_status == .failure) {
                while (pc == 0 and level >= 1) {
                    pc = labels[level].fail_label;
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

pub fn codeInterpret(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    special_frames: *types.SpecialFrames,
    rept: types.LeadParam,
    count: isize,
    code_head: *types.CodeHeader,
    from_span: bool,
) anyerror!bool {
    return (try codeInterpretFrame(editor, allocator, frame, special_frames, rept, count, code_head, from_span)).ok;
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
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 1, &mark_one);
    const last = fixture.content_lines[contents.len - 1];
    try mark_ops.markCreate(allocator, last, last.used + 1, &mark_two);
    const span = try allocator.create(types.SpanObject);
    span.* = .{
        .name = "CMD",
        .mark_one = mark_one,
        .mark_two = mark_two,
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
        .name = name,
        .frame = fixture.frame,
    };
    fixture.frame.span = span;
    try mark_ops.markCreate(allocator, fixture.frame.first_group.?.first_line.?, 1, &span.mark_one);
    try mark_ops.markCreate(allocator, fixture.frame.last_group.?.last_line.?, 1, &span.mark_two);
    return fixture;
}

fn expectFrameLines(frame: *types.FrameObject, expected: []const []const u8) !void {
    const sentinel = frame.last_group.?.last_line.?;
    var line = frame.first_group.?.first_line.?;
    for (expected) |content| {
        try std.testing.expect(line != sentinel);
        try std.testing.expectEqualStrings(content, line_ops.getLineContent(line));
        line = line.f_link.?;
    }
    try std.testing.expect(line == sentinel);
}

fn makeBufferedFile(
    allocator: std.mem.Allocator,
    contents: []const []const u8,
    output_flag: bool,
) !*types.FileObject {
    return file_ops.makeBufferedFile(allocator, contents, output_flag);
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

    var advance_span = types.SpanObject{ .name = "ADV" };
    try std.testing.expect(try codeCompileString(&editor, allocator, &advance_span, "A"));
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, advance_span.code.?, false));
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[1]);

    var mode_span = types.SpanObject{ .name = "MODE" };
    editor.edit_mode = .mode_insert;
    try std.testing.expect(try codeCompileString(&editor, allocator, &mode_span, "O"));
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, mode_span.code.?, false));
    try std.testing.expectEqual(types.ModeType.mode_overtype, editor.edit_mode);

    var prompt_span = types.SpanObject{ .name = "PROMPT" };
    try std.testing.expect(try codeCompileString(&editor, allocator, &prompt_span, "R"));
    const compiled = &editor.compiler_code[@intCast(prompt_span.code.?.code)];
    try std.testing.expectEqual(types.Commands.CmdReplace, compiled.op);
    try std.testing.expect(compiled.tpar != null);
    try std.testing.expectEqual(types.tpd_prompt, compiled.tpar.?.dlm);
    try std.testing.expect(compiled.tpar.?.nxt != null);
    try std.testing.expectEqual(types.tpd_prompt, compiled.tpar.?.nxt.?.dlm);
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

    var immediate_span = types.SpanObject{ .name = "IMM" };
    try editor.setImmediateInput("A");
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, &immediate_span, false));
    try std.testing.expect(editor.immediate_input == null);
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, immediate_span.code.?, false));
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[1]);
}

test "code compile can consume live interactive input" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.ludwig_mode = .ludwig_screen;

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});

    var live_span = types.SpanObject{ .name = "LIVE" };
    interactive_io.testing.installInput("A");
    defer interactive_io.testing.clearInput();

    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, &live_span, false));
    const compiled = &editor.compiler_code[@intCast(live_span.code.?.code)];
    try std.testing.expectEqual(types.Commands.CmdAdvance, compiled.op);
}

test "code compile live input accepts special keys as commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.ludwig_mode = .ludwig_screen;
    try user_ops.userKeyInitialize(&editor, allocator);

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});

    var live_span = types.SpanObject{ .name = "LIVE" };
    interactive_io.testing.installInput("\x1b[6~");
    defer interactive_io.testing.clearInput();

    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, &live_span, false));
    const compiled = &editor.compiler_code[@intCast(live_span.code.?.code)];
    try std.testing.expectEqual(types.Commands.CmdWindowForward, compiled.op);
}

test "code compile live input supports prefix commands with prompted parameters" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.ludwig_mode = .ludwig_screen;

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});
    var live_span = types.SpanObject{ .name = "LIVE" };
    interactive_io.testing.installInput("EPc=/\r");
    defer interactive_io.testing.clearInput();

    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, &live_span, false));
    const compiled = &editor.compiler_code[@intCast(live_span.code.?.code)];
    try std.testing.expectEqual(types.Commands.CmdFrameParameters, compiled.op);
    try std.testing.expect(compiled.tpar != null);
    try std.testing.expectEqual(types.tpd_prompt, compiled.tpar.?.dlm);
    try std.testing.expectEqual(@as(?u8, 'c'), try interactive_io.readKey());
}

test "code compile false preserves immediate prompt placeholders" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});
    var prompt_span = types.SpanObject{ .name = "PROMPT" };
    try editor.setImmediateInput("R");
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, &prompt_span, false));
    const compiled = &editor.compiler_code[@intCast(prompt_span.code.?.code)];
    try std.testing.expectEqual(types.Commands.CmdReplace, compiled.op);
    try std.testing.expect(compiled.tpar != null);
    try std.testing.expectEqual(types.tpd_prompt, compiled.tpar.?.dlm);
    try std.testing.expect(compiled.tpar.?.nxt != null);
    try std.testing.expectEqual(types.tpd_prompt, compiled.tpar.?.nxt.?.dlm);
}

test "code interpreter can insert spaces with insert char command" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"ab"});
    try mark_ops.markCreate(allocator, target.content_lines[0], 2, &target.frame.dot);

    const command = try makeCommandSpan(allocator, &[_][]const u8{"2C"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqualStrings("a  b", line_ops.getLineContent(target.content_lines[0]));
    try std.testing.expectEqual(@as(isize, 2), target.frame.dot.?.col);
    try std.testing.expectEqual(@as(isize, 4), target.frame.marks[types.mark_equals].?.col);
}

test "code interpreter can delete a marked character range into oops" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"abcdef"});
    try mark_ops.markCreate(allocator, target.content_lines[0], 5, &target.frame.dot);
    try mark_ops.markCreate(allocator, target.content_lines[0], 2, &target.frame.marks[1]);

    const oops = try makeSpecialFrame(allocator, "OOPS", &[_][]const u8{""});
    var special_frames: types.SpecialFrames = .{
        .oops = oops.frame,
    };

    const command = try makeCommandSpan(allocator, &[_][]const u8{"@1D"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{"aef"});
    try std.testing.expectEqualStrings("bcd", line_ops.getLineContent(oops.frame.last_group.?.last_line.?.b_link));
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
    try mark_ops.markCreate(allocator, target.content_lines[1], 2, &target.frame.dot);

    const oops = try makeSpecialFrame(allocator, "OOPS", &[_][]const u8{""});
    var special_frames: types.SpecialFrames = .{
        .oops = oops.frame,
    };

    const command = try makeCommandSpan(allocator, &[_][]const u8{"K"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{
        "one",
        "three",
    });
    try std.testing.expectEqualStrings("two", line_ops.getLineContent(oops.frame.last_group.?.last_line.?.b_link));
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[2]);
    try std.testing.expectEqual(@as(isize, 2), target.frame.dot.?.col);
}

test "code interpreter can jump by character count" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"abcdef"});
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);

    const command = try makeCommandSpan(allocator, &[_][]const u8{"2J"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 3), target.frame.dot.?.col);
    try std.testing.expectEqual(@as(isize, 1), target.frame.marks[types.mark_equals].?.col);
}

test "code interpreter can centre a line" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"cat"});
    target.frame.margin_left = 1;
    target.frame.margin_right = 10;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"YC"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqualStrings("   cat", line_ops.getLineContent(target.content_lines[0]));
}

test "code interpreter can set margins from dot" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"abcdef"});
    try mark_ops.markCreate(allocator, target.content_lines[0], 3, &target.frame.dot);

    const left_command = try makeCommandSpan(allocator, &[_][]const u8{"{"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, left_command.span, true));
    try std.testing.expect((try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, left_command.span.code.?, true)).ok);
    try std.testing.expectEqual(@as(isize, 3), target.frame.margin_left);

    try mark_ops.markCreate(allocator, target.content_lines[0], 5, &target.frame.dot);
    const right_command = try makeCommandSpan(allocator, &[_][]const u8{"}"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, right_command.span, true));
    try std.testing.expect((try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, right_command.span.code.?, true)).ok);
    try std.testing.expectEqual(@as(isize, 5), target.frame.margin_right);
}

test "code interpreter can report help topics into oops frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const current = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const oops = try makeSpecialFrame(allocator, "OOPS", &[_][]const u8{""});
    var special_frames: types.SpecialFrames = .{
        .oops = oops.frame,
    };

    const command = try makeCommandSpan(allocator, &[_][]const u8{"H/Q/"});
    try std.testing.expect(try codeCompile(&editor, allocator, current.frame, command.span, true));

    const outcome = try codeInterpretFrame(&editor, allocator, current.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(outcome.frame == current.frame);

    const first = oops.frame.first_group.?.first_line.?;
    try std.testing.expectEqualStrings("Q       QUIT", line_ops.getLineContent(first));
    try std.testing.expectEqualStrings("=       ====", line_ops.getLineContent(first.f_link));
}

test "code interpreter can insert opsys command output into frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.loadCommandTable(false);
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"tail"});
    const command = try makeCommandSpan(allocator, &[_][]const u8{"OX|printf \"alpha\\nbeta\\n\"|"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));

    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{
        "alpha",
        "beta",
        "tail",
    });
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[0]);
    try std.testing.expectEqual(@as(isize, 1), target.frame.dot.?.col);
    try std.testing.expectEqualStrings("alpha", line_ops.getLineContent(target.frame.marks[types.mark_equals].?.line));
}

test "code interpreter captures opsys stderr with tab expansion" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.loadCommandTable(false);
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"tail"});
    const command = try makeCommandSpan(allocator, &[_][]const u8{"OX|printf \"\\tX\\n\" >&2|"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));

    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
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
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);

    const command = try makeCommandSpan(allocator, &[_][]const u8{"EQS/hello/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    var special_frames: types.SpecialFrames = .{};
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true));
    try std.testing.expectEqual(@as(isize, 6), target.frame.marks[types.mark_equals].?.col);
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
    try mark_ops.markCreate(allocator, success_target.content_lines[0], 1, &success_target.frame.dot);
    const success_cmd = try makeCommandSpan(allocator, &[_][]const u8{"G/world/[A]"});
    try std.testing.expect(try codeCompile(&editor, allocator, success_target.frame, success_cmd.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, success_target.frame, &special_frames, .LeadParamNone, 1, success_cmd.span.code.?, true));
    try std.testing.expect(success_target.frame.dot.?.line == success_target.content_lines[1]);

    const fail_target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "hello world",
        "second",
    });
    try mark_ops.markCreate(allocator, fail_target.content_lines[0], 1, &fail_target.frame.dot);
    const fail_cmd = try makeCommandSpan(allocator, &[_][]const u8{"G/missing/[:A]"});
    try std.testing.expect(try codeCompile(&editor, allocator, fail_target.frame, fail_cmd.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, fail_target.frame, &special_frames, .LeadParamNone, 1, fail_cmd.span.code.?, true));
    try std.testing.expect(fail_target.frame.dot.?.line == fail_target.content_lines[1]);
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
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);
    const command = try makeCommandSpan(allocator, &[_][]const u8{"2(A)"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    var special_frames: types.SpecialFrames = .{};
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true));
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[2]);
}

test "code interpreter executes compiled arrow and insert text commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "hello",
        "second",
    });
    try mark_ops.markCreate(allocator, target.content_lines[1], 1, &target.frame.dot);
    const command = try makeCommandSpan(allocator, &[_][]const u8{"ZU I/abc/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    var special_frames: types.SpecialFrames = .{};
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true));
    try std.testing.expectEqualStrings("abchello", line_ops.getLineContent(target.content_lines[0]));
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[0]);
    try std.testing.expectEqual(@as(isize, 4), target.frame.dot.?.col);
}

test "code interpreter executes span assign with heap and oops special frames" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const current = try line_ops.createContentFrame(allocator, &[_][]const u8{"ignored"});
    const oops = try makeSpecialFrame(allocator, "OOPS", &[_][]const u8{""});
    const heap = try makeSpecialFrame(allocator, "HEAP", &[_][]const u8{""});
    var special_frames: types.SpecialFrames = .{
        .oops = oops.frame,
        .heap = heap.frame,
    };

    const source = try line_ops.createContentFrame(allocator, &[_][]const u8{"stale"});
    var source_mark_one: ?*types.MarkObject = null;
    var source_mark_two: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, source.content_lines[0], 1, &source_mark_one);
    try mark_ops.markCreate(allocator, source.content_lines[0], 6, &source_mark_two);
    try std.testing.expect(try span_ops.spanCreate(&editor, allocator, "NAME", source_mark_one.?, source_mark_two.?));

    const assign_existing = try makeCommandSpan(allocator, &[_][]const u8{"SA/NAME/new/"});
    try std.testing.expect(try codeCompile(&editor, allocator, current.frame, assign_existing.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, current.frame, &special_frames, .LeadParamNone, 1, assign_existing.span.code.?, true));

    const assigned_span = (try findSpanByName(&editor, allocator, "NAME")) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("new", line_ops.getLineContent(assigned_span.mark_one.?.line));
    try std.testing.expectEqualStrings("stale", line_ops.getLineContent(oops.frame.last_group.?.last_line.?.b_link));

    const assign_new = try makeCommandSpan(allocator, &[_][]const u8{"SA/NEW/alpha/"});
    try std.testing.expect(try codeCompile(&editor, allocator, current.frame, assign_new.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, current.frame, &special_frames, .LeadParamNone, 1, assign_new.span.code.?, true));

    const new_span = (try findSpanByName(&editor, allocator, "NEW")) orelse return error.TestUnexpectedResult;
    try std.testing.expect(new_span.mark_one.?.line.group.?.frame == heap.frame);
    try std.testing.expectEqualStrings("alpha", line_ops.getLineContent(new_span.mark_one.?.line));
}

test "code interpreter executes span define jump and destroy commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"hello world"});
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.marks[1]);
    try mark_ops.markCreate(allocator, target.content_lines[0], 6, &target.frame.dot);

    const define_command = try makeCommandSpan(allocator, &[_][]const u8{"SD/TEST/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, define_command.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, define_command.span.code.?, true));

    const defined_span = (try findSpanByName(&editor, allocator, "TEST")) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(isize, 1), defined_span.mark_one.?.col);
    try std.testing.expectEqual(@as(isize, 6), defined_span.mark_two.?.col);

    try mark_ops.markCreate(allocator, target.content_lines[0], 11, &target.frame.dot);
    const jump_command = try makeCommandSpan(allocator, &[_][]const u8{"-SJ/TEST/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, jump_command.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, jump_command.span.code.?, true));
    try std.testing.expectEqual(@as(isize, 1), target.frame.dot.?.col);

    const destroy_command = try makeCommandSpan(allocator, &[_][]const u8{"-SD/TEST/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, destroy_command.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, destroy_command.span.code.?, true));
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
        .cmd = cmd_frame.frame,
    };
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);

    const exec_command = try makeCommandSpan(allocator, &[_][]const u8{"^/AA/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, exec_command.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, exec_command.span.code.?, true));
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[2]);
    try std.testing.expect(cmd_frame.frame.span.?.code != null);

    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);
    const repeat_command = try makeCommandSpan(allocator, &[_][]const u8{"\x07"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, repeat_command.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, repeat_command.span.code.?, true));
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[2]);
}

test "code interpreter can edit and return frames" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const origin = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});

    const edit_command = try makeCommandSpan(allocator, &[_][]const u8{"ED/WORK/"});
    try std.testing.expect(try codeCompile(&editor, allocator, origin.frame, edit_command.span, true));
    const edit_outcome = try codeInterpretFrame(&editor, allocator, origin.frame, &special_frames, .LeadParamNone, 1, edit_command.span.code.?, true);
    try std.testing.expect(edit_outcome.ok);
    try std.testing.expect(edit_outcome.frame != origin.frame);
    try std.testing.expectEqualStrings("WORK", edit_outcome.frame.span.?.name);
    try std.testing.expect(edit_outcome.frame.return_frame == origin.frame);

    const return_command = try makeCommandSpan(allocator, &[_][]const u8{"ER"});
    try std.testing.expect(try codeCompile(&editor, allocator, edit_outcome.frame, return_command.span, true));
    const return_outcome = try codeInterpretFrame(&editor, allocator, edit_outcome.frame, &special_frames, .LeadParamNone, 1, return_command.span.code.?, true);
    try std.testing.expect(return_outcome.ok);
    try std.testing.expect(return_outcome.frame == origin.frame);
}

test "code interpreter can kill another frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const origin = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    _ = (try frame_ops.frameEdit(&editor, allocator, origin.frame, "WORK")).?;

    const kill_command = try makeCommandSpan(allocator, &[_][]const u8{"EK/WORK/"});
    try std.testing.expect(try codeCompile(&editor, allocator, origin.frame, kill_command.span, true));
    const kill_outcome = try codeInterpretFrame(&editor, allocator, origin.frame, &special_frames, .LeadParamNone, 1, kill_command.span.code.?, true);
    try std.testing.expect(kill_outcome.ok);
    try std.testing.expect(kill_outcome.frame == origin.frame);
    try std.testing.expect((try findSpanByName(&editor, allocator, "WORK")) == null);
}

test "code interpreter can apply frame parameters" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.terminal_info = .{ .width = 160, .height = 48 };
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    const param_command = try makeCommandSpan(allocator, &[_][]const u8{"EP/K=O,H=24,W=100,O=(I,-N)/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, param_command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, param_command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(types.ModeType.mode_overtype, editor.edit_mode);
    try std.testing.expectEqual(@as(isize, 24), target.frame.scr_height);
    try std.testing.expectEqual(@as(isize, 100), target.frame.scr_width);
    try std.testing.expect(target.frame.options.autoIndent);
    try std.testing.expect(!target.frame.options.newLine);
}

test "code interpreter can validate linked frame/span state" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.terminal_info = .{ .width = 160, .height = 48 };
    const allocator = editor.allocator();

    const root_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const current = (try frame_ops.frameEdit(&editor, allocator, root_fixture.frame, "MAIN")).?;
    const cmd = (try frame_ops.frameEdit(&editor, allocator, current, "COMMAND")).?;
    const oops = (try frame_ops.frameEdit(&editor, allocator, current, "OOPS")).?;
    const heap = (try frame_ops.frameEdit(&editor, allocator, current, "HEAP")).?;
    cmd.options.specialFrame = true;
    oops.options.specialFrame = true;
    heap.options.specialFrame = true;
    var special_frames: types.SpecialFrames = .{
        .cmd = cmd,
        .oops = oops,
        .heap = heap,
    };

    var span_mark_one: ?*types.MarkObject = null;
    var span_mark_two: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, current.first_group.?.first_line.?, 1, &span_mark_one);
    try mark_ops.markCreate(allocator, current.last_group.?.last_line.?, 1, &span_mark_two);
    try std.testing.expect(try span_ops.spanCreate(&editor, allocator, "WORK", span_mark_one.?, span_mark_two.?));

    const validate_command = try makeCommandSpan(allocator, &[_][]const u8{"~V"});
    try std.testing.expect(try codeCompile(&editor, allocator, current, validate_command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, current, &special_frames, .LeadParamNone, 1, validate_command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(outcome.frame == current);
}

test "code interpreter can insert user command introducer in screen mode" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.ludwig_mode = .ludwig_screen;
    editor.command_introducer = '@';
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"ab"});
    try mark_ops.markCreate(allocator, target.content_lines[0], 2, &target.frame.dot);

    const command = try makeCommandSpan(allocator, &[_][]const u8{"UC"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqualStrings("a@b", line_ops.getLineContent(target.content_lines[0]));
}

test "code interpreter can bind simple user key commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.ludwig_mode = .ludwig_screen;
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    const heap = (try frame_ops.frameEdit(&editor, allocator, target.frame, "HEAP")).?;
    heap.options.specialFrame = true;
    var special_frames: types.SpecialFrames = .{
        .heap = heap,
    };

    const command = try makeCommandSpan(allocator, &[_][]const u8{"UK/A/A/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(types.Commands.CmdAdvance, editor.lookup['A'].command);
    try std.testing.expect(editor.lookup['A'].code == null);
    try std.testing.expect(editor.lookup['A'].tpar == null);
}

test "code interpreter can bind extended user key commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.ludwig_mode = .ludwig_screen;
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    const heap = (try frame_ops.frameEdit(&editor, allocator, target.frame, "HEAP")).?;
    heap.options.specialFrame = true;
    var special_frames: types.SpecialFrames = .{
        .heap = heap,
    };

    const command = try makeCommandSpan(allocator, &[_][]const u8{"UK/B/A A/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(types.Commands.CmdExtended, editor.lookup['B'].command);
    try std.testing.expect(editor.lookup['B'].code != null);
    try std.testing.expect(editor.lookup['B'].tpar == null);
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
    target.frame.scr_height = 2;
    try mark_ops.markCreate(allocator, target.content_lines[2], 1, &target.frame.dot);

    const command = try makeCommandSpan(allocator, &[_][]const u8{"WF"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[4]);
    try std.testing.expect(target.frame.marks[types.mark_equals] != null);
    try std.testing.expect(target.frame.marks[types.mark_equals].?.line == target.content_lines[2]);
}

test "code interpreter can apply window height command" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    editor.terminal_info = .{ .width = 120, .height = 24 };
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"one"});
    const command = try makeCommandSpan(allocator, &[_][]const u8{"WH"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 24), target.frame.scr_height);
}

test "code interpreter can read from the global input file buffer" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"tail"});
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);

    const input_file = try makeBufferedFile(allocator, &[_][]const u8{
        "alpha",
        "beta",
    }, false);
    input_file.eof = true;
    editor.files[1] = input_file;
    editor.fgi_file = 1;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"2FGR"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{
        "alpha",
        "beta",
        "tail",
    });
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[0]);
    try std.testing.expect(target.frame.marks[types.mark_equals] != null);
    try std.testing.expectEqualStrings("alpha", line_ops.getLineContent(target.frame.marks[types.mark_equals].?.line));
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
    try mark_ops.markCreate(allocator, target.content_lines[1], 1, &target.frame.dot);

    const output_file = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    editor.files[1] = output_file;
    editor.fgo_file = 1;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FGW"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 1), output_file.line_count);
    try std.testing.expectEqualStrings("two", line_ops.getLineContent(output_file.first_line));
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
    try mark_ops.markCreate(allocator, target.content_lines[1], 1, &target.frame.dot);

    const input_file = try makeBufferedFile(allocator, &[_][]const u8{
        "new1",
        "new2",
    }, false);
    input_file.eof = true;
    editor.files[1] = input_file;
    editor.files_frames[1] = target.frame;
    target.frame.input_file = 1;

    const output_file = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    editor.files[2] = output_file;
    editor.files_frames[2] = target.frame;
    target.frame.output_file = 2;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FP"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{
        "old2",
        "new1",
        "new2",
    });
    try std.testing.expectEqualStrings("old1", line_ops.getLineContent(output_file.first_line));
    try std.testing.expectEqualStrings("<End of File>", line_ops.getDisplayLineContent(target.frame.last_group.?.last_line.?));
}

test "code interpreter can rewind attached input file buffer" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"stale"});
    try mark_ops.markCreate(allocator, target.frame.last_group.?.last_line.?, 1, &target.frame.dot);

    const input_file = try makeBufferedFile(allocator, &[_][]const u8{
        "alpha",
        "beta",
    }, false);
    input_file.first_line = null;
    input_file.last_line = null;
    input_file.line_count = 0;
    input_file.eof = true;
    editor.files[1] = input_file;
    editor.files_frames[1] = target.frame;
    target.frame.input_file = 1;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FB"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{
        "alpha",
        "beta",
    });
    try std.testing.expectEqual(@as(isize, 0), input_file.line_count);
    try std.testing.expectEqualStrings("<End of File>", line_ops.getDisplayLineContent(target.frame.last_group.?.last_line.?));
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
    input_file.first_line = null;
    input_file.last_line = null;
    input_file.line_count = 0;
    input_file.eof = true;
    editor.files[1] = input_file;
    editor.fgi_file = 1;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FGB"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 2), input_file.line_count);
    try std.testing.expect(!input_file.eof);
    try std.testing.expectEqualStrings("alpha", line_ops.getLineContent(input_file.first_line));
}

test "code interpreter can execute a buffered file into the command frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
    });
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);

    const cmd_frame = try makeSpecialFrame(allocator, "COMMAND", &[_][]const u8{"old"});
    var special_frames: types.SpecialFrames = .{
        .cmd = cmd_frame.frame,
    };

    const source_file = try makeBufferedFile(allocator, &[_][]const u8{"A"}, false);
    source_file.filename = "proc.lud";
    editor.files[1] = source_file;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FX/proc.lud/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[1]);
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
    const target = (try frame_ops.frameEdit(&editor, allocator, root.frame, "WORK")).?;

    const open_text = try commandWithPath(allocator, "FI", path, "");
    const command = try makeCommandSpan(allocator, &[_][]const u8{open_text});
    try std.testing.expect(try codeCompile(&editor, allocator, target, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target, &[_][]const u8{
        "alpha",
        "beta",
    });
    try std.testing.expect(target.input_file != 0);
    const expanded = (try sys_ops.expandFilename(allocator, path)) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(expanded, editor.files[@intCast(target.input_file)].?.filename);
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
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);

    const command_text = try commandWithPath(allocator, "FGI", path, " 2FGR -FGI||");
    const command = try makeCommandSpan(allocator, &[_][]const u8{command_text});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target.frame, &[_][]const u8{
        "alpha",
        "beta",
        "tail",
    });
    try std.testing.expectEqual(@as(isize, 0), editor.fgi_file);
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
    const target = (try frame_ops.frameEdit(&editor, allocator, root.frame, "WORK")).?;

    const command_text = try commandWithPath(allocator, "FE", path, " I/edited / -FE||");
    const command = try makeCommandSpan(allocator, &[_][]const u8{command_text});
    try std.testing.expect(try codeCompile(&editor, allocator, target, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try expectFrameLines(target, &[_][]const u8{"edited alpha"});
    try std.testing.expectEqual(@as(isize, 0), target.input_file);
    try std.testing.expectEqual(@as(isize, 0), target.output_file);

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
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);

    const command_text = try commandWithPath(allocator, "FGO", path, " FGW -FGO||");
    const command = try makeCommandSpan(allocator, &[_][]const u8{command_text});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 0), editor.fgo_file);

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
    const target = (try frame_ops.frameEdit(&editor, allocator, root.frame, "WORK")).?;

    const edit_command = try commandWithPath(allocator, "FE", edit_path, " I/edited /");
    const global_command = try commandWithPath(allocator, "FGO", global_path, " FGW Q I/ignored/");
    const command_text = try std.fmt.allocPrint(allocator, "{s} {s}", .{ edit_command, global_command });
    const command = try makeCommandSpan(allocator, &[_][]const u8{command_text});
    try std.testing.expect(try codeCompile(&editor, allocator, target, command.span, true));

    const outcome = try codeInterpretFrame(&editor, allocator, target, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(outcome.frame == target);
    try std.testing.expect(editor.quit_requested);
    try std.testing.expect(editor.hangup);
    try std.testing.expectEqual(@as(isize, 0), target.input_file);
    try std.testing.expectEqual(@as(isize, 0), target.output_file);
    try std.testing.expectEqual(@as(isize, 0), editor.fgo_file);
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
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);

    const cmd_frame = try makeSpecialFrame(allocator, "COMMAND", &[_][]const u8{"old"});
    var special_frames: types.SpecialFrames = .{
        .cmd = cmd_frame.frame,
    };

    const command_text = try commandWithPath(allocator, "FX", path, "");
    const command = try makeCommandSpan(allocator, &[_][]const u8{command_text});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[1]);
    try expectFrameLines(cmd_frame.frame, &[_][]const u8{"A"});
}

test "code interpreter can save to attached output file buffer" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"visible"});
    const output_file = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    editor.files[1] = output_file;
    editor.files_frames[1] = target.frame;
    target.frame.output_file = 1;
    target.frame.text_modified = true;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FS"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expect(!target.frame.text_modified);
    try std.testing.expectEqual(@as(isize, 1), output_file.line_count);
    try std.testing.expectEqualStrings("visible", line_ops.getLineContent(output_file.first_line));
}

test "code interpreter can kill attached output file buffer" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"visible"});
    const output_file = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    editor.files[1] = output_file;
    editor.files_frames[1] = target.frame;
    target.frame.output_file = 1;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FK"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 0), target.frame.output_file);
    try std.testing.expect(editor.files[1] == null);
}

test "code interpreter can close attached input file with empty parameter" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"visible"});
    const input_file = try makeBufferedFile(allocator, &[_][]const u8{"tail"}, false);
    editor.files[1] = input_file;
    editor.files_frames[1] = target.frame;
    target.frame.input_file = 1;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"-FI//"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
    try std.testing.expect(outcome.ok);
    try std.testing.expectEqual(@as(isize, 0), target.frame.input_file);
    try std.testing.expect(editor.files[1] == null);
    try std.testing.expectEqualStrings("<End of File>", line_ops.getDisplayLineContent(target.frame.last_group.?.last_line.?));
}

test "code interpreter can table files into oops frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const root = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const current = (try frame_ops.frameEdit(&editor, allocator, root.frame, "WORK")).?;
    const oops = (try frame_ops.frameEdit(&editor, allocator, current, "OOPS")).?;
    oops.options.specialFrame = true;
    var special_frames: types.SpecialFrames = .{
        .oops = oops,
    };

    const input = try allocator.create(types.FileObject);
    input.* = .{
        .filename = "input.txt",
        .eof = true,
    };
    editor.files[1] = input;
    editor.files_frames[1] = current;
    current.input_file = 1;
    current.text_modified = true;

    const command = try makeCommandSpan(allocator, &[_][]const u8{"FT"});
    try std.testing.expect(try codeCompile(&editor, allocator, current, command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, current, &special_frames, .LeadParamNone, 1, command.span.code.?, true);
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
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &mark_one);
    try mark_ops.markCreate(allocator, target.content_lines[0], 6, &mark_two);
    try std.testing.expect(try span_ops.spanCreate(&editor, allocator, "NAME", mark_one.?, mark_two.?));

    const oops = (try frame_ops.frameEdit(&editor, allocator, target.frame, "OOPS")).?;
    oops.options.specialFrame = true;
    var special_frames: types.SpecialFrames = .{
        .oops = oops,
    };

    const index_command = try makeCommandSpan(allocator, &[_][]const u8{"SI"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, index_command.span, true));
    const outcome = try codeInterpretFrame(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, index_command.span.code.?, true);
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
    const other = (try frame_ops.frameEdit(&editor, allocator, origin.frame, "OTHER")).?;
    try text.textRealizeNull(allocator, other.last_group.?.last_line.?);
    const content_line = other.last_group.?.last_line.?.b_link.?;
    try line_ops.lineChangeLength(allocator, content_line, 4);
    try line_ops.setLineContent(content_line, "dest");
    var span_mark_one: ?*types.MarkObject = null;
    var span_mark_two: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, content_line, 1, &span_mark_one);
    try mark_ops.markCreate(allocator, content_line, 5, &span_mark_two);
    try std.testing.expect(try span_ops.spanCreate(&editor, allocator, "DEST", span_mark_one.?, span_mark_two.?));

    const jump_command = try makeCommandSpan(allocator, &[_][]const u8{"SJ/DEST/"});
    try std.testing.expect(try codeCompile(&editor, allocator, origin.frame, jump_command.span, true));
    const jump_outcome = try codeInterpretFrame(&editor, allocator, origin.frame, &special_frames, .LeadParamNone, 1, jump_command.span.code.?, true);
    try std.testing.expect(jump_outcome.ok);
    try std.testing.expect(jump_outcome.frame == other);
    try std.testing.expect(jump_outcome.frame.dot.?.line == content_line);
    try std.testing.expectEqual(@as(isize, 5), jump_outcome.frame.dot.?.col);
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
        .cmd = cmd_frame.frame,
    };
    cmd_frame.frame.span.?.code = null;
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);

    const repeat_command = try makeCommandSpan(allocator, &[_][]const u8{"\x07"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, repeat_command.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, repeat_command.span.code.?, true));
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[1]);
}

test "code interpreter executes named span compile and execute variants" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var special_frames: types.SpecialFrames = .{};

    const command_source = try makeCommandSpan(allocator, &[_][]const u8{"A"});
    try std.testing.expect(try span_ops.spanCreate(&editor, allocator, "CMD", command_source.span.mark_one.?, command_source.span.mark_two.?));

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "one",
        "two",
        "three",
    });
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);

    const compile_command = try makeCommandSpan(allocator, &[_][]const u8{"SR/CMD/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, compile_command.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, compile_command.span.code.?, true));
    const compiled_span = (try findSpanByName(&editor, allocator, "CMD")) orelse return error.TestUnexpectedResult;
    try std.testing.expect(compiled_span.code != null);

    try line_ops.setLineContent(command_source.fixture.content_lines[0], "2A");
    try mark_ops.markCreate(allocator, compiled_span.mark_two.?.line, 3, &compiled_span.mark_two);

    const no_recompile_command = try makeCommandSpan(allocator, &[_][]const u8{"EN/CMD/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, no_recompile_command.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, no_recompile_command.span.code.?, true));
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[1]);

    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);
    const execute_command = try makeCommandSpan(allocator, &[_][]const u8{"EX/CMD/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, execute_command.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, execute_command.span.code.?, true));
    try std.testing.expect(target.frame.dot.?.line == target.content_lines[2]);
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
    try mark_ops.markCreate(allocator, copy_target.content_lines[0], 1, &span_start);
    try mark_ops.markCreate(allocator, copy_target.content_lines[0], 6, &span_end);
    try std.testing.expect(try span_ops.spanCreate(&editor, allocator, "COPY", span_start.?, span_end.?));
    try mark_ops.markCreate(allocator, copy_target.content_lines[1], 1, &copy_target.frame.dot);

    const copy_command = try makeCommandSpan(allocator, &[_][]const u8{"SC/COPY/"});
    try std.testing.expect(try codeCompile(&editor, allocator, copy_target.frame, copy_command.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, copy_target.frame, &special_frames, .LeadParamNone, 1, copy_command.span.code.?, true));
    try std.testing.expectEqualStrings("hello", line_ops.getLineContent(copy_target.content_lines[0]));
    try std.testing.expectEqualStrings("hellotarget", line_ops.getLineContent(copy_target.content_lines[1]));

    const transfer_target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "hello",
        "target",
    });
    span_start = null;
    span_end = null;
    try mark_ops.markCreate(allocator, transfer_target.content_lines[0], 1, &span_start);
    try mark_ops.markCreate(allocator, transfer_target.content_lines[0], 6, &span_end);
    try std.testing.expect(try span_ops.spanCreate(&editor, allocator, "MOVE", span_start.?, span_end.?));
    try mark_ops.markCreate(allocator, transfer_target.content_lines[1], 1, &transfer_target.frame.dot);

    const transfer_command = try makeCommandSpan(allocator, &[_][]const u8{"ST/MOVE/"});
    try std.testing.expect(try codeCompile(&editor, allocator, transfer_target.frame, transfer_command.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, transfer_target.frame, &special_frames, .LeadParamNone, 1, transfer_command.span.code.?, true));
    try std.testing.expectEqualStrings("", line_ops.getLineContent(transfer_target.content_lines[0]));
    try std.testing.expectEqualStrings("hellotarget", line_ops.getLineContent(transfer_target.content_lines[1]));
    const moved_span = (try findSpanByName(&editor, allocator, "MOVE")) orelse return error.TestUnexpectedResult;
    try std.testing.expect(moved_span.mark_one.?.line == transfer_target.content_lines[1]);
    try std.testing.expectEqual(@as(isize, 1), moved_span.mark_one.?.col);
}

test "code interpreter executes compiled split line and equal-eol commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const split_target = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "hello world",
        "second",
    });
    try mark_ops.markCreate(allocator, split_target.content_lines[0], 6, &split_target.frame.dot);
    const split_command = try makeCommandSpan(allocator, &[_][]const u8{"SL"});
    try std.testing.expect(try codeCompile(&editor, allocator, split_target.frame, split_command.span, true));
    var special_frames: types.SpecialFrames = .{};
    try std.testing.expect(try codeInterpret(&editor, allocator, split_target.frame, &special_frames, .LeadParamNone, 1, split_command.span.code.?, true));
    const inserted_line = split_target.content_lines[0].f_link.?;
    try std.testing.expectEqualStrings("hello", line_ops.getLineContent(split_target.content_lines[0]));
    try std.testing.expectEqualStrings(" world", line_ops.getLineContent(inserted_line));
    try std.testing.expectEqualStrings("second", line_ops.getLineContent(inserted_line.f_link));
    try line_ops.validateFrameShape(split_target.frame);

    const eql_target = try line_ops.createContentFrame(allocator, &[_][]const u8{"abc"});
    try mark_ops.markCreate(allocator, eql_target.content_lines[0], 4, &eql_target.frame.dot);
    const eql_command = try makeCommandSpan(allocator, &[_][]const u8{"EOL"});
    try std.testing.expect(try codeCompile(&editor, allocator, eql_target.frame, eql_command.span, true));
    try std.testing.expect(try codeInterpret(&editor, allocator, eql_target.frame, &special_frames, .LeadParamNone, 1, eql_command.span.code.?, true));
}

test "code interpreter executes compiled replace commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const target = try line_ops.createContentFrame(allocator, &[_][]const u8{"hello world"});
    try mark_ops.markCreate(allocator, target.content_lines[0], 1, &target.frame.dot);
    const command = try makeCommandSpan(allocator, &[_][]const u8{"R/world/earth/"});
    try std.testing.expect(try codeCompile(&editor, allocator, target.frame, command.span, true));
    var special_frames: types.SpecialFrames = .{};
    try std.testing.expect(try codeInterpret(&editor, allocator, target.frame, &special_frames, .LeadParamNone, 1, command.span.code.?, true));
    try std.testing.expectEqualStrings("hello earth", target.content_lines[0].str.?.slice(1, 11));
}
