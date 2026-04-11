const std = @import("std");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const str_object = @import("str_object.zig");
const types = @import("types.zig");

fn markLineDirty(frame: *types.FrameObject, line: *types.LineHdrObject) void {
    const line_number = line_ops.LineToNumber(line);
    if (frame.DirtyLine == 0 or line_number < frame.DirtyLine) {
        frame.DirtyLine = line_number;
    }
}

fn newBlankString(allocator: std.mem.Allocator) !*str_object.StrObject {
    return str_object.NewBlankStrObject(allocator, types.MaxStrLen);
}

pub fn TextReturnCol(cur_line: *types.LineHdrObject, cur_col: isize, splitting: bool) isize {
    var new_col: isize = if (cur_col >= cur_line.Group.?.Frame.MarginLeft) cur_line.Group.?.Frame.MarginLeft else 1;

    if (cur_line.Group.?.Frame.Options.autoIndent and cur_line.FLink != null) {
        var str1 = cur_line.Str.?;
        const used1 = cur_line.Used;
        var str2 = cur_line.Str.?;
        var used2 = cur_line.Used;

        if (cur_line.FLink.?.FLink != null and !splitting) {
            str2 = cur_line.FLink.?.Str.?;
            used2 = cur_line.FLink.?.Used;
        }

        while (true) : (new_col += 1) {
            if (new_col <= used1 and str1.Get(new_col) != ' ') break;
            if (new_col <= used2) {
                if (str2.Get(new_col) != ' ') break;
            } else if (new_col >= used1) {
                break;
            }
        }
    }
    return new_col;
}

pub fn TextRealizeNull(allocator: std.mem.Allocator, old_null: *types.LineHdrObject) !void {
    const range = try line_ops.LinesCreate(allocator, 1);
    try line_ops.linesInject(allocator, range.first, range.last, old_null);
    try mark_ops.MarksShift(allocator, old_null, 1, types.MaxStrLenP, range.first, 1);
    const frame = range.first.Group.?.Frame;
    frame.TextModified = true;
    if (frame.Dot) |dot| {
        try mark_ops.MarkCreate(allocator, dot.Line, dot.Col, &frame.Marks[types.MarkModified]);
    }
}

pub fn TextInsert(
    allocator: std.mem.Allocator,
    update_screen: bool,
    count: isize,
    buf: *const str_object.StrObject,
    buf_len: isize,
    dst: *types.MarkObject,
) !bool {
    _ = update_screen;
    const insert_len = count * buf_len;
    if (insert_len <= 0) {
        return true;
    }

    var dst_line = dst.Line;
    const dst_col = dst.Col;

    var final_len = dst_col - 1 + insert_len;
    var tail_len = dst_line.Used + 1 - dst_col;
    if (tail_len <= 0) {
        tail_len = 0;
    } else {
        final_len += tail_len;
    }
    if (final_len > types.MaxStrLen) {
        return false;
    }
    if (dst_line.FLink == null) {
        try TextRealizeNull(allocator, dst_line);
        dst_line = dst_line.BLink.?;
    }

    if (final_len > dst_line.Len()) {
        try line_ops.LineChangeLength(allocator, dst_line, final_len);
    }
    try mark_ops.MarksShift(allocator, dst_line, dst_col, types.MaxStrLenP - dst_col, dst_line, dst_col + insert_len);
    if (tail_len > 0) {
        var i = dst_line.Used;
        while (i >= dst_col) : (i -= 1) {
            dst_line.Str.?.Set(i + insert_len, dst_line.Str.?.Get(i));
            if (i == dst_col) break;
        }
    }

    var new_col = dst_col;
    var repetitions: isize = 0;
    while (repetitions < count) : (repetitions += 1) {
        dst_line.Str.?.Copy(buf, 1, buf_len, new_col);
        new_col += buf_len;
    }

    if (tail_len == 0) {
        dst_line.Used = dst_line.Str.?.TrimmedLen(' ', @intCast(dst_line.Len()));
    } else {
        dst_line.Used += insert_len;
    }
    markLineDirty(dst_line.Group.?.Frame, dst_line);
    return true;
}

