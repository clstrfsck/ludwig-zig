const std = @import("std");
const batch_output = @import("../platform/batch_output.zig");
const chars = @import("chars.zig");
const interactive_io = @import("../platform/interactive_io.zig");
const span_ops = @import("span.zig");
const state = @import("state.zig");
const str_object = @import("str_object.zig");
const types = @import("types.zig");

pub const enquiry_num_len = 20;
pub const system_name = "Zig/Linux";

const illegal_mark_number_message = "Illegal mark number.";
const invalid_integer_message = "Trailing parameter integer is invalid.";
const span_names_one_line_message = "A span name must be on one line.";
const span_must_be_one_line_message = "A span used as a trailing parameter for this command must be one line.";
const unknown_item_message = "Unknown enquiry item.";
const tpar_too_deep_message = "Trailing parameter translation has gone too deep.";
const reserved_tpd_message = "Delimiter reserved for future use.";
const prompts_one_line_message = "A prompt string must be on one line.";
const interactive_mode_only_message = "Allowed in interactive mode only.";
const nonprintable_introducer_message = "Command Introducer is not printable";

const VarType = enum {
    unknown,
    terminal,
    frame,
    opsys,
    ludwig,
};

fn emitMessage(editor: *const state.Editor, message: []const u8) void {
    switch (editor.ludwig_mode) {
        .LudwigScreen => interactive_io.queueStatusMessage(message),
        .LudwigBatch, .LudwigHardcopy => {
            if (editor.batch_output_enabled) {
                batch_output.printMessage(message);
            }
        },
    }
}

fn ensureString(allocator: std.mem.Allocator, tp: *types.TParObject) !void {
    if (tp.Str == null) {
        tp.Str = try str_object.newBlankStrObject(allocator, types.MaxStrLen);
    }
}

fn uppercaseCopy(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, input.len);
    for (input, 0..) |ch, idx| {
        out[idx] = chars.chToUpper(ch);
    }
    return out;
}

fn tparDuplicateCon(
    allocator: std.mem.Allocator,
    tpar: *types.TParObject,
    tp_out: *types.TParObject,
) !void {
    tp_out.* = tpar.*;
    tp_out.Str = try tpar.Str.?.clone();
    tp_out.Nxt = null;
    tp_out.Con = null;

    var src_con = tpar.Con;
    var prev: ?*types.TParObject = null;
    while (src_con) |current| {
        const node = try allocator.create(types.TParObject);
        node.* = current.*;
        node.Str = try current.Str.?.clone();
        node.Nxt = null;
        node.Con = null;
        if (prev) |previous| {
            previous.Con = node;
        } else {
            tp_out.Con = node;
        }
        prev = node;
        src_con = current.Con;
    }
}

pub fn tparDuplicate(
    allocator: std.mem.Allocator,
    from_tp: ?*types.TParObject,
) !?*types.TParObject {
    if (from_tp == null) {
        return null;
    }

    const to_tp = try allocator.create(types.TParObject);
    try tparDuplicateCon(allocator, from_tp.?, to_tp);

    var src_next = from_tp.?.Nxt;
    var dst_next = to_tp;
    while (src_next) |current| {
        const node = try allocator.create(types.TParObject);
        try tparDuplicateCon(allocator, current, node);
        dst_next.Nxt = node;
        dst_next = node;
        src_next = current.Nxt;
    }
    return to_tp;
}

pub fn tparToInt(strng: *types.TParObject, chpos: *isize) ?isize {
    const first = if (chpos.* > strng.Len) 0 else strng.Str.?.get(chpos.*);
    if (first < '0' or first > '9') {
        return null;
    }

    var number: isize = 0;
    var ch = first;
    while (true) {
        const digit: isize = ch - '0';
        if (number > @divTrunc(types.MaxInt - digit, 10)) {
            return null;
        }
        number = number * 10 + digit;
        chpos.* += 1;
        ch = if (chpos.* > strng.Len) 0 else strng.Str.?.get(chpos.*);
        if (ch < '0' or ch > '9') {
            break;
        }
    }
    return number;
}

