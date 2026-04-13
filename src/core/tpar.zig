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
        .ludwig_screen => interactive_io.queueStatusMessage(message),
        .ludwig_batch, .ludwig_hardcopy => {
            if (editor.batch_output_enabled) {
                batch_output.printMessage(message);
            }
        },
    }
}

fn ensureString(allocator: std.mem.Allocator, tp: *types.TParObject) !void {
    if (tp.str == null) {
        tp.str = try str_object.newBlankStrObject(allocator, types.max_str_len);
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
    tp_out.str = try tpar.str.?.clone();
    tp_out.nxt = null;
    tp_out.con = null;

    var src_con = tpar.con;
    var prev: ?*types.TParObject = null;
    while (src_con) |current| {
        const node = try allocator.create(types.TParObject);
        node.* = current.*;
        node.str = try current.str.?.clone();
        node.nxt = null;
        node.con = null;
        if (prev) |previous| {
            previous.con = node;
        } else {
            tp_out.con = node;
        }
        prev = node;
        src_con = current.con;
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

    var src_next = from_tp.?.nxt;
    var dst_next = to_tp;
    while (src_next) |current| {
        const node = try allocator.create(types.TParObject);
        try tparDuplicateCon(allocator, current, node);
        dst_next.nxt = node;
        dst_next = node;
        src_next = current.nxt;
    }
    return to_tp;
}

pub fn tparToInt(strng: *types.TParObject, chpos: *isize) ?isize {
    const first = if (chpos.* > strng.len) 0 else strng.str.?.get(chpos.*);
    if (first < '0' or first > '9') {
        return null;
    }

    var number: isize = 0;
    var ch = first;
    while (true) {
        const digit: isize = ch - '0';
        if (number > @divTrunc(types.max_int - digit, 10)) {
            return null;
        }
        number = number * 10 + digit;
        chpos.* += 1;
        ch = if (chpos.* > strng.len) 0 else strng.str.?.get(chpos.*);
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
    if (strng.len == 0) {
        return null;
    }
    const mch = strng.str.?.get(1);
    if (mch >= '0' and mch <= '9') {
        var pos: isize = 1;
        const mark = tparToInt(strng, &pos) orelse return null;
        if (pos <= strng.len or mark < types.min_user_mark_number or mark > types.max_user_mark_number) {
            return null;
        }
        return mark;
    }
    if (strng.len > 1 or (mch != '=' and mch != '%')) {
        return null;
    }
    return if (mch == '=') types.mark_equals else types.mark_modified;
}

pub fn tparToMarkMessage(editor: *state.Editor, strng: *types.TParObject) ?isize {
    if (strng.len == 0) {
        emitMessage(editor, illegal_mark_number_message);
        return null;
    }
    const mch = strng.str.?.get(1);
    if (mch >= '0' and mch <= '9') {
        var pos: isize = 1;
        const mark = tparToIntMessage(editor, strng, &pos) orelse return null;
        if (pos <= strng.len or mark < types.min_user_mark_number or mark > types.max_user_mark_number) {
            emitMessage(editor, illegal_mark_number_message);
            return null;
        }
        return mark;
    }
    if (strng.len > 1 or (mch != '=' and mch != '%')) {
        emitMessage(editor, illegal_mark_number_message);
        return null;
    }
    return if (mch == '=') types.mark_equals else types.mark_modified;
}

pub fn tparSubstitute(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    tpar: *types.TParObject,
    cmd: types.Commands,
    this_tp: isize,
) !bool {
    if (tpar.con != null) {
        emitMessage(editor, span_names_one_line_message);
        return false;
    }
    try ensureString(allocator, tpar);

    const name = try uppercaseCopy(allocator, tpar.str.?.slice(1, tpar.len));
    defer allocator.free(name);

    var span: ?*types.SpanObject = null;
    var dummy: ?*types.SpanObject = null;
    if (!try span_ops.spanFind(editor, allocator, name, &span, &dummy)) {
        emitMessage(editor, "No such span.");
        return false;
    }

    tpar.dlm = 0;
    var start_mark = span.?.mark_one.?.*;
    const end_mark = span.?.mark_two.?.*;

    if (start_mark.line == end_mark.line) {
        tpar.len = end_mark.col - start_mark.col;
        const src_len = if (start_mark.col > start_mark.line.used)
            @as(isize, 0)
        else if (end_mark.col > end_mark.line.used)
            end_mark.line.used - start_mark.col + 1
        else
            tpar.len;
        tpar.str.?.fillCopy(start_mark.line.str.?, start_mark.col, src_len, 1, tpar.len, ' ');
        return true;
    }

    if (!editor.cmd_attrib[@intFromEnum(cmd)].tpar_info[@intCast(this_tp)].ml_allowed) {
        emitMessage(editor, span_must_be_one_line_message);
        return false;
    }

    tpar.len = if (start_mark.col > start_mark.line.used) 0 else start_mark.line.used - start_mark.col + 1;
    tpar.str.?.copy(start_mark.line.str.?, start_mark.col, tpar.len, 1);

    var tmp_tp: ?*types.TParObject = null;
    start_mark.line = start_mark.line.f_link.?;
    while (start_mark.line != end_mark.line) {
        const node = try allocator.create(types.TParObject);
        node.* = .{
            .str = try str_object.newBlankStrObject(allocator, types.max_str_len),
            .dlm = 0,
            .len = start_mark.line.used,
        };
        node.str.?.copy(start_mark.line.str.?, 1, node.len, 1);
        if (tmp_tp) |prev| {
            prev.con = node;
        } else {
            tpar.con = node;
        }
        tmp_tp = node;
        start_mark.line = start_mark.line.f_link.?;
    }

    const last_node = try allocator.create(types.TParObject);
    last_node.* = .{
        .str = try str_object.newBlankStrObject(allocator, types.max_str_len),
        .dlm = 0,
        .len = end_mark.col - 1,
    };
    last_node.str.?.fillCopy(end_mark.line.str.?, 1, end_mark.line.used, 1, last_node.len, ' ');
    if (tmp_tp) |prev| {
        prev.con = last_node;
    } else {
        tpar.con = last_node;
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
            if (std.mem.eql(u8, item, "NAME")) break :blk try allocator.dupe(u8, editor.terminal_info.name);
            if (std.mem.eql(u8, item, "HEIGHT")) break :blk try leftPadded(allocator, enquiry_num_len, editor.terminal_info.height);
            if (std.mem.eql(u8, item, "WIDTH")) break :blk try leftPadded(allocator, enquiry_num_len, editor.terminal_info.width);
            if (std.mem.eql(u8, item, "SPEED")) break :blk try leftPadded(allocator, enquiry_num_len, 0);
            break :blk null;
        },
        .frame => blk: {
            const current = frame orelse break :blk null;
            if (std.mem.eql(u8, item, "NAME")) {
                break :blk try allocator.dupe(u8, if (current.span) |span| span.name else "");
            }
            if (std.mem.eql(u8, item, "INPUTFILE")) {
                if (current.input_file == 0 or editor.files[@intCast(current.input_file)] == null) {
                    break :blk try allocator.dupe(u8, "");
                }
                break :blk try allocator.dupe(u8, editor.files[@intCast(current.input_file)].?.filename);
            }
            if (std.mem.eql(u8, item, "OUTPUTFILE")) {
                if (current.output_file == 0 or editor.files[@intCast(current.output_file)] == null) {
                    break :blk try allocator.dupe(u8, "");
                }
                break :blk try allocator.dupe(u8, editor.files[@intCast(current.output_file)].?.filename);
            }
            if (std.mem.eql(u8, item, "MODIFIED")) {
                break :blk try allocator.dupe(u8, if (current.text_modified) "Y" else "N");
            }
            break :blk null;
        },
        .opsys => blk: {
            const value = std.process.getEnvVarOwned(allocator, item) catch break :blk null;
            if (value.len > types.max_str_len) {
                defer allocator.free(value);
                break :blk try allocator.dupe(u8, value[0..types.max_str_len]);
            }
            break :blk value;
        },
        .ludwig => blk: {
            if (std.mem.eql(u8, item, "VERSION")) break :blk try allocator.dupe(u8, types.ludwig_reader);
            if (std.mem.eql(u8, item, "OPSYS")) break :blk try allocator.dupe(u8, system_name);
            if (std.mem.eql(u8, item, "COMMAND_INTRODUCER")) {
                if (editor.command_introducer < 0 or editor.command_introducer > types.max_set_range or !chars.chIsPrintable(@intCast(editor.command_introducer))) {
                    emitMessage(editor, nonprintable_introducer_message);
                    break :blk try allocator.dupe(u8, "");
                }
                const byte = [_]u8{@intCast(editor.command_introducer)};
                break :blk try allocator.dupe(u8, byte[0..]);
            }
            if (std.mem.eql(u8, item, "INSERT_MODE")) {
                const enabled = editor.edit_mode == .mode_insert or (editor.edit_mode == .mode_command and editor.previous_mode == .mode_insert);
                break :blk try allocator.dupe(u8, if (enabled) "Y" else "N");
            }
            if (std.mem.eql(u8, item, "OVERTYPE_MODE")) {
                const enabled = editor.edit_mode == .mode_overtype or (editor.edit_mode == .mode_command and editor.previous_mode == .mode_overtype);
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
    tpar.dlm = 0;
    if (try findEnquiry(allocator, editor, frame, tpar.str.?.slice(1, tpar.len))) |result| {
        defer allocator.free(result);
        try tpar.str.?.assign(result);
        tpar.len = @intCast(result.len);
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
    if (depth > types.max_tpar_recursion) {
        emitMessage(editor, tpar_too_deep_message);
        return false;
    }
    if (tran.dlm == types.tpd_smart or tran.dlm == types.tpd_exact or tran.dlm == types.tpd_lit) {
        return !editor.tt_control_c;
    }

    var ended = false;
    while (!ended and !editor.tt_control_c) {
        const delim = tran.dlm;
        if (tran.con == null) {
            if (tran.len > 1) {
                const first = tran.str.?.get(1);
                if (first == tran.str.?.get(tran.len) and (first == types.tpd_span or first == types.tpd_prompt or first == types.tpd_environment or first == types.tpd_smart or first == types.tpd_exact or first == types.tpd_lit)) {
                    tran.dlm = first;
                    tran.len -= 2;
                    tran.str.?.erase(1, 1);
                    if (!try tparAnalyse(allocator, editor, frame, cmd, tran, depth + 1, this_tp)) {
                        return false;
                    }
                }
            }
        } else {
            var tmp_tp = tran.con.?;
            while (tmp_tp.con != null) {
                tmp_tp = tmp_tp.con.?;
            }
            if (tran.len != 0 and tmp_tp.len != 0) {
                const first = tran.str.?.get(1);
                if (first == tmp_tp.str.?.get(tmp_tp.len) and (first == types.tpd_span or first == types.tpd_prompt or first == types.tpd_environment or first == types.tpd_smart or first == types.tpd_exact or first == types.tpd_lit)) {
                    tran.dlm = first;
                    tran.len -= 1;
                    tran.str.?.erase(1, 1);
                    tmp_tp.len -= 1;
                    if (!try tparAnalyse(allocator, editor, frame, cmd, tran, depth + 1, this_tp)) {
                        return false;
                    }
                }
            }
        }

        switch (delim) {
            types.tpd_span => if (!try tparSubstitute(editor, allocator, tran, cmd, this_tp)) return false,
            types.tpd_environment => {
                if (editor.file_data.old_cmds) {
                    emitMessage(editor, reserved_tpd_message);
                    return false;
                }
                if (!try tparEnquire(allocator, editor, frame, tran)) {
                    return false;
                }
            },
            types.tpd_prompt => {
                if (editor.ludwig_mode != .ludwig_screen) {
                    emitMessage(editor, interactive_mode_only_message);
                    return false;
                }

                const prompt = if (tran.len == 0)
                    editor.dflt_prompts[@intFromEnum(editor.cmd_attrib[@intFromEnum(cmd)].tpar_info[@intCast(this_tp)].prompt_name)]
                else
                    tran.str.?.slice(1, tran.len);

                if (cmd == .cmd_verify) {
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
                    tran.str = try str_object.newStrObjectFrom(allocator, response);
                    tran.len = 1;
                    tran.dlm = 0;
                } else {
                    if (tran.con != null) {
                        emitMessage(editor, prompts_one_line_message);
                        return false;
                    }
                    const response = try interactive_io.readPromptLineWithOptions(allocator, prompt, .{
                        .editor = editor,
                        .frame = frame,
                        .max_tp = @max(editor.cmd_attrib[@intFromEnum(cmd)].tp_count, 1),
                        .this_tp = this_tp,
                    });
                    tran.str = try str_object.newStrObjectFrom(allocator, response);
                    tran.len = @intCast(response.len);
                    tran.dlm = 0;
                }
            },
            else => ended = true,
        }
    }
    return !editor.tt_control_c;
}

pub fn trim(request: *types.TParObject) void {
    if (request.len <= 0) {
        return;
    }
    const original_len = request.len;
    var index: isize = 1;
    while (index <= request.len and request.str.?.get(index) == ' ') : (index += 1) {}
    request.len -= index - 1;
    if (request.len > 0) {
        request.str.?.erase(index - 1, 1);
        request.str.?.applyN(chars.chToUpper, request.len, 1);
    }
    if (request.len < original_len) {
        request.str.?.fill(' ', request.len + 1, original_len);
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
    if (editor.cmd_attrib[@intFromEnum(cmd)].tpar_info[1].trim_reply) {
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
    if (tpar == null or tpar.?.nxt == null) {
        return false;
    }

    try tparDuplicateCon(allocator, tpar.?, trn1);
    try tparDuplicateCon(allocator, tpar.?.nxt.?, trn2);

    if (!try tparAnalyse(allocator, editor, frame, cmd, trn1, 1, 1)) {
        return false;
    }
    if (trn1.len != 0 and !try tparAnalyse(allocator, editor, frame, cmd, trn2, 1, 2)) {
        return false;
    }
    if (editor.cmd_attrib[@intFromEnum(cmd)].tpar_info[1].trim_reply) {
        trim(trn1);
    }
    if (editor.cmd_attrib[@intFromEnum(cmd)].tpar_info[2].trim_reply) {
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
        .str = try str_object.newStrObjectFrom(allocator, "123"),
        .len = 3,
    };
    var mark_three = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "3"),
        .len = 1,
    };
    var mark_equals = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "="),
        .len = 1,
    };
    try std.testing.expectEqual(@as(?isize, 123), tparToInt(&digits, &pos));
    try std.testing.expectEqual(@as(?isize, 3), tparToMark(&mark_three));
    try std.testing.expectEqual(@as(?isize, types.mark_equals), tparToMark(&mark_equals));

    var second = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "two"),
        .len = 3,
    };
    var third = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "three"),
        .len = 5,
    };
    second.con = &third;
    var first = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "one"),
        .len = 3,
        .nxt = &second,
    };
    const duplicate = (try tparDuplicate(allocator, &first)).?;
    try std.testing.expect(duplicate != &first);
    try std.testing.expect(duplicate.str != first.str);
    try std.testing.expectEqualStrings("one", duplicate.str.?.slice(1, 3));
    try std.testing.expect(duplicate.nxt != null);
    try std.testing.expectEqualStrings("two", duplicate.nxt.?.str.?.slice(1, 3));
    try std.testing.expect(duplicate.nxt.?.con != null);
    try std.testing.expectEqualStrings("three", duplicate.nxt.?.con.?.str.?.slice(1, 5));
}