pub fn TextOvertype(
    allocator: std.mem.Allocator,
    update_screen: bool,
    count: isize,
    buf: *const str_object.StrObject,
    buf_len: isize,
    dst: *types.MarkObject,
) !bool {
    _ = update_screen;
    const overtype_len = count * buf_len;
    if (overtype_len <= 0) {
        return true;
    }

    var dst_line = dst.Line;
    const final_len = dst.Col + overtype_len - 1;
    if (final_len > types.MaxStrLen) {
        return false;
    }
    if (dst_line.FLink == null) {
        try TextRealizeNull(allocator, dst.Line);
        dst_line = dst_line.BLink.?;
    }

    if (final_len > dst_line.Len()) {
        try line_ops.LineChangeLength(allocator, dst_line, final_len);
    }

    var new_col = dst.Col;
    var repetitions: isize = 0;
    while (repetitions < count) : (repetitions += 1) {
        dst_line.Str.?.Copy(buf, 1, buf_len, new_col);
        new_col += buf_len;
    }

    if (new_col > dst_line.Used) {
        dst_line.Used = dst_line.Str.?.TrimmedLen(' ', @intCast(dst_line.Len()));
    }
    markLineDirty(dst_line.Group.?.Frame, dst_line);
    dst.Col += overtype_len;
    return true;
}

pub fn TextInsertTpar(
    allocator: std.mem.Allocator,
    tp: *types.TParObject,
    before_mark: *types.MarkObject,
    equals_mark: *?*types.MarkObject,
) !bool {
    if (tp.Con == null) {
        if (!try TextInsert(allocator, true, 1, tp.Str.?, tp.Len, before_mark)) {
            return false;
        }
        try mark_ops.MarkCreate(allocator, before_mark.Line, before_mark.Col - tp.Len, equals_mark);
        return true;
    }

    if (before_mark.Col + tp.Len > types.MaxStrLen) {
        return false;
    }

    var line_count: isize = 0;
    var tmp_tp = tp.Con.?;
    while (tmp_tp.Con != null) {
        line_count += 1;
        tmp_tp = tmp_tp.Con.?;
    }
    if (tmp_tp.Len + (before_mark.Line.Used - before_mark.Col) > types.MaxStrLen) {
        return false;
    }

    var first_line: ?*types.LineHdrObject = null;
    var last_line: ?*types.LineHdrObject = null;
    if (line_count > 0) {
        const range = try line_ops.LinesCreate(allocator, @intCast(line_count));
        first_line = range.first;
        last_line = range.last;
    }

    if (before_mark.Line.FLink == null) {
        try TextRealizeNull(allocator, before_mark.Line);
    }
    if (!try TextSplitLine(allocator, before_mark, 1, equals_mark)) {
        return false;
    }
    if (!try TextInsert(allocator, true, 1, tp.Str.?, tp.Len, equals_mark.*.?)) {
        return false;
    }
    equals_mark.*.?.Col -= tp.Len;

    tmp_tp = tp.Con.?;
    var tmp_line = first_line;
    var lines_written: isize = 0;
    while (lines_written < line_count) : (lines_written += 1) {
        try line_ops.LineChangeLength(allocator, tmp_line.?, tmp_tp.Len);
        tmp_line.?.Str.?.Copy(tmp_tp.Str.?, 1, tmp_tp.Len, 1);
        tmp_line.?.Used = if (tmp_tp.Len == 0) 0 else tmp_line.?.Str.?.TrimmedLen(' ', tmp_tp.Len);
        tmp_tp = tmp_tp.Con.?;
        tmp_line = tmp_line.?.FLink;
    }

    if (line_count > 0) {
        try line_ops.linesInject(allocator, first_line.?, last_line.?, before_mark.Line);
    }
    if (!try TextInsert(allocator, true, 1, tmp_tp.Str.?, tmp_tp.Len, before_mark)) {
        return false;
    }
    return true;
}

fn textIntraRemove(
    allocator: std.mem.Allocator,
    mark_one: *types.MarkObject,
    size: isize,
) !void {
    const line = mark_one.Line;
    const col_one = mark_one.Col;
    const col_two = col_one + size;
    try mark_ops.MarksSqueeze(allocator, line, col_one, line, col_two);
    try mark_ops.MarksShift(allocator, line, col_two, types.MaxStrLenP + 1 - col_two, line, col_one);
    if (size == 0) {
        return;
    }

    const old_used = line.Used;
    if (col_one > old_used) {
        return;
    }
    const dst_len = old_used + 1 - col_one;
    if (col_two <= old_used) {
        var i: isize = 0;
        while (i < old_used + 1 - col_two) : (i += 1) {
            line.Str.?.Set(col_one + i, line.Str.?.Get(col_two + i));
        }
        i = old_used + 1 - col_two;
        while (i < dst_len) : (i += 1) {
            line.Str.?.Set(col_one + i, ' ');
        }
    } else {
        var i: isize = 0;
        while (i < dst_len) : (i += 1) {
            line.Str.?.Set(col_one + i, ' ');
        }
    }
    line.Used = line.Str.?.TrimmedLen(' ', old_used);
    markLineDirty(line.Group.?.Frame, line);
}

