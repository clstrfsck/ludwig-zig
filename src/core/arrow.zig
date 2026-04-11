const std = @import("std");
const mark_ops = @import("mark.zig");
const text = @import("text.zig");
const types = @import("types.zig");
const line_ops = @import("line.zig");

fn isArrowCommand(command: types.Commands) bool {
    return switch (command) {
        .CmdReturn,
        .CmdHome,
        .CmdTab,
        .CmdBacktab,
        .CmdLeft,
        .CmdRight,
        .CmdDown,
        .CmdUp,
        => true,
        else => false,
    };
}

pub fn doCmdLeft(frame: *types.FrameObject, rept: types.LeadParam, count: isize, new_eql: *types.MarkObject) bool {
    new_eql.* = frame.Dot.?.*;
    switch (rept) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            if (frame.Dot.?.Col - count >= 1) {
                frame.Dot.?.Col -= count;
                return true;
            }
        },
        .LeadParamPIndef => {
            if (frame.Dot.?.Col >= frame.MarginLeft) {
                frame.Dot.?.Col = frame.MarginLeft;
                return true;
            }
        },
        else => {},
    }
    return false;
}

pub fn doCmdRight(frame: *types.FrameObject, rept: types.LeadParam, count: isize, new_eql: *types.MarkObject) bool {
    new_eql.* = frame.Dot.?.*;
    switch (rept) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            if (frame.Dot.?.Col + count <= types.MaxStrLenP) {
                frame.Dot.?.Col += count;
                return true;
            }
        },
        .LeadParamPIndef => {
            if (frame.Dot.?.Col <= frame.MarginRight) {
                frame.Dot.?.Col = frame.MarginRight;
                return true;
            }
        },
        else => {},
    }
    return false;
}

pub fn doCmdTabBacktab(frame: *types.FrameObject, step: isize, count: isize, new_eql: *types.MarkObject) bool {
    new_eql.* = frame.Dot.?.*;
    var new_col = frame.Dot.?.Col;
    var counter: isize = 1;
    while (counter <= count) : (counter += 1) {
        while (true) {
            new_col += step;
            if (new_col <= 0 or new_col >= types.MaxStrLenP or frame.TabStops[@intCast(new_col)] or new_col == frame.MarginLeft or new_col == frame.MarginRight) {
                break;
            }
        }
        if (new_col <= 0 or new_col >= types.MaxStrLenP) {
            return false;
        }
    }
    frame.Dot.?.Col = new_col;
    return true;
}

pub fn doCmdHome(screen: *const types.ScreenState, frame: *types.FrameObject, new_eql: *types.MarkObject) bool {
    new_eql.* = frame.Dot.?.*;
    if (frame == screen.Frame) {
        const top_line = screen.TopLine orelse return true;
        frame.Dot.?.Line = top_line;
        frame.Dot.?.Col = frame.ScrOffset + 1;
    }
    return true;
}

pub fn doCmdUp(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
    new_eql: *types.MarkObject,
) !bool {
    var dot_line = frame.Dot.?.Line;
    const line_nr = line_ops.lineToNumber(dot_line);
    switch (rept) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            if (line_nr - count > 0) {
                if (count < types.MaxGroupLines / 2) {
                    var counter: isize = 1;
                    while (counter <= count) : (counter += 1) {
                        dot_line = dot_line.BLink.?;
                    }
                } else {
                    dot_line = line_ops.lineFromNumber(frame, line_nr - count) orelse return false;
                }
            } else {
                return false;
            }
        },
        .LeadParamPIndef => dot_line = frame.FirstGroup.?.FirstLine.?,
        else => {},
    }
    new_eql.* = frame.Dot.?.*;
    try mark_ops.markCreate(allocator, dot_line, frame.Dot.?.Col, &frame.Dot);
    return true;
}