pub fn tparToIntMessage(editor: *state.Editor, strng: *types.TParObject, chpos: *isize) ?isize {
    const value = tparToInt(strng, chpos) orelse {
        emitMessage(editor, invalid_integer_message);
        return null;
    };
    return value;
}

pub fn tparToMark(strng: *types.TParObject) ?isize {
    if (strng.Len == 0) {
        return null;
    }
    const mch = strng.Str.?.get(1);
    if (mch >= '0' and mch <= '9') {
        var pos: isize = 1;
        const mark = tparToInt(strng, &pos) orelse return null;
        if (pos <= strng.Len or mark < types.MinUserMarkNumber or mark > types.MaxUserMarkNumber) {
            return null;
        }
        return mark;
    }
    if (strng.Len > 1 or (mch != '=' and mch != '%')) {
        return null;
    }
    return if (mch == '=') types.MarkEquals else types.MarkModified;
}

pub fn tparToMarkMessage(editor: *state.Editor, strng: *types.TParObject) ?isize {
    if (strng.Len == 0) {
        emitMessage(editor, illegal_mark_number_message);
        return null;
    }
    const mch = strng.Str.?.get(1);
    if (mch >= '0' and mch <= '9') {
        var pos: isize = 1;
        const mark = tparToIntMessage(editor, strng, &pos) orelse return null;
        if (pos <= strng.Len or mark < types.MinUserMarkNumber or mark > types.MaxUserMarkNumber) {
            emitMessage(editor, illegal_mark_number_message);
            return null;
        }
        return mark;
    }
    if (strng.Len > 1 or (mch != '=' and mch != '%')) {
        emitMessage(editor, illegal_mark_number_message);
        return null;
    }
    return if (mch == '=') types.MarkEquals else types.MarkModified;
}

pub fn tparSubstitute(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    tpar: *types.TParObject,
    cmd: types.Commands,
    this_tp: isize,
) !bool {
    if (tpar.Con != null) {
        emitMessage(editor, span_names_one_line_message);
        return false;
    }
    try ensureString(allocator, tpar);

    const name = try uppercaseCopy(allocator, tpar.Str.?.slice(1, tpar.Len));
    defer allocator.free(name);

    var span: ?*types.SpanObject = null;
    var dummy: ?*types.SpanObject = null;
    if (!try span_ops.spanFind(editor, allocator, name, &span, &dummy)) {
        emitMessage(editor, "No such span.");
        return false;
    }

    tpar.Dlm = 0;
    var start_mark = span.?.MarkOne.?.*;
    const end_mark = span.?.MarkTwo.?.*;

    if (start_mark.Line == end_mark.Line) {
        tpar.Len = end_mark.Col - start_mark.Col;
        const src_len = if (start_mark.Col > start_mark.Line.Used)
            @as(isize, 0)
        else if (end_mark.Col > end_mark.Line.Used)
            end_mark.Line.Used - start_mark.Col + 1
        else
            tpar.Len;
        tpar.Str.?.fillCopy(start_mark.Line.Str.?, start_mark.Col, src_len, 1, tpar.Len, ' ');
        return true;
    }

    if (!editor.cmd_attrib[@intFromEnum(cmd)].TparInfo[@intCast(this_tp)].MlAllowed) {
        emitMessage(editor, span_must_be_one_line_message);
        return false;
    }

    tpar.Len = if (start_mark.Col > start_mark.Line.Used) 0 else start_mark.Line.Used - start_mark.Col + 1;
    tpar.Str.?.copy(start_mark.Line.Str.?, start_mark.Col, tpar.Len, 1);

    var tmp_tp: ?*types.TParObject = null;
    start_mark.Line = start_mark.Line.FLink.?;
    while (start_mark.Line != end_mark.Line) {
        const node = try allocator.create(types.TParObject);
        node.* = .{
            .Str = try str_object.newBlankStrObject(allocator, types.MaxStrLen),
            .Dlm = 0,
            .Len = start_mark.Line.Used,
        };
        node.Str.?.copy(start_mark.Line.Str.?, 1, node.Len, 1);
        if (tmp_tp) |prev| {
            prev.Con = node;
        } else {
            tpar.Con = node;
        }
        tmp_tp = node;
        start_mark.Line = start_mark.Line.FLink.?;
    }

    const last_node = try allocator.create(types.TParObject);
    last_node.* = .{
        .Str = try str_object.newBlankStrObject(allocator, types.MaxStrLen),
        .Dlm = 0,
        .Len = end_mark.Col - 1,
    };
    last_node.Str.?.fillCopy(end_mark.Line.Str.?, 1, end_mark.Line.Used, 1, last_node.Len, ' ');
    if (tmp_tp) |prev| {
        prev.Con = last_node;
    } else {
        tpar.Con = last_node;
    }
    return true;
}

