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
    new_eql.* = frame.dot.?.*;
    switch (rept) {
        .lead_param_none, .lead_param_plus, .lead_param_p_int => {
            if (frame.dot.?.col - count >= 1) {
                frame.dot.?.col -= count;
                return true;
            }
        },
        .lead_param_p_indef => {
            if (frame.dot.?.col >= frame.margin_left) {
                frame.dot.?.col = frame.margin_left;
                return true;
            }
        },
        else => {},
    }
    return false;
}

pub fn doCmdRight(frame: *types.FrameObject, rept: types.LeadParam, count: isize, new_eql: *types.MarkObject) bool {
    new_eql.* = frame.dot.?.*;
    switch (rept) {
        .lead_param_none, .lead_param_plus, .lead_param_p_int => {
            if (frame.dot.?.col + count <= types.max_str_len_p1) {
                frame.dot.?.col += count;
                return true;
            }
        },
        .lead_param_p_indef => {
            if (frame.dot.?.col <= frame.margin_right) {
                frame.dot.?.col = frame.margin_right;
                return true;
            }
        },
        else => {},
    }
    return false;
}

pub fn doCmdTabBacktab(frame: *types.FrameObject, step: isize, count: isize, new_eql: *types.MarkObject) bool {
    new_eql.* = frame.dot.?.*;
    var new_col = frame.dot.?.col;
    var counter: isize = 1;
    while (counter <= count) : (counter += 1) {
        while (true) {
            new_col += step;
            if (new_col <= 0 or new_col >= types.max_str_len_p1 or frame.tab_stops[@intCast(new_col)] or new_col == frame.margin_left or new_col == frame.margin_right) {
                break;
            }
        }
        if (new_col <= 0 or new_col >= types.max_str_len_p1) {
            return false;
        }
    }
    frame.dot.?.col = new_col;
    return true;
}

pub fn doCmdHome(screen: *const types.ScreenState, frame: *types.FrameObject, new_eql: *types.MarkObject) bool {
    new_eql.* = frame.dot.?.*;
    if (frame == screen.frame) {
        const top_line = screen.top_line orelse return true;
        frame.dot.?.line = top_line;
        frame.dot.?.col = frame.scr_offset + 1;
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
    var dot_line = frame.dot.?.line;
    const line_nr = line_ops.lineToNumber(dot_line);
    switch (rept) {
        .lead_param_none, .lead_param_plus, .lead_param_p_int => {
            if (line_nr - count > 0) {
                if (count < types.max_group_lines / 2) {
                    var counter: isize = 1;
                    while (counter <= count) : (counter += 1) {
                        dot_line = dot_line.b_link.?;
                    }
                } else {
                    dot_line = line_ops.lineFromNumber(frame, line_nr - count) orelse return false;
                }
            } else {
                return false;
            }
        },
        .lead_param_p_indef => dot_line = frame.first_group.?.first_line.?,
        else => {},
    }
    new_eql.* = frame.dot.?.*;
    try mark_ops.markCreate(allocator, dot_line, frame.dot.?.col, &frame.dot);
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
    var dot_line = frame.dot.?.line;
    const line_nr = line_ops.lineToNumber(dot_line);
    switch (rept) {
        .lead_param_none, .lead_param_plus, .lead_param_p_int => {
            if (line_nr + count <= eop_line_nr) {
                if (count < types.max_group_lines / 2) {
                    var counter: isize = 1;
                    while (counter <= count and dot_line.f_link != null) : (counter += 1) {
                        dot_line = dot_line.f_link.?;
                    }
                } else {
                    dot_line = line_ops.lineFromNumber(frame, line_nr + count) orelse return false;
                }
            }
        },
        .lead_param_p_indef => dot_line = frame.last_group.?.last_line.?,
        else => {},
    }
    new_eql.* = frame.dot.?.*;
    try mark_ops.markCreate(allocator, dot_line, frame.dot.?.col, &frame.dot);
    return true;
}

pub fn doCmdReturn(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    count: isize,
    new_eql: *types.MarkObject,
    eop_line_nr: *isize,
) !bool {
    new_eql.* = frame.dot.?.*;
    var dot_line = frame.dot.?.line;
    var dot_col = frame.dot.?.col;
    var counter: isize = 1;
    while (counter <= count) : (counter += 1) {
        if (dot_line.f_link == null) {
            try text.textRealizeNull(allocator, dot_line);
            eop_line_nr.* += 1;
            dot_line = dot_line.b_link.?;
            if (counter == 1) {
                new_eql.line = dot_line;
            }
        }
        dot_col = text.textReturnCol(dot_line, dot_col, false);
        dot_line = dot_line.f_link.?;
    }
    try mark_ops.markCreate(allocator, dot_line, dot_col, &frame.dot);
    return true;
}

test "isArrowCommand identifies supported movement commands" {
    try std.testing.expect(isArrowCommand(.CmdReturn));
    try std.testing.expect(isArrowCommand(.CmdLeft));
    try std.testing.expect(!isArrowCommand(.CmdDeleteLine));
}

test "left and right commands obey bounds and margins" {
    var frame = types.FrameObject{
        .dot = undefined,
        .margin_left = 5,
        .margin_right = 80,
    };
    var dot_line = types.LineHdrObject{};
    var dot = types.MarkObject{ .line = &dot_line, .col = 10 };
    frame.dot = &dot;

    var eql = types.MarkObject{ .line = &dot_line, .col = 0 };
    try std.testing.expect(doCmdLeft(&frame, .lead_param_none, 1, &eql));
    try std.testing.expectEqual(@as(isize, 9), frame.dot.?.col);
    try std.testing.expect(doCmdRight(&frame, .lead_param_p_indef, 0, &eql));
    try std.testing.expectEqual(@as(isize, 80), frame.dot.?.col);
}

test "tab and backtab follow tab stops and margins" {
    var frame = types.FrameObject{
        .dot = undefined,
        .margin_left = 1,
        .margin_right = 80,
    };
    frame.tab_stops[10] = true;
    frame.tab_stops[20] = true;
    frame.tab_stops[30] = true;
    var dot_line = types.LineHdrObject{};
    var dot = types.MarkObject{ .line = &dot_line, .col = 5 };
    frame.dot = &dot;
    var eql = types.MarkObject{ .line = &dot_line, .col = 0 };
    try std.testing.expect(doCmdTabBacktab(&frame, 1, 2, &eql));
    try std.testing.expectEqual(@as(isize, 20), frame.dot.?.col);
    try std.testing.expect(doCmdTabBacktab(&frame, -1, 1, &eql));
    try std.testing.expectEqual(@as(isize, 10), frame.dot.?.col);
}

test "home command uses screen top line when frame is visible" {
    var top_line = types.LineHdrObject{};
    var current_line = types.LineHdrObject{};
    var frame = types.FrameObject{ .dot = undefined, .scr_offset = 10 };
    var dot = types.MarkObject{ .line = &current_line, .col = 50 };
    frame.dot = &dot;
    const screen = types.ScreenState{ .frame = &frame, .top_line = &top_line };
    var eql = types.MarkObject{ .line = &current_line, .col = 0 };
    _ = doCmdHome(&screen, &frame, &eql);
    try std.testing.expect(frame.dot.?.line == &top_line);
    try std.testing.expectEqual(@as(isize, 11), frame.dot.?.col);
}
