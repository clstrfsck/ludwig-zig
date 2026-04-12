const std = @import("std");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const str_object = @import("str_object.zig");
const text = @import("text.zig");
const types = @import("types.zig");

fn blankString(allocator: std.mem.Allocator) !*str_object.StrObject {
    return str_object.newBlankStrObject(allocator, types.max_str_len);
}

fn normalizeLineCommandRepeat(rept: *types.LeadParam, count: *isize) void {
    if (rept.* == .LeadParamPIndef) {
        count.* = types.max_int;
    }
    if (rept.* == .LeadParamNone or rept.* == .LeadParamPlus) {
        count.* = 1;
        rept.* = .LeadParamPInt;
    }
}

fn validateNonBlankLineCount(frame: *types.FrameObject, count: isize) bool {
    var line_count = count;
    var this_line = frame.dot.?.Line;
    while (line_count > 0 and this_line.used > 0) {
        this_line = this_line.f_link orelse return false;
        line_count -= 1;
    }
    return line_count == 0;
}

fn moveDot(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    line: *types.LineHdrObject,
    col: isize,
) !void {
    try mark_ops.markCreate(allocator, line, col, &frame.dot);
}

pub fn wordFill(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var here: ?*types.MarkObject = null;
    var there: ?*types.MarkObject = null;
    defer mark_ops.markDestroy(allocator, &here);
    defer mark_ops.markDestroy(allocator, &there);

    const blank = try blankString(allocator);
    defer blank.destroy();

    var leave_dot_alone = false;
    var rept_mut = rept;
    var count_mut = count;
    if (rept_mut == .LeadParamPIndef) {
        count_mut = types.max_int;
    }
    if (rept_mut == .LeadParamNone) {
        count_mut = 1;
        rept_mut = .LeadParamPInt;
    }
    if (rept_mut == .LeadParamPInt and !validateNonBlankLineCount(frame, count_mut)) {
        return false;
    }

    while (count_mut > 0 and frame.dot.?.Line.used > 0) {
        if (frame.dot.?.Line.f_link == null) {
            return false;
        }

        if (frame.dot.?.Line.b_link != null and frame.dot.?.Line.b_link.?.used != 0) {
            var start_char: isize = 1;
            while (frame.dot.?.Line.str.?.get(start_char) == ' ' and start_char < frame.dot.?.Line.used) {
                start_char += 1;
            }
            if (start_char < frame.margin_left and start_char < frame.dot.?.Line.used) {
                try mark_ops.markCreate(allocator, frame.dot.?.Line, start_char, &here);
                if (!try text.textInsert(allocator, true, 1, blank, frame.margin_left - start_char, here.?)) {
                    return false;
                }
                mark_ops.markDestroy(allocator, &here);
            } else {
                var end_char = frame.margin_left;
                if (end_char < frame.dot.?.Line.used) {
                    while (frame.dot.?.Line.str.?.get(end_char) == ' ' and end_char < frame.dot.?.Line.used) {
                        end_char += 1;
                    }
                    if (end_char > 1) {
                        try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.margin_left, &here);
                        try mark_ops.markCreate(allocator, frame.dot.?.Line, end_char, &there);
                        if (!try text.textRemove(allocator, here.?, there.?)) {
                            return false;
                        }
                        mark_ops.markDestroy(allocator, &here);
                        mark_ops.markDestroy(allocator, &there);
                    }
                }
            }
        }

        if (frame.dot.?.Line.used > frame.margin_right) {
            var end_char = frame.margin_right + 1;
            if (frame.dot.?.Line.str.?.get(end_char) != ' ') {
                while (frame.dot.?.Line.str.?.get(end_char) != ' ' and end_char > frame.margin_left) {
                    end_char -= 1;
                }
                if (end_char == frame.margin_left) {
                    return false;
                }
            }
            var start_char = end_char;
            while (frame.dot.?.Line.str.?.get(end_char) == ' ' and end_char > frame.margin_left) {
                end_char -= 1;
            }
            if (end_char == frame.margin_left) {
                return false;
            }
            while (frame.dot.?.Line.str.?.get(start_char) == ' ') {
                start_char += 1;
            }
            try mark_ops.markCreate(allocator, frame.dot.?.Line, start_char, &here);
            if (frame.dot.?.Col > end_char) {
                try mark_ops.markCreate(allocator, frame.dot.?.Line, end_char, &frame.dot);
            }
            if (!try text.textSplitLine(allocator, here.?, frame.margin_left, &there)) {
                return false;
            }
            mark_ops.markDestroy(allocator, &here);
            mark_ops.markDestroy(allocator, &there);
            if (rept_mut != .LeadParamPIndef) {
                count_mut += 1;
            }
        } else {
            while (true) {
                const space_to_add = frame.margin_right - frame.dot.?.Line.used - 1;
                if (space_to_add > 0 and frame.dot.?.Line.f_link.?.used != 0) {
                    const next_line = frame.dot.?.Line.f_link.?;
                    var start_char: isize = 1;
                    while (next_line.str.?.get(start_char) == ' ') {
                        start_char += 1;
                    }
                    var end_char = start_char;
                    var old_end = end_char;
                    while (end_char <= next_line.used) {
                        while (next_line.str.?.get(end_char) == ' ') {
                            end_char += 1;
                        }
                        while (next_line.str.?.get(end_char) != ' ' and end_char < next_line.used) {
                            end_char += 1;
                        }
                        if (end_char == next_line.used) {
                            end_char += 1;
                        }
                        if (space_to_add < (end_char - start_char)) {
                            end_char = next_line.used + 1;
                        } else {
                            old_end = end_char;
                        }
                    }

                    if ((old_end - start_char) <= space_to_add and old_end != start_char) {
                        var old_here: ?*types.MarkObject = null;
                        var old_there: ?*types.MarkObject = null;
                        defer mark_ops.markDestroy(allocator, &old_here);
                        defer mark_ops.markDestroy(allocator, &old_there);

                        try mark_ops.markCreate(allocator, next_line, start_char, &here);
                        try mark_ops.markCreate(allocator, next_line, start_char, &old_here);
                        try mark_ops.markCreate(allocator, next_line, old_end, &there);
                        try mark_ops.markCreate(allocator, next_line, old_end, &old_there);
                        frame.dot.?.Col = frame.dot.?.Line.used + 2;
                        if (!try text.textMove(allocator, true, 1, here.?, there.?, frame.dot.?, &here, &there)) {
                            return false;
                        }
                        try mark_ops.marksShift(allocator, next_line, old_here.?.Col, old_there.?.Col - old_here.?.Col, here.?.Line, here.?.Col);
                        try mark_ops.markCreate(allocator, next_line, 1, &old_here);
                        try mark_ops.markCreate(allocator, next_line, old_end, &old_there);
                        if (!try text.textRemove(allocator, old_here.?, old_there.?)) {
                            return false;
                        }

                        if (frame.dot.?.Line.f_link.?.used == 0) {
                            const this_line = frame.dot.?.Line.f_link.?;
                            try mark_ops.marksSqueeze(allocator, frame.dot.?.Line.f_link.?, 1, frame.dot.?.Line.f_link.?.f_link.?, 1);
                            line_ops.linesExtract(this_line, this_line);
                            count_mut -= 1;
                            if (count_mut > 0) {
                                continue;
                            }
                            leave_dot_alone = true;
                        }
                    }

                    if (count_mut > 0 and frame.dot.?.Line.f_link.?.used != 0) {
                        const next_line_after_pull = frame.dot.?.Line.f_link.?;
                        var next_start_char: isize = 1;
                        while (next_line_after_pull.str.?.get(next_start_char) == ' ') {
                            next_start_char += 1;
                        }
                        try mark_ops.markCreate(allocator, next_line_after_pull, next_start_char, &there);
                        if (next_start_char < frame.margin_left) {
                            if (!try text.textInsert(allocator, true, 1, blank, frame.margin_left - next_start_char, there.?)) {
                                return false;
                            }
                        } else {
                            try mark_ops.markCreate(allocator, next_line_after_pull, frame.margin_left, &here);
                            if (!try text.textRemove(allocator, here.?, there.?)) {
                                return false;
                            }
                        }
                    }
                }
                mark_ops.markDestroy(allocator, &here);
                mark_ops.markDestroy(allocator, &there);
                break;
            }
        }

        count_mut -= 1;
        if (!leave_dot_alone) {
            try moveDot(allocator, frame, frame.dot.?.Line.f_link.?, frame.margin_left);
        }
        frame.text_modified = true;
        try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &frame.marks[types.mark_modified]);
    }
    return (count_mut <= 0) or (rept_mut == .LeadParamPIndef);
}