fn leftPadded(allocator: std.mem.Allocator, width: usize, value: isize) ![]u8 {
    const raw = try std.fmt.allocPrint(allocator, "{d}", .{value});
    defer allocator.free(raw);
    if (raw.len >= width) {
        return allocator.dupe(u8, raw);
    }
    const out = try allocator.alloc(u8, width);
    @memset(out, ' ');
    @memcpy(out[width - raw.len ..], raw);
    return out;
}

pub fn findEnquiry(
    allocator: std.mem.Allocator,
    editor: *state.Editor,
    frame: ?*types.FrameObject,
    name: []const u8,
) !?[]u8 {
    const dash = std.mem.indexOfScalar(u8, name, '-') orelse return null;
    const prefix = try uppercaseCopy(allocator, name[0..dash]);
    defer allocator.free(prefix);

    const variable_type: VarType = if (std.mem.eql(u8, prefix, "TERMINAL"))
        .terminal
    else if (std.mem.eql(u8, prefix, "FRAME"))
        .frame
    else if (std.mem.eql(u8, prefix, "ENV"))
        .opsys
    else if (std.mem.eql(u8, prefix, "LUDWIG"))
        .ludwig
    else
        .unknown;

    const item = if (variable_type == .opsys)
        try allocator.dupe(u8, name[dash + 1 ..])
    else
        try uppercaseCopy(allocator, name[dash + 1 ..]);
    defer allocator.free(item);

    return switch (variable_type) {
        .terminal => blk: {
            if (std.mem.eql(u8, item, "NAME")) break :blk try allocator.dupe(u8, editor.terminal_info.Name);
            if (std.mem.eql(u8, item, "HEIGHT")) break :blk try leftPadded(allocator, enquiry_num_len, editor.terminal_info.Height);
            if (std.mem.eql(u8, item, "WIDTH")) break :blk try leftPadded(allocator, enquiry_num_len, editor.terminal_info.Width);
            if (std.mem.eql(u8, item, "SPEED")) break :blk try leftPadded(allocator, enquiry_num_len, 0);
            break :blk null;
        },
        .frame => blk: {
            const current = frame orelse break :blk null;
            if (std.mem.eql(u8, item, "NAME")) {
                break :blk try allocator.dupe(u8, if (current.Span) |span| span.Name else "");
            }
            if (std.mem.eql(u8, item, "INPUTFILE")) {
                if (current.InputFile == 0 or editor.files[@intCast(current.InputFile)] == null) {
                    break :blk try allocator.dupe(u8, "");
                }
                break :blk try allocator.dupe(u8, editor.files[@intCast(current.InputFile)].?.Filename);
            }
            if (std.mem.eql(u8, item, "OUTPUTFILE")) {
                if (current.OutputFile == 0 or editor.files[@intCast(current.OutputFile)] == null) {
                    break :blk try allocator.dupe(u8, "");
                }
                break :blk try allocator.dupe(u8, editor.files[@intCast(current.OutputFile)].?.Filename);
            }
            if (std.mem.eql(u8, item, "MODIFIED")) {
                break :blk try allocator.dupe(u8, if (current.TextModified) "Y" else "N");
            }
            break :blk null;
        },
        .opsys => blk: {
            const value = std.process.getEnvVarOwned(allocator, item) catch break :blk null;
            if (value.len > types.MaxStrLen) {
                defer allocator.free(value);
                break :blk try allocator.dupe(u8, value[0..types.MaxStrLen]);
            }
            break :blk value;
        },
        .ludwig => blk: {
            if (std.mem.eql(u8, item, "VERSION")) break :blk try allocator.dupe(u8, types.LudwigVersion);
            if (std.mem.eql(u8, item, "OPSYS")) break :blk try allocator.dupe(u8, system_name);
            if (std.mem.eql(u8, item, "COMMAND_INTRODUCER")) {
                if (editor.command_introducer < 0 or editor.command_introducer > types.MaxSetRange or !chars.chIsPrintable(@intCast(editor.command_introducer))) {
                    emitMessage(editor, nonprintable_introducer_message);
                    break :blk try allocator.dupe(u8, "");
                }
                const byte = [_]u8{@intCast(editor.command_introducer)};
                break :blk try allocator.dupe(u8, byte[0..]);
            }
            if (std.mem.eql(u8, item, "INSERT_MODE")) {
                const enabled = editor.edit_mode == .ModeInsert or (editor.edit_mode == .ModeCommand and editor.previous_mode == .ModeInsert);
                break :blk try allocator.dupe(u8, if (enabled) "Y" else "N");
            }
            if (std.mem.eql(u8, item, "OVERTYPE_MODE")) {
                const enabled = editor.edit_mode == .ModeOvertype or (editor.edit_mode == .ModeCommand and editor.previous_mode == .ModeOvertype);
                break :blk try allocator.dupe(u8, if (enabled) "Y" else "N");
            }
            break :blk null;
        },
        .unknown => null,
    };
}