test "tpar span substitution enquiries and analysis work in batch mode" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{
        "Hello World",
        "Line2",
    });
    editor.terminal_info = .{ .name = "tty", .width = 80, .height = 24 };
    editor.file_data.old_cmds = false;

    var mark1: ?*types.MarkObject = null;
    var mark2: ?*types.MarkObject = null;
    try @import("mark.zig").markCreate(allocator, fixture.content_lines[0], 7, &mark1);
    try @import("mark.zig").markCreate(allocator, fixture.content_lines[1], 6, &mark2);
    try std.testing.expect(try span_ops.spanCreate(&editor, allocator, "TEST", mark1.?, mark2.?));

    var substitute = types.TParObject{
        .str = try str_object.newBlankStrObject(allocator, types.max_str_len),
        .len = 4,
        .dlm = types.tpd_span,
    };
    try substitute.str.?.assign("TEST");
    try std.testing.expect(try tparSubstitute(&editor, allocator, &substitute, .cmd_replace, 2));
    try std.testing.expectEqualStrings("World", substitute.str.?.slice(1, 5));
    try std.testing.expect(substitute.con != null);
    try std.testing.expectEqualStrings("Line2", substitute.con.?.str.?.slice(1, 5));

    const version_enquiry = "LUDWIG-VERSION";
    var enquiry = types.TParObject{
        .str = try str_object.newBlankStrObject(allocator, types.max_str_len),
        .len = version_enquiry.len,
        .dlm = types.tpd_environment,
    };
    try enquiry.str.?.assign(version_enquiry);
    try std.testing.expect(try tparEnquire(allocator, &editor, fixture.frame, &enquiry));
    try std.testing.expectEqualStrings(types.ludwig_reader, enquiry.str.?.slice(1, enquiry.len));

    const frame_enquiry = "FRAME-MODIFIED";
    var analysed = types.TParObject{
        .str = try str_object.newBlankStrObject(allocator, types.max_str_len),
        .len = frame_enquiry.len,
        .dlm = types.tpd_environment,
    };
    try analysed.str.?.assign(frame_enquiry);
    try std.testing.expect(try tparAnalyse(allocator, &editor, fixture.frame, .cmd_get, &analysed, 1, 1));
    try std.testing.expectEqualStrings("N", analysed.str.?.slice(1, analysed.len));
}