pub fn wordCentre(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var here: ?*types.MarkObject = null;
    var there: ?*types.MarkObject = null;
    defer mark_ops.markDestroy(allocator, &here);
    defer mark_ops.markDestroy(allocator, &there);

    const blank = try blankString(allocator);
    defer blank.destroy();

    var rept_mut = rept;
    var count_mut = count;
    normalizeLineCommandRepeat(&rept_mut, &count_mut);
    if (rept_mut == .LeadParamPInt and !validateNonBlankLineCount(frame, count_mut)) {
        return false;
    }

    while (count_mut > 0 and frame.dot.?.Line.used > 0) {
        if (frame.dot.?.Line.f_link == null) return false;
        if (frame.dot.?.Line.used < frame.margin_left or frame.dot.?.Line.used > frame.margin_right) return false;

        var start_char: isize = 1;
        while (frame.dot.?.Line.str.?.get(start_char) == ' ') {
            start_char += 1;
        }
        if (start_char < frame.margin_left) return false;

        const space_to_add = @divTrunc(frame.margin_right - frame.margin_left - (frame.dot.?.Line.used - start_char), 2) - (start_char - frame.margin_left);
        if (space_to_add > 0) {
            try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.margin_left, &here);
            if (!try text.textInsert(allocator, true, 1, blank, space_to_add, here.?)) return false;
        } else if (space_to_add < 0) {
            try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.margin_left, &here);
            try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.margin_left - space_to_add, &there);
            if (!try text.textRemove(allocator, here.?, there.?)) return false;
        }

        count_mut -= 1;
        try moveDot(allocator, frame, frame.dot.?.Line.f_link.?, frame.margin_left);
        frame.text_modified = true;
        try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &frame.marks[types.mark_modified]);
    }
    return (count_mut <= 0) or (rept_mut == .LeadParamPIndef);
}