pub fn tparEnquire(
    allocator: std.mem.Allocator,
    editor: *state.Editor,
    frame: ?*types.FrameObject,
    tpar: *types.TParObject,
) !bool {
    try ensureString(allocator, tpar);
    tpar.Dlm = 0;
    if (try findEnquiry(allocator, editor, frame, tpar.Str.?.slice(1, tpar.Len))) |result| {
        defer allocator.free(result);
        try tpar.Str.?.assign(result);
        tpar.Len = @intCast(result.len);
        return true;
    }
    emitMessage(editor, unknown_item_message);
    editor.exit_abort = true;
    return false;
}

pub fn tparAnalyse(
    allocator: std.mem.Allocator,
    editor: *state.Editor,
    frame: ?*types.FrameObject,
    cmd: types.Commands,
    tran: *types.TParObject,
    depth: isize,
    this_tp: isize,
) !bool {
    if (depth > types.MaxTparRecursion) {
        emitMessage(editor, tpar_too_deep_message);
        return false;
    }
    if (tran.Dlm == types.TpdSmart or tran.Dlm == types.TpdExact or tran.Dlm == types.TpdLit) {
        return !editor.tt_control_c;
    }

    var ended = false;
    while (!ended and !editor.tt_control_c) {
        const delim = tran.Dlm;
        if (tran.Con == null) {
            if (tran.Len > 1) {
                const first = tran.Str.?.get(1);
                if (first == tran.Str.?.get(tran.Len) and (first == types.TpdSpan or first == types.TpdPrompt or first == types.TpdEnvironment or first == types.TpdSmart or first == types.TpdExact or first == types.TpdLit)) {
                    tran.Dlm = first;
                    tran.Len -= 2;
                    tran.Str.?.erase(1, 1);
                    if (!try tparAnalyse(allocator, editor, frame, cmd, tran, depth + 1, this_tp)) {
                        return false;
                    }
                }
            }
        } else {
            var tmp_tp = tran.Con.?;
            while (tmp_tp.Con != null) {
                tmp_tp = tmp_tp.Con.?;
            }
            if (tran.Len != 0 and tmp_tp.Len != 0) {
                const first = tran.Str.?.get(1);
                if (first == tmp_tp.Str.?.get(tmp_tp.Len) and (first == types.TpdSpan or first == types.TpdPrompt or first == types.TpdEnvironment or first == types.TpdSmart or first == types.TpdExact or first == types.TpdLit)) {
                    tran.Dlm = first;
                    tran.Len -= 1;
                    tran.Str.?.erase(1, 1);
                    tmp_tp.Len -= 1;
                    if (!try tparAnalyse(allocator, editor, frame, cmd, tran, depth + 1, this_tp)) {
                        return false;
                    }
                }
            }
        }

        switch (delim) {
            types.TpdSpan => if (!try tparSubstitute(editor, allocator, tran, cmd, this_tp)) return false,
            types.TpdEnvironment => {
                if (editor.file_data.OldCmds) {
                    emitMessage(editor, reserved_tpd_message);
                    return false;
                }
                if (!try tparEnquire(allocator, editor, frame, tran)) {
                    return false;
                }
            },
            types.TpdPrompt => {
                if (editor.ludwig_mode != .LudwigScreen) {
                    emitMessage(editor, interactive_mode_only_message);
                    return false;
                }

                const prompt = if (tran.Len == 0)
                    editor.dflt_prompts[@intFromEnum(editor.cmd_attrib[@intFromEnum(cmd)].TparInfo[@intCast(this_tp)].PromptName)]
                else
                    tran.Str.?.slice(1, tran.Len);

                if (cmd == .CmdVerify) {
                    const reply = if (frame) |verify_frame|
                        (try interactive_io.readVerifyReply(editor, verify_frame, prompt)) orelse return false
                    else
                        (try interactive_io.readVerifyKey(prompt)) orelse return false;
                    const response = switch (reply) {
                        ' ', 'Y' => "Y",
                        'N' => "N",
                        'A' => "A",
                        'Q' => "Q",
                        else => unreachable,
                    };
                    tran.Str = try str_object.newStrObjectFrom(allocator, response);
                    tran.Len = 1;
                    tran.Dlm = 0;
                } else {
                    if (tran.Con != null) {
                        emitMessage(editor, prompts_one_line_message);
                        return false;
                    }
                    const response = try interactive_io.readPromptLineWithOptions(allocator, prompt, .{
                        .editor = editor,
                        .frame = frame,
                        .max_tp = @max(editor.cmd_attrib[@intFromEnum(cmd)].TpCount, 1),
                        .this_tp = this_tp,
                    });
                    tran.Str = try str_object.newStrObjectFrom(allocator, response);
                    tran.Len = @intCast(response.len);
                    tran.Dlm = 0;
                }
            },
            else => ended = true,
        }
    }
    return !editor.tt_control_c;
}