fn textInterRemove(
    allocator: std.mem.Allocator,
    mark_one: *types.MarkObject,
    mark_two: *types.MarkObject,
) !bool {
    if (mark_two.Line.FLink == null and mark_one.Col != 1) {
        const line_one = mark_one.Line;
        const col_one = mark_one.Col;
        const extr_one = line_one.FLink.?;
        const extr_two = mark_two.Line;
        try textIntraRemove(allocator, mark_one, types.MaxStrLenP - mark_one.Col);
        try mark_ops.MarksSqueeze(allocator, line_one, col_one, mark_two.Line, mark_two.Col);
        try mark_ops.MarksShift(allocator, mark_two.Line, mark_two.Col, types.MaxStrLenP + 1 - mark_two.Col, line_one, col_one);
        if (extr_one != extr_two) {
            line_ops.linesExtract(extr_one, extr_two.BLink.?);
        }
        return true;
    }

    var mark_start: ?*types.MarkObject = null;
    defer mark_ops.MarkDestroy(allocator, &mark_start);

    var text_len = mark_one.Line.Used;
    if (mark_one.Col <= text_len) {
        text_len = mark_one.Col - 1;
    }

    const strng = try newBlankString(allocator);
    defer strng.destroy();
    if (mark_one.Col > 1) {
        strng.FillCopy(mark_one.Line.Str.?, 1, text_len, 1, mark_one.Col - 1, ' ');
    }

    text_len = mark_one.Col - 1;
    const delta = mark_one.Col - mark_two.Col;
    if (delta < 0) {
        try mark_ops.MarkCreate(allocator, mark_two.Line, mark_one.Col, &mark_start);
        try textIntraRemove(allocator, mark_start.?, mark_two.Col - mark_start.?.Col);
    } else if (delta > 0) {
        const strng_tail = try newBlankString(allocator);
        defer strng_tail.destroy();
        strng_tail.Copy(strng, mark_two.Col, delta, 1);
        if (!try TextInsert(allocator, true, 1, strng_tail, delta, mark_two)) {
            return false;
        }
        text_len -= delta;
    }

    try mark_ops.MarkCreate(allocator, mark_two.Line, 1, &mark_start);
    if (text_len > 0) {
        if (!try TextOvertype(allocator, true, 1, strng, text_len, mark_start.?)) {
            return false;
        }
    }

    const col_one = mark_one.Col;
    const extr_one = mark_one.Line;
    const extr_two = mark_two.Line.BLink.?;
    try mark_ops.MarksSqueeze(allocator, extr_one, col_one, mark_two.Line, mark_two.Col);
    if (col_one > 1) {
        try mark_ops.MarksShift(allocator, extr_one, 1, col_one - 1, mark_two.Line, 1);
    }
    line_ops.linesExtract(extr_one, extr_two);
    return true;
}

pub fn TextRemove(
    allocator: std.mem.Allocator,
    mark_one: *types.MarkObject,
    mark_two: *types.MarkObject,
) !bool {
    if (mark_one.Line == mark_two.Line) {
        try textIntraRemove(allocator, mark_one, mark_two.Col - mark_one.Col);
        return true;
    }
    return textInterRemove(allocator, mark_one, mark_two);
}

fn textIntraMove(
    allocator: std.mem.Allocator,
    copy_text: bool,
    count: isize,
    mark_one: *types.MarkObject,
    mark_two: *types.MarkObject,
    dst: *types.MarkObject,
    new_start: *?*types.MarkObject,
    new_end: *?*types.MarkObject,
) !bool {
    const col_one = mark_one.Col;
    const col_two = mark_two.Col;
    var full_len = col_two - col_one;

    const text_str = try newBlankString(allocator);
    defer text_str.destroy();

    if (full_len != 0) {
        if (full_len * count > types.MaxStrLen) {
            return false;
        }
        var text_len = full_len;
        if (col_one > mark_one.Line.Used) {
            text_len = 0;
        } else if (col_two > mark_one.Line.Used) {
            text_len = mark_one.Line.Used + 1 - col_one;
        }
        text_str.FillCopy(mark_one.Line.Str.?, col_one, text_len, 1, full_len, ' ');
        text_len = full_len;

        var i: isize = 1;
        while (i < count) : (i += 1) {
            text_str.Copy(text_str, 1, text_len, 1 + full_len);
            full_len += text_len;
        }
    }

    if (!copy_text) {
        var dst_col = dst.Col;
        var dst_used = dst.Line.Used;
        if (mark_one.Line == dst.Line) {
            if (dst_col > col_two) {
                dst_col -= col_two - col_one;
            } else if (dst_col > col_one) {
                dst_col = col_one;
            }
            if (dst_used > col_two) {
                dst_used -= col_two - col_one;
            } else {
                dst_used = col_one - 1;
            }
        }

        var tail_len: isize = 0;
        if (dst_col <= dst_used) {
            tail_len = dst_used + 1 - dst_col;
        }
        if (dst_col + full_len + tail_len > types.MaxStrLenP) {
            return false;
        }
        if (full_len != 0) {
            try textIntraRemove(allocator, mark_one, mark_two.Col - mark_one.Col);
        }
    }

    if (full_len != 0 and !try TextInsert(allocator, true, 1, text_str, full_len, dst)) {
        return false;
    }
    const dst_col = dst.Col;
    try mark_ops.MarkCreate(allocator, dst.Line, dst_col - full_len, new_start);
    try mark_ops.MarkCreate(allocator, dst.Line, dst_col, new_end);
    return true;
}

