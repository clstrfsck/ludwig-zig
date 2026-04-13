const std = @import("std");
const chars = @import("chars.zig");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const str_object = @import("str_object.zig");
const text = @import("text.zig");
const types = @import("types.zig");

pub const CommandType = enum {
    case_command,
    ditto_command,
    unknown_command,
};

pub fn caseDittoCommand(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    command: types.Commands,
    rept: types.LeadParam,
    count: isize,
    from_span: bool,
    edit_mode: types.ModeType,
    previous_mode: types.ModeType,
) !bool {
    const insert = (command == .cmd_ditto_up or command == .cmd_ditto_down) and
        (edit_mode == .mode_insert or (edit_mode == .mode_command and previous_mode == .mode_insert));

    const old_dot_col = frame.dot.?.col;
    var other_line: ?*types.LineHdrObject = switch (command) {
        .cmd_case_up, .cmd_case_low, .cmd_case_edit => frame.dot.?.line,
        .cmd_ditto_up => frame.dot.?.line.b_link,
        .cmd_ditto_down => frame.dot.?.line.f_link,
        else => null,
    };

    if ((command == .cmd_ditto_up or command == .cmd_ditto_down) and insert and
        (rept == .lead_param_minus or rept == .lead_param_n_int or rept == .lead_param_n_indef))
    {
        return false;
    }

    var cmd_valid = other_line != null;
    var first_col: isize = frame.dot.?.col;
    var new_col: isize = frame.dot.?.col;
    var count_mut = count;

    if (cmd_valid) {
        switch (rept) {
            .lead_param_none, .lead_param_plus, .lead_param_p_int => {
                if (count_mut != 0 and frame.dot.?.col + count_mut > other_line.?.used + 1) {
                    cmd_valid = false;
                }
                first_col = frame.dot.?.col;
                new_col = frame.dot.?.col + count_mut;
            },
            .lead_param_p_indef => {
                count_mut = other_line.?.used + 1 - frame.dot.?.col;
                if (count_mut < 0) cmd_valid = false;
                first_col = frame.dot.?.col;
                new_col = other_line.?.used + 1;
            },
            .lead_param_minus, .lead_param_n_int => {
                count_mut = -count_mut;
                if (count_mut >= frame.dot.?.col) {
                    cmd_valid = false;
                } else {
                    first_col = frame.dot.?.col - count_mut;
                }
                new_col = first_col;
            },
            .lead_param_n_indef => {
                count_mut = frame.dot.?.col - 1;
                first_col = 1;
                new_col = 1;
            },
            else => {},
        }
    }

    var cmd_status = false;
    if (cmd_valid) {
        const available = other_line.?.used + 1 - first_col;
        const new_str = if (available > 0)
            try str_object.newStrObjectCopy(allocator, other_line.?.str.?, first_col, available, count_mut)
        else
            try str_object.newBlankStrObject(allocator, @intCast(count_mut));
        defer new_str.destroy();

        switch (command) {
            .cmd_case_up => new_str.applyN(chars.chToUpper, count_mut, 1),
            .cmd_case_low => new_str.applyN(chars.chToLower, count_mut, 1),
            .cmd_case_edit => {
                var ch: u8 = if (1 < first_col and first_col <= other_line.?.used)
                    other_line.?.str.?.get(first_col - 1)
                else
                    ' ';
                var j: isize = 1;
                while (j <= count_mut) : (j += 1) {
                    if (chars.chIsLetter(ch)) {
                        ch = chars.chToLower(new_str.get(j));
                    } else {
                        ch = chars.chToUpper(new_str.get(j));
                    }
                    new_str.set(j, ch);
                }
            },
            .cmd_ditto_up, .cmd_ditto_down => {},
            else => cmd_valid = false,
        }

        if (cmd_valid) {
            frame.dot.?.col = first_col;
            const success = if (insert)
                try text.textInsert(allocator, true, 1, new_str, count_mut, frame.dot.?)
            else
                try text.textOvertype(allocator, true, 1, new_str, count_mut, frame.dot.?);

            if (success) {
                frame.dot.?.col = new_col;
                cmd_status = true;
            }
        }
    }

    if (cmd_status) {
        frame.text_modified = true;
        try mark_ops.markCreate(allocator, frame.dot.?.line, frame.dot.?.col, &frame.marks[types.mark_modified]);
        try mark_ops.markCreate(allocator, frame.dot.?.line, old_dot_col, &frame.marks[types.mark_equals]);
    }
    return cmd_status or !from_span;
}

fn buildFrame(
    allocator: std.mem.Allocator,
    contents: []const []const u8,
) !line_ops.FrameFixture {
    return line_ops.createContentFrame(allocator, contents);
}

fn moveDot(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    line: *types.LineHdrObject,
    col: isize,
) !void {
    try mark_ops.markCreate(allocator, line, col, &frame.dot);
}