pub fn trim(request: *types.TParObject) void {
    if (request.Len <= 0) {
        return;
    }
    const original_len = request.Len;
    var index: isize = 1;
    while (index <= request.Len and request.Str.?.get(index) == ' ') : (index += 1) {}
    request.Len -= index - 1;
    if (request.Len > 0) {
        request.Str.?.erase(index - 1, 1);
        request.Str.?.applyN(chars.chToUpper, request.Len, 1);
    }
    if (request.Len < original_len) {
        request.Str.?.fill(' ', request.Len + 1, original_len);
    }
}

pub fn tparGet1(
    allocator: std.mem.Allocator,
    editor: *state.Editor,
    frame: ?*types.FrameObject,
    tpar: ?*types.TParObject,
    cmd: types.Commands,
    tran: *types.TParObject,
) !bool {
    if (tpar == null) {
        return false;
    }
    try tparDuplicateCon(allocator, tpar.?, tran);
    if (!try tparAnalyse(allocator, editor, frame, cmd, tran, 1, 1)) {
        return false;
    }
    if (editor.cmd_attrib[@intFromEnum(cmd)].TparInfo[1].TrimReply) {
        trim(tran);
    }
    return true;
}

pub fn tparGet2(
    allocator: std.mem.Allocator,
    editor: *state.Editor,
    frame: ?*types.FrameObject,
    tpar: ?*types.TParObject,
    cmd: types.Commands,
    trn1: *types.TParObject,
    trn2: *types.TParObject,
) !bool {
    if (tpar == null or tpar.?.Nxt == null) {
        return false;
    }

    try tparDuplicateCon(allocator, tpar.?, trn1);
    try tparDuplicateCon(allocator, tpar.?.Nxt.?, trn2);

    if (!try tparAnalyse(allocator, editor, frame, cmd, trn1, 1, 1)) {
        return false;
    }
    if (trn1.Len != 0 and !try tparAnalyse(allocator, editor, frame, cmd, trn2, 1, 2)) {
        return false;
    }
    if (editor.cmd_attrib[@intFromEnum(cmd)].TparInfo[1].TrimReply) {
        trim(trn1);
    }
    if (editor.cmd_attrib[@intFromEnum(cmd)].TparInfo[2].TrimReply) {
        trim(trn2);
    }
    return true;
}