fn createMarks(
    allocator: std.mem.Allocator,
    dst_line: *types.LineHdrObject,
    dst_col: isize,
    new_start: *?*types.MarkObject,
    last_line: *types.LineHdrObject,
    last_col: isize,
    new_end: *?*types.MarkObject,
) !void {
    try mark_ops.MarkCreate(allocator, dst_line, dst_col, new_start);
    try mark_ops.MarkCreate(allocator, last_line, last_col, new_end);
}

fn textInterMove(
    allocator: std.mem.Allocator,
    copy_text: bool,
    count: isize,
    mark_one: *types.MarkObject,
    mark_two: *types.MarkObject,
    dst: *types.MarkObject,
    new_start: *?*types.MarkObject,
    new_end: *?*types.MarkObject,
) !bool {
    const text_str = try newBlankString(allocator);
    defer text_str.destroy();

    const line_one = mark_one.Line;
    const col_one = mark_one.Col;
    const line_two = mark_two.Line;
    const col_two = mark_two.Col;
    const line_one_nr = line_ops.LineToNumber(line_one);
    const line_two_nr = line_ops.LineToNumber(line_two);

    var dst_col = dst.Col;
    var dst_used = dst.Line.Used;
    if (!copy_text and dst.Line.Group.?.Frame == line_one.Group.?.Frame) {
        const line_dst_nr = line_ops.LineToNumber(dst.Line);
        if (line_one_nr <= line_dst_nr and line_dst_nr <= line_two_nr) {
            if (line_two_nr == line_dst_nr and dst_col >= col_two) {
                dst_col = col_one + dst_col - col_two;
            } else if (line_one_nr != line_dst_nr or dst_col >= col_one) {
                dst_col = col_one;
            }

            var temp_len: isize = 0;
            if (col_two <= line_two.Used) {
                temp_len = line_two.Used + 1 - col_two;
            }
            dst_used = col_one - 1 + temp_len;
        }
    }

    if (col_two <= line_two.Used and col_one + line_two.Used - col_two > types.MaxStrLenP) return false;
    if (col_one <= line_one.Used and dst_col + line_one.Used - col_one > types.MaxStrLenP) return false;
    if (dst_col <= dst_used and col_two + dst_used - dst_col > types.MaxStrLen) return false;
    if (count > 1 and col_one <= line_one.Used and col_two + line_one.Used - col_one > types.MaxStrLen) return false;

    var lines_required = count * (line_two_nr - line_one_nr);
    if (!copy_text) {
        lines_required -= line_two_nr - line_one_nr - 1;
    }
    const range = try line_ops.LinesCreate(allocator, @intCast(lines_required));
    var first_line = range.first;
    var last_line = range.last;

    var text_len: isize = 0;
    if (col_one <= line_one.Used) {
        text_len = line_one.Used + 1 - col_one;
        text_str.Copy(line_one.Str.?, col_one, text_len, 1);
    }

    var i = count - 1;
    while (i >= 0) : (i -= 1) {
        var next_dst_line = if (i == count - 1) first_line else blk: {
            var line = first_line;
            var skip: isize = 0;
            while (skip < (count - 1 - i) * (line_two_nr - line_one_nr)) : (skip += 1) {
                line = line.FLink.?;
            }
            break :blk line;
        };
        var next_src_line = line_one.FLink.?;

        if (i == 0 and !copy_text and (line_two_nr - line_one_nr > 1)) {
            const first_nicked = line_one.FLink.?;
            const last_nicked = line_two.BLink.?;
            try mark_ops.MarksSqueeze(allocator, first_nicked, 1, last_nicked.FLink.?, 1);
            line_ops.linesExtract(first_nicked, last_nicked);
            last_nicked.FLink = next_dst_line;
            first_nicked.BLink = next_dst_line.BLink;
            if (first_nicked.BLink) |blink| {
                blink.FLink = first_nicked;
            }
            next_dst_line.BLink = last_nicked;
            if (next_dst_line == first_line) {
                first_line = first_nicked;
            }
            next_src_line = line_two;
        }

        while (next_src_line != line_two) {
            try line_ops.LineChangeLength(allocator, next_dst_line, next_src_line.Used);
            next_dst_line.Str.?.Copy(next_src_line.Str.?, 1, next_src_line.Used, 1);
            next_dst_line.Used = next_src_line.Used;
            next_src_line = next_src_line.FLink.?;
            next_dst_line = next_dst_line.FLink.?;
        }

        if (i != 0) {
            try line_ops.LineChangeLength(allocator, next_dst_line, col_two - 1 + text_len);
            next_dst_line.Str.?.Copy(text_str, 1, text_len, col_two);
        } else {
            try line_ops.LineChangeLength(allocator, next_dst_line, col_two - 1);
        }

        if (col_two > 1) {
            if (col_two <= next_src_line.Used) {
                next_dst_line.Str.?.Copy(next_src_line.Str.?, 1, col_two - 1, 1);
            } else {
                next_dst_line.Str.?.FillCopy(next_src_line.Str.?, 1, next_src_line.Used, 1, col_two - 1, ' ');
            }
        }
        next_dst_line.Used = if (i != 0)
            next_dst_line.Str.?.TrimmedLen(' ', col_two - 1 + text_len)
        else
            col_two - 1;
    }

    if (!copy_text and !try textInterRemove(allocator, mark_one, mark_two)) {
        return false;
    }

    var dst_line = dst.Line;
    dst_col = dst.Col;

    const last_line_length = last_line.Used;
    const tail_len = dst_line.Used + 1 - dst_col;
    if (tail_len > 0) {
        try line_ops.LineChangeLength(allocator, last_line, last_line.Used + tail_len);
        last_line.Str.?.Copy(dst_line.Str.?, dst_col, tail_len, last_line_length + 1);
        last_line.Used = last_line.Str.?.TrimmedLen(' ', last_line_length + tail_len);
    } else if (last_line_length > 0) {
        last_line.Used = last_line.Str.?.TrimmedLen(' ', last_line_length);
    }

    if (dst_line.FLink == null) {
        if (dst_col != 1 or last_line_length != 0) {
            try TextRealizeNull(allocator, dst_line);
            dst_line = dst_line.BLink.?;
        } else {
            if (first_line != last_line) {
                const first_nicked = last_line;
                last_line = last_line.BLink.?;
                last_line.FLink = null;
                first_nicked.BLink = null;
                first_nicked.FLink = first_line;
                first_line.BLink = first_nicked;
                first_line = first_nicked;
            }

            if (text_len > 0) {
                try line_ops.LineChangeLength(allocator, first_line, text_len);
                first_line.Str.?.FillCopy(text_str, 1, text_len, 1, first_line.Len(), ' ');
                first_line.Used = text_len;
            }
            try line_ops.linesInject(allocator, first_line, last_line, dst_line);

            last_line = dst_line;
            dst_line = first_line;
            try createMarks(allocator, dst_line, dst_col, new_start, last_line, col_two, new_end);
            return true;
        }
    }

    try line_ops.linesInject(allocator, first_line, last_line, dst_line.FLink.?);
    try mark_ops.MarksShift(allocator, dst_line, dst_col, types.MaxStrLenP + 1 - dst_col, last_line, col_two);
    if (text_len > 0) {
        try line_ops.LineChangeLength(allocator, dst_line, dst_col + text_len - 1);
        dst_line.Str.?.FillCopy(text_str, 1, text_len, dst_col, dst_line.Len() + 1 - dst_col, ' ');
        dst_line.Used = dst_col + text_len - 1;
        markLineDirty(dst_line.Group.?.Frame, dst_line);
    } else if (dst_col <= dst_line.Used) {
        dst_line.Str.?.Fill(' ', dst_col, dst_line.Used);
        dst_line.Used = dst_line.Str.?.TrimmedLen(' ', dst_col);
        markLineDirty(dst_line.Group.?.Frame, dst_line);
    }

    try createMarks(allocator, dst_line, dst_col, new_start, last_line, col_two, new_end);
    return true;
}