pub fn wordJustify(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var here: ?*types.MarkObject = null;
    defer mark_ops.markDestroy(allocator, &here);

    const blank = try blankString(allocator);
    defer blank.destroy();

    var rept_mut = rept;
    var count_mut = count;
    normalizeLineCommandRepeat(&rept_mut, &count_mut);
    if (rept_mut == .LeadParamPInt and !validateNonBlankLineCount(frame, count_mut)) {
        return false;
    }

    while (count_mut > 0 and frame.dot.?.Line.used > 0) {
        if (frame.dot.?.Line.f_link == null) return false;
        if (frame.dot.?.Line.f_link.?.used != 0) {
            if (frame.dot.?.Line.used > frame.margin_right) return false;

            var space_to_add = frame.margin_right - frame.dot.?.Line.used;
            var start_char = frame.margin_left;
            while (frame.dot.?.Line.str.?.get(start_char) == ' ' and start_char < frame.dot.?.Line.used) {
                start_char += 1;
            }
            const end_char = start_char;
            var holes: isize = 0;
            while (true) {
                while (frame.dot.?.Line.str.?.get(start_char) != ' ' and start_char < frame.dot.?.Line.used) {
                    start_char += 1;
                }
                while (frame.dot.?.Line.str.?.get(start_char) == ' ' and start_char < frame.dot.?.Line.used) {
                    start_char += 1;
                }
                holes += 1;
                if (!(start_char < frame.dot.?.Line.used)) break;
            }
            holes -= 1;

            var fill_ratio: f64 = 0.0;
            if (holes > 0) {
                fill_ratio = @as(f64, @floatFromInt(space_to_add)) / @as(f64, @floatFromInt(holes));
            }
            var debit: f64 = 0.0;
            start_char = end_char;
            var i: isize = 1;
            while (i <= holes) : (i += 1) {
                while (frame.dot.?.Line.str.?.get(start_char) != ' ') {
                    start_char += 1;
                }
                debit += fill_ratio;
                space_to_add = @intFromFloat(debit + 0.5);
                if (space_to_add > 0) {
                    here = null;
                    try mark_ops.markCreate(allocator, frame.dot.?.Line, start_char, &here);
                    if (!try text.textInsert(allocator, true, 1, blank, space_to_add, here.?)) return false;
                    mark_ops.markDestroy(allocator, &here);
                    debit -= @as(f64, @floatFromInt(space_to_add));
                }
                while (frame.dot.?.Line.str.?.get(start_char) == ' ') {
                    start_char += 1;
                }
            }
        }

        count_mut -= 1;
        try moveDot(allocator, frame, frame.dot.?.Line.f_link.?, frame.margin_left);
        frame.text_modified = true;
        try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &frame.marks[types.mark_modified]);
    }
    return (count_mut <= 0) or (rept_mut == .LeadParamPIndef);
}