pub fn doCmdDown(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
    new_eql: *types.MarkObject,
    eop_line_nr: isize,
) !bool {
    var dot_line = frame.Dot.?.Line;
    const line_nr = line_ops.lineToNumber(dot_line);
    switch (rept) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            if (line_nr + count <= eop_line_nr) {
                if (count < types.MaxGroupLines / 2) {
                    var counter: isize = 1;
                    while (counter <= count and dot_line.FLink != null) : (counter += 1) {
                        dot_line = dot_line.FLink.?;
                    }
                } else {
                    dot_line = line_ops.lineFromNumber(frame, line_nr + count) orelse return false;
                }
            }
        },
        .LeadParamPIndef => dot_line = frame.LastGroup.?.LastLine.?,
        else => {},
    }
    new_eql.* = frame.Dot.?.*;
    try mark_ops.markCreate(allocator, dot_line, frame.Dot.?.Col, &frame.Dot);
    return true;
}

pub fn doCmdReturn(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    count: isize,
    new_eql: *types.MarkObject,
    eop_line_nr: *isize,
) !bool {
    new_eql.* = frame.Dot.?.*;
    var dot_line = frame.Dot.?.Line;
    var dot_col = frame.Dot.?.Col;
    var counter: isize = 1;
    while (counter <= count) : (counter += 1) {
        if (dot_line.FLink == null) {
            try text.TextRealizeNull(allocator, dot_line);
            eop_line_nr.* += 1;
            dot_line = dot_line.BLink.?;
            if (counter == 1) {
                new_eql.Line = dot_line;
            }
        }
        dot_col = text.TextReturnCol(dot_line, dot_col, false);
        dot_line = dot_line.FLink.?;
    }
    try mark_ops.markCreate(allocator, dot_line, dot_col, &frame.Dot);
    return true;
}

test "isArrowCommand identifies supported movement commands" {
    try std.testing.expect(isArrowCommand(.CmdReturn));
    try std.testing.expect(isArrowCommand(.CmdLeft));
    try std.testing.expect(!isArrowCommand(.CmdDeleteLine));
}

test "left and right commands obey bounds and margins" {
    var frame = types.FrameObject{
        .Dot = undefined,
        .MarginLeft = 5,
        .MarginRight = 80,
    };
    var dot_line = types.LineHdrObject{};
    var dot = types.MarkObject{ .Line = &dot_line, .Col = 10 };
    frame.Dot = &dot;

    var eql = types.MarkObject{ .Line = &dot_line, .Col = 0 };
    try std.testing.expect(doCmdLeft(&frame, .LeadParamNone, 1, &eql));
    try std.testing.expectEqual(@as(isize, 9), frame.Dot.?.Col);
    try std.testing.expect(doCmdRight(&frame, .LeadParamPIndef, 0, &eql));
    try std.testing.expectEqual(@as(isize, 80), frame.Dot.?.Col);
}

test "tab and backtab follow tab stops and margins" {
    var frame = types.FrameObject{
        .Dot = undefined,
        .MarginLeft = 1,
        .MarginRight = 80,
    };
    frame.TabStops[10] = true;
    frame.TabStops[20] = true;
    frame.TabStops[30] = true;
    var dot_line = types.LineHdrObject{};
    var dot = types.MarkObject{ .Line = &dot_line, .Col = 5 };
    frame.Dot = &dot;
    var eql = types.MarkObject{ .Line = &dot_line, .Col = 0 };
    try std.testing.expect(doCmdTabBacktab(&frame, 1, 2, &eql));
    try std.testing.expectEqual(@as(isize, 20), frame.Dot.?.Col);
    try std.testing.expect(doCmdTabBacktab(&frame, -1, 1, &eql));
    try std.testing.expectEqual(@as(isize, 10), frame.Dot.?.Col);
}

test "home command uses screen top line when frame is visible" {
    var top_line = types.LineHdrObject{};
    var current_line = types.LineHdrObject{};
    var frame = types.FrameObject{ .Dot = undefined, .ScrOffset = 10 };
    var dot = types.MarkObject{ .Line = &current_line, .Col = 50 };
    frame.Dot = &dot;
    const screen = types.ScreenState{ .Frame = &frame, .TopLine = &top_line };
    var eql = types.MarkObject{ .Line = &current_line, .Col = 0 };
    _ = doCmdHome(&screen, &frame, &eql);
    try std.testing.expect(frame.Dot.?.Line == &top_line);
    try std.testing.expectEqual(@as(isize, 11), frame.Dot.?.Col);
}