test "tpar integer mark and duplicate helpers preserve list structure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var pos: isize = 1;
    var digits = types.TParObject{
        .Str = try str_object.newStrObjectFrom(allocator, "123"),
        .Len = 3,
    };
    var mark_three = types.TParObject{
        .Str = try str_object.newStrObjectFrom(allocator, "3"),
        .Len = 1,
    };
    var mark_equals = types.TParObject{
        .Str = try str_object.newStrObjectFrom(allocator, "="),
        .Len = 1,
    };
    try std.testing.expectEqual(@as(?isize, 123), tparToInt(&digits, &pos));
    try std.testing.expectEqual(@as(?isize, 3), tparToMark(&mark_three));
    try std.testing.expectEqual(@as(?isize, types.MarkEquals), tparToMark(&mark_equals));

    var second = types.TParObject{
        .Str = try str_object.newStrObjectFrom(allocator, "two"),
        .Len = 3,
    };
    var third = types.TParObject{
        .Str = try str_object.newStrObjectFrom(allocator, "three"),
        .Len = 5,
    };
    second.Con = &third;
    var first = types.TParObject{
        .Str = try str_object.newStrObjectFrom(allocator, "one"),
        .Len = 3,
        .Nxt = &second,
    };
    const duplicate = (try tparDuplicate(allocator, &first)).?;
    try std.testing.expect(duplicate != &first);
    try std.testing.expect(duplicate.Str != first.Str);
    try std.testing.expectEqualStrings("one", duplicate.Str.?.slice(1, 3));
    try std.testing.expect(duplicate.Nxt != null);
    try std.testing.expectEqualStrings("two", duplicate.Nxt.?.Str.?.slice(1, 3));
    try std.testing.expect(duplicate.Nxt.?.Con != null);
    try std.testing.expectEqualStrings("three", duplicate.Nxt.?.Con.?.Str.?.slice(1, 5));
}

test "tpar span substitution enquiries and analysis work in batch mode" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{
        "Hello World",
        "Line2",
    });
    editor.terminal_info = .{ .Name = "tty", .Width = 80, .Height = 24 };
    editor.file_data.OldCmds = false;

    var mark1: ?*types.MarkObject = null;
    var mark2: ?*types.MarkObject = null;
    try @import("mark.zig").markCreate(allocator, fixture.content_lines[0], 7, &mark1);
    try @import("mark.zig").markCreate(allocator, fixture.content_lines[1], 6, &mark2);
    try std.testing.expect(try span_ops.spanCreate(&editor, allocator, "TEST", mark1.?, mark2.?));

    var substitute = types.TParObject{
        .Str = try str_object.newBlankStrObject(allocator, types.MaxStrLen),
        .Len = 4,
        .Dlm = types.TpdSpan,
    };
    try substitute.Str.?.assign("TEST");
    try std.testing.expect(try tparSubstitute(&editor, allocator, &substitute, .CmdReplace, 2));
    try std.testing.expectEqualStrings("World", substitute.Str.?.slice(1, 5));
    try std.testing.expect(substitute.Con != null);
    try std.testing.expectEqualStrings("Line2", substitute.Con.?.Str.?.slice(1, 5));

    const version_enquiry = "LUDWIG-VERSION";
    var enquiry = types.TParObject{
        .Str = try str_object.newBlankStrObject(allocator, types.MaxStrLen),
        .Len = version_enquiry.len,
        .Dlm = types.TpdEnvironment,
    };
    try enquiry.Str.?.assign(version_enquiry);
    try std.testing.expect(try tparEnquire(allocator, &editor, fixture.frame, &enquiry));
    try std.testing.expectEqualStrings(types.LudwigVersion, enquiry.Str.?.slice(1, enquiry.Len));

    const frame_enquiry = "FRAME-MODIFIED";
    var analysed = types.TParObject{
        .Str = try str_object.newBlankStrObject(allocator, types.MaxStrLen),
        .Len = frame_enquiry.len,
        .Dlm = types.TpdEnvironment,
    };
    try analysed.Str.?.assign(frame_enquiry);
    try std.testing.expect(try tparAnalyse(allocator, &editor, fixture.frame, .CmdGet, &analysed, 1, 1));
    try std.testing.expectEqualStrings("N", analysed.Str.?.slice(1, analysed.Len));
}