pub fn wordSqueeze(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var here: ?*types.MarkObject = null;
    var there: ?*types.MarkObject = null;
    defer mark_ops.markDestroy(allocator, &here);
    defer mark_ops.markDestroy(allocator, &there);

    var rept_mut = rept;
    var count_mut = count;
    normalizeLineCommandRepeat(&rept_mut, &count_mut);
    if (rept_mut == .LeadParamPInt and !validateNonBlankLineCount(frame, count_mut)) {
        return false;
    }

    while (count_mut > 0 and frame.dot.?.Line.used > 0) {
        if (frame.dot.?.Line.f_link == null) return false;
        var start_char: isize = 1;
        while (frame.dot.?.Line.str.?.get(start_char) == ' ') {
            start_char += 1;
        }
        while (true) {
            while (frame.dot.?.Line.str.?.get(start_char) != ' ' and start_char < frame.dot.?.Line.used) {
                start_char += 1;
            }
            if (frame.dot.?.Line.str.?.get(start_char) != ' ') break;
            var end_char = start_char;
            while (frame.dot.?.Line.str.?.get(end_char) == ' ') {
                end_char += 1;
            }
            if ((end_char - start_char) > 1) {
                here = null;
                there = null;
                try mark_ops.markCreate(allocator, frame.dot.?.Line, start_char, &here);
                try mark_ops.markCreate(allocator, frame.dot.?.Line, end_char - 1, &there);
                if (!try text.textRemove(allocator, here.?, there.?)) return false;
                start_char = here.?.Col;
            } else {
                start_char = end_char;
            }
        }

        count_mut -= 1;
        try moveDot(allocator, frame, frame.dot.?.Line.f_link.?, frame.margin_left);
        frame.text_modified = true;
        try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &frame.marks[types.mark_modified]);
    }
    return (count_mut <= 0) or (rept_mut == .LeadParamPIndef);
}

pub fn wordRight(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var here: ?*types.MarkObject = null;
    var there: ?*types.MarkObject = null;
    defer mark_ops.markDestroy(allocator, &here);
    defer mark_ops.markDestroy(allocator, &there);

    const blank = try blankString(allocator);
    defer blank.destroy();

    var rept_mut = rept;
    var count_mut = count;
    normalizeLineCommandRepeat(&rept_mut, &count_mut);
    if (rept_mut == .LeadParamPInt and !validateNonBlankLineCount(frame, count_mut)) {
        return false;
    }

    while (count_mut > 0 and frame.dot.?.Line.used > 0) {
        if (frame.dot.?.Line.f_link == null) return false;
        if (frame.dot.?.Line.used < frame.margin_left or frame.dot.?.Line.used > frame.margin_right) return false;

        var start_char: isize = 1;
        while (frame.dot.?.Line.str.?.get(start_char) == ' ') {
            start_char += 1;
        }
        if (start_char < frame.margin_left) return false;

        const space_to_add = frame.margin_right - frame.dot.?.Line.used;
        if (space_to_add > 0) {
            try mark_ops.markCreate(allocator, frame.dot.?.Line, start_char, &here);
            if (!try text.textInsert(allocator, true, 1, blank, space_to_add, here.?)) return false;
        } else if (space_to_add < 0) {
            try mark_ops.markCreate(allocator, frame.dot.?.Line, start_char, &there);
            try mark_ops.markCreate(allocator, frame.dot.?.Line, start_char - space_to_add, &here);
            if (!try text.textRemove(allocator, there.?, here.?)) return false;
        }

        count_mut -= 1;
        try moveDot(allocator, frame, frame.dot.?.Line.f_link.?, frame.margin_left);
        frame.text_modified = true;
        try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &frame.marks[types.mark_modified]);
    }
    return (count_mut <= 0) or (rept_mut == .LeadParamPIndef);
}