pub fn TextMove(
    allocator: std.mem.Allocator,
    copy_text: bool,
    count: isize,
    mark_one: *types.MarkObject,
    mark_two: *types.MarkObject,
    dst: *types.MarkObject,
    new_start: *?*types.MarkObject,
    new_end: *?*types.MarkObject,
) !bool {
    if (count > 0) {
        const cmd_success = if (mark_one.Line == mark_two.Line)
            try textIntraMove(allocator, copy_text, count, mark_one, mark_two, dst, new_start, new_end)
        else
            try textInterMove(allocator, copy_text, count, mark_one, mark_two, dst, new_start, new_end);

        if (!cmd_success) {
            return false;
        }
        if (!copy_text) {
            mark_two.Line.Group.?.Frame.TextModified = true;
            try mark_ops.MarkCreate(allocator, mark_two.Line, mark_two.Col, &mark_two.Line.Group.?.Frame.Marks[types.MarkModified]);
        }
        new_end.*.?.Line.Group.?.Frame.TextModified = true;
        try mark_ops.MarkCreate(allocator, new_end.*.?.Line, new_end.*.?.Col, &new_end.*.?.Line.Group.?.Frame.Marks[types.MarkModified]);
    }
    return true;
}

pub fn TextSplitLine(
    allocator: std.mem.Allocator,
    before_mark: *types.MarkObject,
    requested_new_col: isize,
    equals_mark: *?*types.MarkObject,
) !bool {
    if (before_mark.Line.FLink == null) {
        return false;
    }

    var new_col = requested_new_col;
    if (new_col == 0) {
        new_col = TextReturnCol(before_mark.Line, before_mark.Col, true);
    }

    var length = before_mark.Line.Used + 1 - before_mark.Col;
    if (length <= 0) {
        length = 0;
    } else if (new_col + length > types.MaxStrLenP) {
        return false;
    }

    const range = try line_ops.LinesCreate(allocator, 1);
    const new_line = range.first;

    var shift = new_col - before_mark.Col;
    var cost: isize = types.MaxInt;
    if (before_mark.Col <= before_mark.Line.Used and before_mark.Line.ScrRowNr != 0) {
        if (shift == 0) {
            cost = before_mark.Col + before_mark.Col;
        } else if (shift > 0) {
            cost = before_mark.Col + before_mark.Col + 3 * shift;
        } else {
            cost = before_mark.Col + before_mark.Col - 3 * shift;
        }
    }

    var equals_col: isize = undefined;
    var equals_line: *types.LineHdrObject = undefined;
    if (2 * length < cost) {
        equals_col = before_mark.Col;
        equals_line = before_mark.Line;
        if (length > 0) {
            try line_ops.LineChangeLength(allocator, new_line, new_col + length - 1);
            new_line.Str.?.FillN(' ', new_col - 1, 1);
            new_line.Str.?.Copy(before_mark.Line.Str.?, before_mark.Col, length, new_col);
            before_mark.Line.Str.?.Fill(' ', before_mark.Col, before_mark.Col + length - 1);
            before_mark.Line.Used = before_mark.Line.Str.?.TrimmedLen(' ', before_mark.Line.Used);
            markLineDirty(before_mark.Line.Group.?.Frame, before_mark.Line);
            new_line.Used = new_col + length - 1;
        }
        try line_ops.linesInject(allocator, new_line, new_line, before_mark.Line.FLink.?);
        try mark_ops.MarksShift(allocator, before_mark.Line, before_mark.Col, types.MaxStrLenP + 1 - before_mark.Col, new_line, new_col);
    } else {
        equals_col = before_mark.Col;
        equals_line = new_line;
        if (before_mark.Col <= before_mark.Line.Used) {
            shift = before_mark.Col - 1;
        } else {
            before_mark.Col = before_mark.Line.Used;
            shift = before_mark.Col - 1;
        }

        if (shift > 0) {
            try line_ops.LineChangeLength(allocator, new_line, shift);
            new_line.Str.?.Copy(before_mark.Line.Str.?, 1, shift, 1);
            new_line.Used = new_line.Str.?.TrimmedLen(' ', shift);
        }

        try line_ops.linesInject(allocator, new_line, new_line, before_mark.Line);
        markLineDirty(new_line.Group.?.Frame, new_line);
        if (before_mark.Col > 1) {
            try mark_ops.MarksShift(allocator, before_mark.Line, 1, before_mark.Col - 1, new_line, 1);
        }

        shift = new_col - before_mark.Col;
        if (shift <= 0) {
            if (shift < 0) {
                before_mark.Col += shift;
                try textIntraRemove(allocator, before_mark, -shift);
            }
            if (new_col > 1) {
                const blank = try newBlankString(allocator);
                defer blank.destroy();
                const save_col = before_mark.Col;
                before_mark.Col = 1;
                if (!try TextOvertype(allocator, true, 1, blank, new_col - 1, before_mark)) {
                    return false;
                }
                before_mark.Col = save_col;
            }
        } else {
            const blank = try newBlankString(allocator);
            defer blank.destroy();
            if (!try TextInsert(allocator, true, 1, blank, shift, before_mark)) {
                return false;
            }
            if (new_col > 1) {
                const save_col = before_mark.Col;
                before_mark.Col = 1;
                if (!try TextOvertype(allocator, true, 1, blank, new_col - 1, before_mark)) {
                    return false;
                }
                before_mark.Col = save_col;
            }
        }
    }

    before_mark.Line.Group.?.Frame.TextModified = true;
    try mark_ops.MarkCreate(allocator, before_mark.Line, before_mark.Col, &before_mark.Line.Group.?.Frame.Marks[types.MarkModified]);
    try mark_ops.MarkCreate(allocator, equals_line, equals_col, equals_mark);
    return true;
}

