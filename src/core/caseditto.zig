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

pub fn getCommandType(command: types.Commands) CommandType {
    return switch (command) {
        .CmdCaseUp, .CmdCaseLow, .CmdCaseEdit => .case_command,
        .CmdDittoUp, .CmdDittoDown => .ditto_command,
        else => .unknown_command,
    };
}

pub fn CaseDittoCommand(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    command: types.Commands,
    rept: types.LeadParam,
    count: isize,
    from_span: bool,
    edit_mode: types.ModeType,
    previous_mode: types.ModeType,
) !bool {
    _ = getCommandType(command);
    const insert = (command == .CmdDittoUp or command == .CmdDittoDown) and
        (edit_mode == .ModeInsert or (edit_mode == .ModeCommand and previous_mode == .ModeInsert));

    const old_dot_col = frame.Dot.?.Col;
    var other_line: ?*types.LineHdrObject = switch (command) {
        .CmdCaseUp, .CmdCaseLow, .CmdCaseEdit => frame.Dot.?.Line,
        .CmdDittoUp => frame.Dot.?.Line.BLink,
        .CmdDittoDown => frame.Dot.?.Line.FLink,
        else => null,
    };

    if ((command == .CmdDittoUp or command == .CmdDittoDown) and insert and
        (rept == .LeadParamMinus or rept == .LeadParamNInt or rept == .LeadParamNIndef))
    {
        return false;
    }

    var cmd_valid = other_line != null;
    var first_col: isize = frame.Dot.?.Col;
    var new_col: isize = frame.Dot.?.Col;
    var count_mut = count;

    if (cmd_valid) {
        switch (rept) {
            .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
                if (count_mut != 0 and frame.Dot.?.Col + count_mut > other_line.?.Used + 1) {
                    cmd_valid = false;
                }
                first_col = frame.Dot.?.Col;
                new_col = frame.Dot.?.Col + count_mut;
            },
            .LeadParamPIndef => {
                count_mut = other_line.?.Used + 1 - frame.Dot.?.Col;
                if (count_mut < 0) cmd_valid = false;
                first_col = frame.Dot.?.Col;
                new_col = other_line.?.Used + 1;
            },
            .LeadParamMinus, .LeadParamNInt => {
                count_mut = -count_mut;
                if (count_mut >= frame.Dot.?.Col) {
                    cmd_valid = false;
                } else {
                    first_col = frame.Dot.?.Col - count_mut;
                }
                new_col = first_col;
            },
            .LeadParamNIndef => {
                count_mut = frame.Dot.?.Col - 1;
                first_col = 1;
                new_col = 1;
            },
            else => {},
        }
    }

    var cmd_status = false;
    if (cmd_valid) {
        const available = other_line.?.Used + 1 - first_col;
        const new_str = if (available > 0)
            try str_object.NewStrObjectCopy(allocator, other_line.?.Str.?, first_col, available, count_mut)
        else
            try str_object.NewBlankStrObject(allocator, @intCast(count_mut));
        defer new_str.destroy();

        switch (command) {
            .CmdCaseUp => new_str.ApplyN(chars.ChToUpper, count_mut, 1),
            .CmdCaseLow => new_str.ApplyN(chars.ChToLower, count_mut, 1),
            .CmdCaseEdit => {
                var ch: u8 = if (1 < first_col and first_col <= other_line.?.Used)
                    other_line.?.Str.?.Get(first_col - 1)
                else
                    ' ';
                var j: isize = 1;
                while (j <= count_mut) : (j += 1) {
                    if (chars.ChIsLetter(ch)) {
                        ch = chars.ChToLower(new_str.Get(j));
                    } else {
                        ch = chars.ChToUpper(new_str.Get(j));
                    }
                    new_str.Set(j, ch);
                }
            },
            .CmdDittoUp, .CmdDittoDown => {},
            else => cmd_valid = false,
        }

        if (cmd_valid) {
            frame.Dot.?.Col = first_col;
            const success = if (insert)
                try text.TextInsert(allocator, true, 1, new_str, count_mut, frame.Dot.?)
            else
                try text.TextOvertype(allocator, true, 1, new_str, count_mut, frame.Dot.?);

            if (success) {
                frame.Dot.?.Col = new_col;
                cmd_status = true;
            }
        }
    }

    if (cmd_status) {
        frame.TextModified = true;
        try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, frame.Dot.?.Col, &frame.Marks[types.MarkModified]);
        try mark_ops.MarkCreate(allocator, frame.Dot.?.Line, old_dot_col, &frame.Marks[types.MarkEquals]);
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
    try mark_ops.MarkCreate(allocator, line, col, &frame.Dot);
}