pub fn wordLeft(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var here: ?*types.MarkObject = null;
    var there: ?*types.MarkObject = null;
    defer mark_ops.markDestroy(allocator, &here);
    defer mark_ops.markDestroy(allocator, &there);

    const blank = try blankString(allocator);
    defer blank.destroy();

    var rept_mut = rept;
    var count_mut = count;
    normalizeLineCommandRepeat(&rept_mut, &count_mut);
    if (rept_mut == .LeadParamPInt and !validateNonBlankLineCount(frame, count_mut)) {
        return false;
    }

    while (count_mut > 0 and frame.dot.?.Line.used > 0) {
        if (frame.dot.?.Line.f_link == null) return false;
        if (frame.dot.?.Line.used < frame.margin_left or frame.dot.?.Line.used > frame.margin_right) return false;

        var start_char: isize = 1;
        while (frame.dot.?.Line.str.?.get(start_char) == ' ') {
            start_char += 1;
        }
        if (start_char != frame.margin_left) {
            if (start_char < frame.margin_left) {
                try mark_ops.markCreate(allocator, frame.dot.?.Line, start_char, &here);
                if (!try text.textInsert(allocator, true, 1, blank, frame.margin_left - start_char, here.?)) return false;
            } else {
                try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.margin_left, &here);
                try mark_ops.markCreate(allocator, frame.dot.?.Line, start_char, &there);
                if (!try text.textRemove(allocator, here.?, there.?)) return false;
            }
        }

        count_mut -= 1;
        try moveDot(allocator, frame, frame.dot.?.Line.f_link.?, frame.margin_left);
        frame.text_modified = true;
        try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &frame.marks[types.mark_modified]);
    }
    return (count_mut <= 0) or (rept_mut == .LeadParamPIndef);
}