test "case ditto rejects negative ditto params in insert contexts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try buildFrame(allocator, &[_][]const u8{ "UPPER", "lower" });
    try moveDot(allocator, fixture.frame, fixture.content_lines[1], 1);
    try std.testing.expect(!(try caseDittoCommand(
        allocator,
        fixture.frame,
        .cmd_ditto_up,
        .lead_param_minus,
        -1,
        true,
        .mode_insert,
        .mode_command,
    )));
    try std.testing.expect(!(try caseDittoCommand(
        allocator,
        fixture.frame,
        .cmd_ditto_down,
        .lead_param_n_int,
        -1,
        true,
        .mode_command,
        .mode_insert,
    )));
}

test "case commands rewrite the current line in place" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const up_fixture = try buildFrame(allocator, &[_][]const u8{"hello world"});
    try std.testing.expect(try caseDittoCommand(
        allocator,
        up_fixture.frame,
        .cmd_case_up,
        .lead_param_none,
        5,
        true,
        .mode_command,
        .mode_command,
    ));
    try std.testing.expectEqualStrings("HELLO world", line_ops.getLineContent(up_fixture.content_lines[0]));

    const low_fixture = try buildFrame(allocator, &[_][]const u8{"HELLO WORLD"});
    try std.testing.expect(try caseDittoCommand(
        allocator,
        low_fixture.frame,
        .cmd_case_low,
        .lead_param_none,
        5,
        true,
        .mode_command,
        .mode_command,
    ));
    try std.testing.expectEqualStrings("hello WORLD", line_ops.getLineContent(low_fixture.content_lines[0]));

    const edit_fixture = try buildFrame(allocator, &[_][]const u8{"HeLLo WoRLd"});
    try std.testing.expect(try caseDittoCommand(
        allocator,
        edit_fixture.frame,
        .cmd_case_edit,
        .lead_param_none,
        5,
        true,
        .mode_command,
        .mode_command,
    ));
    try std.testing.expectEqualStrings("Hello WoRLd", line_ops.getLineContent(edit_fixture.content_lines[0]));
}

test "ditto commands copy from adjacent lines with repeat semantics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const plus_fixture = try buildFrame(allocator, &[_][]const u8{ "ABCDEFGHIJ", "1234567890" });
    try moveDot(allocator, plus_fixture.frame, plus_fixture.content_lines[1], 3);
    try std.testing.expect(try caseDittoCommand(
        allocator,
        plus_fixture.frame,
        .cmd_ditto_up,
        .lead_param_plus,
        4,
        true,
        .mode_command,
        .mode_command,
    ));
    try std.testing.expectEqualStrings("12CDEF7890", line_ops.getLineContent(plus_fixture.content_lines[1]));

    const pindef_fixture = try buildFrame(allocator, &[_][]const u8{ "COMPLETE LINE", "short" });
    try moveDot(allocator, pindef_fixture.frame, pindef_fixture.content_lines[1], 3);
    try std.testing.expect(try caseDittoCommand(
        allocator,
        pindef_fixture.frame,
        .cmd_ditto_up,
        .lead_param_p_indef,
        0,
        true,
        .mode_command,
        .mode_command,
    ));
    try std.testing.expectEqualStrings("shMPLETE LINE", line_ops.getLineContent(pindef_fixture.content_lines[1]));
}

test "ditto commands honor backward copy parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const minus_fixture = try buildFrame(allocator, &[_][]const u8{ "ABCDEFGHIJ", "1234567890" });
    try moveDot(allocator, minus_fixture.frame, minus_fixture.content_lines[1], 6);
    try std.testing.expect(try caseDittoCommand(
        allocator,
        minus_fixture.frame,
        .cmd_ditto_up,
        .lead_param_minus,
        -3,
        true,
        .mode_command,
        .mode_command,
    ));
    try std.testing.expectEqualStrings("12CDE67890", line_ops.getLineContent(minus_fixture.content_lines[1]));
    try std.testing.expectEqual(@as(isize, 3), minus_fixture.frame.dot.?.col);

    const nindef_fixture = try buildFrame(allocator, &[_][]const u8{ "PREFIXSUFFIX", "lowercase text" });
    try moveDot(allocator, nindef_fixture.frame, nindef_fixture.content_lines[1], 7);
    try std.testing.expect(try caseDittoCommand(
        allocator,
        nindef_fixture.frame,
        .cmd_ditto_up,
        .lead_param_n_indef,
        0,
        true,
        .mode_command,
        .mode_command,
    ));
    try std.testing.expectEqualStrings("PREFIXase text", line_ops.getLineContent(nindef_fixture.content_lines[1]));
    try std.testing.expectEqual(@as(isize, 1), nindef_fixture.frame.dot.?.col);
}