test "case ditto rejects negative ditto params in insert contexts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try buildFrame(allocator, &[_][]const u8{ "UPPER", "lower" });
    try moveDot(allocator, fixture.frame, fixture.content_lines[1], 1);
    try std.testing.expect(!(try CaseDittoCommand(
        allocator,
        fixture.frame,
        .CmdDittoUp,
        .LeadParamMinus,
        -1,
        true,
        .ModeInsert,
        .ModeCommand,
    )));
    try std.testing.expect(!(try CaseDittoCommand(
        allocator,
        fixture.frame,
        .CmdDittoDown,
        .LeadParamNInt,
        -1,
        true,
        .ModeCommand,
        .ModeInsert,
    )));
}

test "case commands rewrite the current line in place" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const up_fixture = try buildFrame(allocator, &[_][]const u8{"hello world"});
    try std.testing.expect(try CaseDittoCommand(
        allocator,
        up_fixture.frame,
        .CmdCaseUp,
        .LeadParamNone,
        5,
        true,
        .ModeCommand,
        .ModeCommand,
    ));
    try std.testing.expectEqualStrings("HELLO world", line_ops.getLineContent(up_fixture.content_lines[0]));

    const low_fixture = try buildFrame(allocator, &[_][]const u8{"HELLO WORLD"});
    try std.testing.expect(try CaseDittoCommand(
        allocator,
        low_fixture.frame,
        .CmdCaseLow,
        .LeadParamNone,
        5,
        true,
        .ModeCommand,
        .ModeCommand,
    ));
    try std.testing.expectEqualStrings("hello WORLD", line_ops.getLineContent(low_fixture.content_lines[0]));

    const edit_fixture = try buildFrame(allocator, &[_][]const u8{"HeLLo WoRLd"});
    try std.testing.expect(try CaseDittoCommand(
        allocator,
        edit_fixture.frame,
        .CmdCaseEdit,
        .LeadParamNone,
        5,
        true,
        .ModeCommand,
        .ModeCommand,
    ));
    try std.testing.expectEqualStrings("Hello WoRLd", line_ops.getLineContent(edit_fixture.content_lines[0]));
}

test "ditto commands copy from adjacent lines with repeat semantics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const plus_fixture = try buildFrame(allocator, &[_][]const u8{ "ABCDEFGHIJ", "1234567890" });
    try moveDot(allocator, plus_fixture.frame, plus_fixture.content_lines[1], 3);
    try std.testing.expect(try CaseDittoCommand(
        allocator,
        plus_fixture.frame,
        .CmdDittoUp,
        .LeadParamPlus,
        4,
        true,
        .ModeCommand,
        .ModeCommand,
    ));
    try std.testing.expectEqualStrings("12CDEF7890", line_ops.getLineContent(plus_fixture.content_lines[1]));

    const pindef_fixture = try buildFrame(allocator, &[_][]const u8{ "COMPLETE LINE", "short" });
    try moveDot(allocator, pindef_fixture.frame, pindef_fixture.content_lines[1], 3);
    try std.testing.expect(try CaseDittoCommand(
        allocator,
        pindef_fixture.frame,
        .CmdDittoUp,
        .LeadParamPIndef,
        0,
        true,
        .ModeCommand,
        .ModeCommand,
    ));
    try std.testing.expectEqualStrings("shMPLETE LINE", line_ops.getLineContent(pindef_fixture.content_lines[1]));
}

test "ditto commands honor backward copy parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const minus_fixture = try buildFrame(allocator, &[_][]const u8{ "ABCDEFGHIJ", "1234567890" });
    try moveDot(allocator, minus_fixture.frame, minus_fixture.content_lines[1], 6);
    try std.testing.expect(try CaseDittoCommand(
        allocator,
        minus_fixture.frame,
        .CmdDittoUp,
        .LeadParamMinus,
        -3,
        true,
        .ModeCommand,
        .ModeCommand,
    ));
    try std.testing.expectEqualStrings("12CDE67890", line_ops.getLineContent(minus_fixture.content_lines[1]));
    try std.testing.expectEqual(@as(isize, 3), minus_fixture.frame.Dot.?.Col);

    const nindef_fixture = try buildFrame(allocator, &[_][]const u8{ "PREFIXSUFFIX", "lowercase text" });
    try moveDot(allocator, nindef_fixture.frame, nindef_fixture.content_lines[1], 7);
    try std.testing.expect(try CaseDittoCommand(
        allocator,
        nindef_fixture.frame,
        .CmdDittoUp,
        .LeadParamNIndef,
        0,
        true,
        .ModeCommand,
        .ModeCommand,
    ));
    try std.testing.expectEqualStrings("PREFIXase text", line_ops.getLineContent(nindef_fixture.content_lines[1]));
    try std.testing.expectEqual(@as(isize, 1), nindef_fixture.frame.Dot.?.Col);
}