test "tpar message helpers queue interactive parse failures" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.ludwig_mode = .ludwig_screen;

    var bad_int = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "ABC"),
        .len = 3,
    };
    var pos: isize = 1;
    try std.testing.expectEqual(@as(?isize, null), tparToIntMessage(&editor, &bad_int, &pos));
    try std.testing.expectEqualStrings(invalid_integer_message, interactive_io.takeStatusMessage().?);

    var bad_mark = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, ""),
        .len = 0,
    };
    try std.testing.expectEqual(@as(?isize, null), tparToMarkMessage(&editor, &bad_mark));
    try std.testing.expectEqualStrings(illegal_mark_number_message, interactive_io.takeStatusMessage().?);
}

test "tpar substitution and enquiry queue interactive failure messages" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.ludwig_mode = .ludwig_screen;

    var substitute = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "MISSING"),
        .len = "MISSING".len,
    };
    try std.testing.expect(!(try tparSubstitute(&editor, allocator, &substitute, .cmd_replace, 1)));
    try std.testing.expectEqualStrings("No such span.", interactive_io.takeStatusMessage().?);

    var enquiry = types.TParObject{
        .str = try str_object.newBlankStrObject(allocator, types.max_str_len),
        .len = "BOGUS-THING".len,
    };
    try enquiry.str.?.assign("BOGUS-THING");
    try std.testing.expect(!(try tparEnquire(allocator, &editor, null, &enquiry)));
    try std.testing.expectEqualStrings(unknown_item_message, interactive_io.takeStatusMessage().?);
    try std.testing.expect(editor.exit_abort);
}