test "tpar message helpers queue interactive parse failures" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.ludwig_mode = .LudwigScreen;

    var bad_int = types.TParObject{
        .Str = try str_object.newStrObjectFrom(allocator, "ABC"),
        .Len = 3,
    };
    var pos: isize = 1;
    try std.testing.expectEqual(@as(?isize, null), tparToIntMessage(&editor, &bad_int, &pos));
    try std.testing.expectEqualStrings(invalid_integer_message, interactive_io.takeStatusMessage().?);

    var bad_mark = types.TParObject{
        .Str = try str_object.newStrObjectFrom(allocator, ""),
        .Len = 0,
    };
    try std.testing.expectEqual(@as(?isize, null), tparToMarkMessage(&editor, &bad_mark));
    try std.testing.expectEqualStrings(illegal_mark_number_message, interactive_io.takeStatusMessage().?);
}

test "tpar substitution and enquiry queue interactive failure messages" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.ludwig_mode = .LudwigScreen;

    var substitute = types.TParObject{
        .Str = try str_object.newStrObjectFrom(allocator, "MISSING"),
        .Len = "MISSING".len,
    };
    try std.testing.expect(!(try tparSubstitute(&editor, allocator, &substitute, .CmdReplace, 1)));
    try std.testing.expectEqualStrings("No such span.", interactive_io.takeStatusMessage().?);

    var enquiry = types.TParObject{
        .Str = try str_object.newBlankStrObject(allocator, types.MaxStrLen),
        .Len = "BOGUS-THING".len,
    };
    try enquiry.Str.?.assign("BOGUS-THING");
    try std.testing.expect(!(try tparEnquire(allocator, &editor, null, &enquiry)));
    try std.testing.expectEqualStrings(unknown_item_message, interactive_io.takeStatusMessage().?);
    try std.testing.expect(editor.exit_abort);
}

test "tpar get helpers duplicate analyse and trim replies" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{"ignored"});
    editor.file_data.OldCmds = false;

    var source1 = types.TParObject{
        .Str = try str_object.newStrObjectFrom(allocator, "  42"),
        .Len = 4,
        .Dlm = 0,
    };
    var out1: types.TParObject = .{};
    try std.testing.expect(try tparGet1(allocator, &editor, fixture.frame, &source1, .CmdEqualColumn, &out1));
    try std.testing.expectEqualStrings("42", out1.Str.?.slice(1, out1.Len));

    var source2 = types.TParObject{
        .Str = try str_object.newStrObjectFrom(allocator, "FRAME-MODIFIED"),
        .Len = 14,
        .Dlm = types.TpdEnvironment,
    };
    source1.Nxt = &source2;
    var trn1: types.TParObject = .{};
    var trn2: types.TParObject = .{};
    try std.testing.expect(try tparGet2(allocator, &editor, fixture.frame, &source1, .CmdReplace, &trn1, &trn2));
    try std.testing.expectEqualStrings("  42", trn1.Str.?.slice(1, trn1.Len));
    try std.testing.expectEqualStrings("N", trn2.Str.?.slice(1, trn2.Len));
}

test "tpar verify prompt retries invalid replies in screen mode" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.ludwig_mode = .LudwigScreen;
    editor.terminal_info = .{ .Width = 80, .Height = 24 };

    const fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{"alpha"});

    var prompt = types.TParObject{
        .Str = try str_object.newBlankStrObject(allocator, 0),
        .Dlm = types.TpdPrompt,
    };
    var reply: types.TParObject = .{};

    interactive_io.testing.installInput("\x011Q");
    defer interactive_io.testing.clearInput();
    interactive_io.resetTestBeepCount();

    try std.testing.expect(try tparGet1(allocator, &editor, fixture.frame, &prompt, .CmdVerify, &reply));
    try std.testing.expectEqualStrings("Q", reply.Str.?.slice(1, reply.Len));
    try std.testing.expectEqual(@as(usize, 1), interactive_io.getTestBeepCount());
}