pub fn wordAdvanceWord(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var this_line = frame.dot.?.Line;
    var pos = frame.dot.?.Col;
    var count_mut = count;

    if (rept == .LeadParamMarker) {
        return false;
    }

    if (rept == .LeadParamNone or rept == .LeadParamPlus or rept == .LeadParamPIndef or (rept == .LeadParamPInt and count_mut != 0)) {
        if (rept == .LeadParamPIndef) {
            while (this_line.used != 0 and this_line.f_link != null) {
                this_line = this_line.f_link.?;
            }
            pos = 1;
            count_mut = 1;
        }

        outer: while (count_mut > 0) {
            while (true) {
                if (pos < this_line.used) {
                    if (this_line.str.?.get(pos) != ' ') {
                        pos += 1;
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            }

            if (pos >= this_line.used) {
                pos = 1;
                while (true) {
                    if (this_line.f_link == null) {
                        if (rept == .LeadParamPIndef) break :outer;
                        return false;
                    }
                    this_line = this_line.f_link.?;
                    if (!(this_line.used <= 0)) break;
                }
            }
            while (this_line.str.?.get(pos) == ' ') {
                pos += 1;
            }
            count_mut -= 1;
        }
        try moveDot(allocator, frame, this_line, pos);
    } else if (rept == .LeadParamNIndef) {
        while (this_line.used == 0 and this_line.b_link != null) {
            this_line = this_line.b_link.?;
        }
        while (this_line.used != 0 and this_line.b_link != null) {
            this_line = this_line.b_link.?;
        }
        pos = 1;
        while (this_line.used == 0) {
            if (this_line.f_link == null) return false;
            this_line = this_line.f_link.?;
        }
        while (this_line.str.?.get(pos) == ' ') {
            pos += 1;
        }
        try moveDot(allocator, frame, this_line, pos);
    } else {
        count_mut = -count_mut;
        if (pos > this_line.used) {
            pos = this_line.used;
        }
        while (true) {
            if (pos == 0 or this_line.f_link == null) {
                while (true) {
                    if (this_line.b_link == null) return false;
                    this_line = this_line.b_link.?;
                    pos = this_line.used;
                    if (pos > 0) break;
                }
            }
            while (this_line.str.?.get(pos) == ' ' and pos > 1) {
                pos -= 1;
            }
            if (pos == 1 and this_line.str.?.get(1) == ' ') {
                while (true) {
                    if (this_line.b_link == null) return false;
                    this_line = this_line.b_link.?;
                    pos = this_line.used;
                    if (!(pos <= 0)) break;
                }
            }
            while (this_line.str.?.get(pos) != ' ' and pos > 1) {
                pos -= 1;
            }
            count_mut -= 1;
            if (count_mut < 0) {
                if (this_line.str.?.get(pos) == ' ') pos += 1;
            } else {
                pos -= 1;
            }
            if (!(count_mut >= 0)) break;
        }
        try moveDot(allocator, frame, this_line, pos);
    }
    return true;
}

pub fn wordDeleteWord(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    frame_oops: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var old_pos: ?*types.MarkObject = null;
    var here: ?*types.MarkObject = null;
    var other_mark: ?*types.MarkObject = null;
    defer mark_ops.markDestroy(allocator, &old_pos);
    defer mark_ops.markDestroy(allocator, &here);
    defer mark_ops.markDestroy(allocator, &other_mark);

    if (rept == .LeadParamMarker) {
        return false;
    }

    try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &old_pos);
    if (!try wordAdvanceWord(allocator, frame, .LeadParamPInt, 0)) {
        return false;
    }
    try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &here);
    if (!try wordAdvanceWord(allocator, frame, rept, count)) {
        try moveDot(allocator, frame, old_pos.?.Line, old_pos.?.Col);
        return false;
    }

    const old_dot_col = frame.dot.?.Col;
    try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &other_mark);
    const line_nr = line_ops.lineToNumber(frame.dot.?.Line);
    const new_line_nr = line_ops.lineToNumber(here.?.Line);
    if (line_nr > new_line_nr or (line_nr == new_line_nr and frame.dot.?.Col > here.?.Col)) {
        const another_mark = here;
        here = other_mark;
        other_mark = another_mark;
    }

    var result = false;
    if (frame != frame_oops) {
        if (frame_oops.span == null) return false;
        try mark_ops.markCreate(allocator, frame_oops.last_group.?.last_line.?, 1, &frame_oops.span.?.mark_two);
        result = try text.textMove(allocator, false, 1, other_mark.?, here.?, frame_oops.span.?.mark_two.?, &frame_oops.marks[types.mark_equals], &frame_oops.dot);
    } else {
        result = try text.textRemove(allocator, other_mark.?, here.?);
    }
    if (line_nr != new_line_nr) {
        result = try text.textSplitLine(allocator, frame.dot.?, old_dot_col, &here);
    }
    return result;
}

fn buildWordFrame(
    allocator: std.mem.Allocator,
    contents: []const []const u8,
) !line_ops.FrameFixture {
    return line_ops.createContentFrame(allocator, contents);
}

fn expectLineContent(line: ?*const types.LineHdrObject, expected: []const u8) !void {
    try std.testing.expectEqualStrings(expected, line_ops.getLineContent(line));
}

test "word left aligns lines to the left margin" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try buildWordFrame(allocator, &[_][]const u8{ "hello", "    world" });
    fixture.frame.margin_left = 3;
    fixture.frame.margin_right = 20;

    try std.testing.expect(try wordLeft(allocator, fixture.frame, .LeadParamPInt, 2));
    try expectLineContent(fixture.content_lines[0], "  hello");
    try expectLineContent(fixture.content_lines[1], "  world");
    try std.testing.expect(fixture.frame.dot.?.Line == fixture.sentinel_line);
}

test "word right aligns content to the right margin" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try buildWordFrame(allocator, &[_][]const u8{"  hello"});
    fixture.frame.margin_left = 3;
    fixture.frame.margin_right = 10;
    try std.testing.expect(try wordRight(allocator, fixture.frame, .LeadParamNone, 1));
    try expectLineContent(fixture.content_lines[0], "     hello");
}