test "tpar get helpers duplicate analyse and trim replies" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{"ignored"});
    editor.file_data.old_cmds = false;

    var source1 = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "  42"),
        .len = 4,
        .dlm = 0,
    };
    var out1: types.TParObject = .{};
    try std.testing.expect(try tparGet1(allocator, &editor, fixture.frame, &source1, .cmd_equal_column, &out1));
    try std.testing.expectEqualStrings("42", out1.str.?.slice(1, out1.len));

    var source2 = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "FRAME-MODIFIED"),
        .len = 14,
        .dlm = types.tpd_environment,
    };
    source1.nxt = &source2;
    var trn1: types.TParObject = .{};
    var trn2: types.TParObject = .{};
    try std.testing.expect(try tparGet2(allocator, &editor, fixture.frame, &source1, .cmd_replace, &trn1, &trn2));
    try std.testing.expectEqualStrings("  42", trn1.str.?.slice(1, trn1.len));
    try std.testing.expectEqualStrings("N", trn2.str.?.slice(1, trn2.len));
}

test "tpar verify prompt retries invalid replies in screen mode" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.ludwig_mode = .ludwig_screen;
    editor.terminal_info = .{ .width = 80, .height = 24 };

    const fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{"alpha"});

    var prompt = types.TParObject{
        .str = try str_object.newBlankStrObject(allocator, 0),
        .dlm = types.tpd_prompt,
    };
    var reply: types.TParObject = .{};

    interactive_io.testing.installInput("\x011Q");
    defer interactive_io.testing.clearInput();
    interactive_io.resetTestBeepCount();

    try std.testing.expect(try tparGet1(allocator, &editor, fixture.frame, &prompt, .cmd_verify, &reply));
    try std.testing.expectEqualStrings("Q", reply.str.?.slice(1, reply.len));
    try std.testing.expectEqual(@as(usize, 1), interactive_io.getTestBeepCount());
}