fn expectLineContent(line: ?*const types.LineHdrObject, expected: []const u8) !void {
    try std.testing.expectEqualStrings(expected, line_ops.getLineContent(line));
}

test "text return column honors margin and auto-indent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try line_ops.setupLinkedLines(allocator, 2);
    fixture.frame.MarginLeft = 5;
    try std.testing.expectEqual(@as(isize, 1), TextReturnCol(fixture.content_lines[0], 3, false));
    try std.testing.expectEqual(@as(isize, 5), TextReturnCol(fixture.content_lines[0], 10, false));

    fixture.frame.Options.autoIndent = true;
    try line_ops.setLineContent(fixture.content_lines[0], "    A");
    try std.testing.expectEqual(@as(isize, 5), TextReturnCol(fixture.content_lines[0], 10, false));
}

test "text insert handles empty middle and null lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var empty_fixture = try line_ops.setupLinkedLines(allocator, 2);
    var insert_mark = types.MarkObject{ .Line = empty_fixture.content_lines[0], .Col = 1 };
    const hello = try str_object.NewStrObjectFrom(allocator, "Hi");
    try std.testing.expect(try TextInsert(allocator, false, 1, hello, 2, &insert_mark));
    try expectLineContent(empty_fixture.content_lines[0], "Hi");

    const middle_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"Hello"});
    var middle_mark = types.MarkObject{ .Line = middle_fixture.content_lines[0], .Col = 4 };
    const xy = try str_object.NewStrObjectFrom(allocator, "XY");
    try std.testing.expect(try TextInsert(allocator, false, 1, xy, 2, &middle_mark));
    try expectLineContent(middle_fixture.content_lines[0], "HelXYlo");

    empty_fixture.frame.Dot = try allocator.create(types.MarkObject);
    empty_fixture.frame.Dot.?.* = .{ .Line = empty_fixture.sentinel_line, .Col = 1 };
    var null_mark = types.MarkObject{ .Line = empty_fixture.sentinel_line, .Col = 1 };
    const z = try str_object.NewStrObjectFrom(allocator, "Z");
    try std.testing.expect(try TextInsert(allocator, false, 1, z, 1, &null_mark));
    try std.testing.expect(empty_fixture.frame.TextModified);
}