test "word centre shifts content toward the middle of margins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try buildWordFrame(allocator, &[_][]const u8{"      hello"});
    fixture.frame.margin_left = 3;
    fixture.frame.margin_right = 11;
    try std.testing.expect(try wordCentre(allocator, fixture.frame, .LeadParamNone, 1));
    try expectLineContent(fixture.content_lines[0], "    hello");
}

test "word justify expands interior holes when next line is nonblank" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try buildWordFrame(allocator, &[_][]const u8{ "  hello world", "next line" });
    fixture.frame.margin_left = 3;
    fixture.frame.margin_right = 20;
    try std.testing.expect(try wordJustify(allocator, fixture.frame, .LeadParamNone, 1));
    try std.testing.expectEqual(@as(isize, 20), fixture.content_lines[0].used);
}

test "word squeeze collapses repeated spaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try buildWordFrame(allocator, &[_][]const u8{"a   b   c"});
    try std.testing.expect(try wordSqueeze(allocator, fixture.frame, .LeadParamNone, 1));
    try expectLineContent(fixture.content_lines[0], "a b c");
}

test "word fill can split long lines and pull from the next line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const split_fixture = try buildWordFrame(allocator, &[_][]const u8{"hello world"});
    split_fixture.frame.margin_right = 10;
    try std.testing.expect(try wordFill(allocator, split_fixture.frame, .LeadParamNone, 1));
    try expectLineContent(split_fixture.content_lines[0], "hello");
    try expectLineContent(split_fixture.content_lines[0].f_link, "world");

    const pull_fixture = try buildWordFrame(allocator, &[_][]const u8{ "hello", "hi" });
    pull_fixture.frame.margin_right = 10;
    try std.testing.expect(try wordFill(allocator, pull_fixture.frame, .LeadParamNone, 1));
    try expectLineContent(pull_fixture.content_lines[0], "hello hi");
}

test "word advance word moves across whitespace and lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const same_line = try buildWordFrame(allocator, &[_][]const u8{"hello world foo"});
    try moveDot(allocator, same_line.frame, same_line.content_lines[0], 1);
    try std.testing.expect(try wordAdvanceWord(allocator, same_line.frame, .LeadParamPInt, 2));
    try std.testing.expectEqual(@as(isize, 13), same_line.frame.dot.?.Col);

    const across_lines = try buildWordFrame(allocator, &[_][]const u8{ "hello", "world" });
    try moveDot(allocator, across_lines.frame, across_lines.content_lines[0], 1);
    try std.testing.expect(try wordAdvanceWord(allocator, across_lines.frame, .LeadParamNone, 1));
    try std.testing.expect(across_lines.frame.dot.?.Line == across_lines.content_lines[1]);
    try std.testing.expectEqual(@as(isize, 1), across_lines.frame.dot.?.Col);

    try moveDot(allocator, same_line.frame, same_line.content_lines[0], 8);
    try std.testing.expect(try wordAdvanceWord(allocator, same_line.frame, .LeadParamNInt, -1));
    try std.testing.expectEqual(@as(isize, 1), same_line.frame.dot.?.Col);
}

test "word delete word removes the next word and restores dot on failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const delete_fixture = try buildWordFrame(allocator, &[_][]const u8{"hello world"});
    try moveDot(allocator, delete_fixture.frame, delete_fixture.content_lines[0], 1);
    try std.testing.expect(try wordDeleteWord(allocator, delete_fixture.frame, delete_fixture.frame, .LeadParamNone, 1));
    try expectLineContent(delete_fixture.content_lines[0], "world");

    const fail_fixture = try buildWordFrame(allocator, &[_][]const u8{"hello"});
    try moveDot(allocator, fail_fixture.frame, fail_fixture.content_lines[0], 3);
    try std.testing.expect(!(try wordDeleteWord(allocator, fail_fixture.frame, fail_fixture.frame, .LeadParamNone, 1)));
    try std.testing.expectEqual(@as(isize, 3), fail_fixture.frame.dot.?.Col);
}