test "text overtype advances destination mark" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"Hello"});
    var mark = types.MarkObject{ .Line = fixture.content_lines[0], .Col = 2 };
    const xy = try str_object.NewStrObjectFrom(allocator, "XY");
    try std.testing.expect(try TextOvertype(allocator, false, 1, xy, 2, &mark));
    try expectLineContent(fixture.content_lines[0], "HXYlo");
    try std.testing.expectEqual(@as(isize, 4), mark.Col);
}

test "text remove works within and across lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const intra = try line_ops.createContentFrame(allocator, &[_][]const u8{"Hello World"});
    var mark_one = types.MarkObject{ .Line = intra.content_lines[0], .Col = 7 };
    var mark_two = types.MarkObject{ .Line = intra.content_lines[0], .Col = 12 };
    try std.testing.expect(try TextRemove(allocator, &mark_one, &mark_two));
    try expectLineContent(intra.content_lines[0], "Hello");

    const inter = try line_ops.setupLinkedLines(allocator, 3);
    try line_ops.setLineContent(inter.content_lines[0], "First line");
    try line_ops.setLineContent(inter.content_lines[1], "Second line");
    try line_ops.setLineContent(inter.content_lines[2], "Third line");
    mark_one = .{ .Line = inter.content_lines[0], .Col = 7 };
    mark_two = .{ .Line = inter.content_lines[2], .Col = 7 };
    try std.testing.expect(try TextRemove(allocator, &mark_one, &mark_two));
    try expectLineContent(mark_two.Line, "First line");
}

test "text split line creates equals mark and preserves content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try line_ops.setupLinkedLines(allocator, 2);
    try line_ops.setLineContent(fixture.content_lines[0], "Hello World");
    fixture.frame.Dot = try allocator.create(types.MarkObject);
    fixture.frame.Dot.?.* = .{ .Line = fixture.content_lines[0], .Col = 1 };

    var before_mark = types.MarkObject{ .Line = fixture.content_lines[0], .Col = 7 };
    var equals_mark: ?*types.MarkObject = null;
    try std.testing.expect(try TextSplitLine(allocator, &before_mark, 1, &equals_mark));
    try std.testing.expect(equals_mark != null);
    try std.testing.expect(fixture.frame.TextModified);
    try line_ops.validateFrameShape(fixture.frame);
}

test "text move copies and moves single-line ranges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const copy_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"Hello"});
    var mark_one = types.MarkObject{ .Line = copy_fixture.content_lines[0], .Col = 1 };
    var mark_two = types.MarkObject{ .Line = copy_fixture.content_lines[0], .Col = 6 };
    var dst = types.MarkObject{ .Line = copy_fixture.content_lines[0], .Col = 10 };
    var new_start: ?*types.MarkObject = null;
    var new_end: ?*types.MarkObject = null;
    try std.testing.expect(try TextMove(allocator, true, 1, &mark_one, &mark_two, &dst, &new_start, &new_end));
    try std.testing.expect(new_start != null and new_end != null);

    const move_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"Hello World"});
    mark_one = .{ .Line = move_fixture.content_lines[0], .Col = 1 };
    mark_two = .{ .Line = move_fixture.content_lines[0], .Col = 6 };
    dst = .{ .Line = move_fixture.content_lines[0], .Col = 12 };
    new_start = null;
    new_end = null;
    try std.testing.expect(try TextMove(allocator, false, 1, &mark_one, &mark_two, &dst, &new_start, &new_end));
    try std.testing.expect(move_fixture.frame.TextModified);
}

test "text move copies and moves multi-line ranges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const copy_fixture = try line_ops.setupLinkedLines(allocator, 4);
    try line_ops.setLineContent(copy_fixture.content_lines[0], "First");
    try line_ops.setLineContent(copy_fixture.content_lines[1], "Second");
    var mark_one = types.MarkObject{ .Line = copy_fixture.content_lines[0], .Col = 1 };
    var mark_two = types.MarkObject{ .Line = copy_fixture.content_lines[1], .Col = 7 };
    var dst = types.MarkObject{ .Line = copy_fixture.content_lines[2], .Col = 1 };
    var new_start: ?*types.MarkObject = null;
    var new_end: ?*types.MarkObject = null;
    try std.testing.expect(try TextMove(allocator, true, 1, &mark_one, &mark_two, &dst, &new_start, &new_end));
    try expectLineContent(copy_fixture.content_lines[0], "First");
    try expectLineContent(copy_fixture.content_lines[1], "Second");

    const move_fixture = try line_ops.setupLinkedLines(allocator, 4);
    try line_ops.setLineContent(move_fixture.content_lines[0], "AAA");
    try line_ops.setLineContent(move_fixture.content_lines[1], "BBB");
    mark_one = .{ .Line = move_fixture.content_lines[0], .Col = 2 };
    mark_two = .{ .Line = move_fixture.content_lines[1], .Col = 3 };
    dst = .{ .Line = move_fixture.content_lines[2], .Col = 1 };
    new_start = null;
    new_end = null;
    try std.testing.expect(try TextMove(allocator, false, 1, &mark_one, &mark_two, &dst, &new_start, &new_end));
    try std.testing.expect(move_fixture.frame.TextModified);
    try line_ops.validateFrameShape(move_fixture.frame);
}

test "text insert tpar handles simple and multiline chains" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const simple_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{""});
    var before_mark = types.MarkObject{ .Line = simple_fixture.content_lines[0], .Col = 1 };
    const hello = try str_object.NewStrObjectFrom(allocator, "Hello");
    var simple_tpar = types.TParObject{ .Len = 5, .Str = hello };
    var equals_mark: ?*types.MarkObject = null;
    try std.testing.expect(try TextInsertTpar(allocator, &simple_tpar, &before_mark, &equals_mark));
    try expectLineContent(simple_fixture.content_lines[0], "Hello");

    const multi_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"Hello World"});
    var mark: ?*types.MarkObject = null;
    try mark_ops.MarkCreate(allocator, multi_fixture.content_lines[0], 7, &mark);
    const line1 = try str_object.NewStrObjectFrom(allocator, "Line1");
    const line2 = try str_object.NewStrObjectFrom(allocator, "Line2");
    const line3 = try str_object.NewStrObjectFrom(allocator, "Line3");
    var tpar3 = types.TParObject{ .Len = 5, .Str = line3 };
    var tpar2 = types.TParObject{ .Len = 5, .Str = line2, .Con = &tpar3 };
    var tpar1 = types.TParObject{ .Len = 5, .Str = line1, .Con = &tpar2 };
    equals_mark = null;
    try std.testing.expect(try TextInsertTpar(allocator, &tpar1, mark.?, &equals_mark));
    try std.testing.expect(equals_mark != null);
    try expectLineContent(equals_mark.?.Line, "Hello Line1");
    try expectLineContent(equals_mark.?.Line.FLink, "Line2");
    try expectLineContent(equals_mark.?.Line.FLink.?.FLink, "Line3World");
}
