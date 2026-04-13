const std = @import("std");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const str_object = @import("str_object.zig");
const types = @import("types.zig");

fn markLineDirty(frame: *types.FrameObject, line: *types.LineHdrObject) void {
    const line_number = line_ops.lineToNumber(line);
    if (frame.dirty_line == 0 or line_number < frame.dirty_line) {
        frame.dirty_line = line_number;
    }
}

fn newBlankString(allocator: std.mem.Allocator) !*str_object.StrObject {
    return str_object.newBlankStrObject(allocator, types.max_str_len);
}

pub fn textReturnCol(cur_line: *types.LineHdrObject, cur_col: isize, splitting: bool) isize {
    var new_col: isize = if (cur_col >= cur_line.group.?.frame.margin_left) cur_line.group.?.frame.margin_left else 1;

    if (cur_line.group.?.frame.options.auto_indent and cur_line.f_link != null) {
        var str1 = cur_line.str.?;
        const used1 = cur_line.used;
        var str2 = cur_line.str.?;
        var used2 = cur_line.used;

        if (cur_line.f_link.?.f_link != null and !splitting) {
            str2 = cur_line.f_link.?.str.?;
            used2 = cur_line.f_link.?.used;
        }

        while (true) : (new_col += 1) {
            if (new_col <= used1 and str1.get(new_col) != ' ') break;
            if (new_col <= used2) {
                if (str2.get(new_col) != ' ') break;
            } else if (new_col >= used1) {
                break;
            }
        }
    }
    return new_col;
}

pub fn textRealizeNull(allocator: std.mem.Allocator, old_null: *types.LineHdrObject) !void {
    const range = try line_ops.linesCreate(allocator, 1);
    try line_ops.linesInject(allocator, range.first, range.last, old_null);
    try mark_ops.marksShift(allocator, old_null, 1, types.max_str_len_p1, range.first, 1);
    const frame = range.first.group.?.frame;
    frame.text_modified = true;
    if (frame.dot) |dot| {
        try mark_ops.markCreate(allocator, dot.line, dot.col, &frame.marks[types.mark_modified]);
    }
}

pub fn textInsert(
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

    var dst_line = dst.line;
    const dst_col = dst.col;

    var final_len = dst_col - 1 + insert_len;
    var tail_len = dst_line.used + 1 - dst_col;
    if (tail_len <= 0) {
        tail_len = 0;
    } else {
        final_len += tail_len;
    }
    if (final_len > types.max_str_len) {
        return false;
    }
    if (dst_line.f_link == null) {
        try textRealizeNull(allocator, dst_line);
        dst_line = dst_line.b_link.?;
    }

    if (final_len > dst_line.len()) {
        try line_ops.lineChangeLength(allocator, dst_line, final_len);
    }
    try mark_ops.marksShift(allocator, dst_line, dst_col, types.max_str_len_p1 - dst_col, dst_line, dst_col + insert_len);
    if (tail_len > 0) {
        var i = dst_line.used;
        while (i >= dst_col) : (i -= 1) {
            dst_line.str.?.set(i + insert_len, dst_line.str.?.get(i));
            if (i == dst_col) break;
        }
    }

    var new_col = dst_col;
    var repetitions: isize = 0;
    while (repetitions < count) : (repetitions += 1) {
        dst_line.str.?.copy(buf, 1, buf_len, new_col);
        new_col += buf_len;
    }

    if (tail_len == 0) {
        dst_line.used = dst_line.str.?.trimmedLen(' ', @intCast(dst_line.len()));
    } else {
        dst_line.used += insert_len;
    }
    markLineDirty(dst_line.group.?.frame, dst_line);
    return true;
}

pub fn textOvertype(
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

    var dst_line = dst.line;
    const final_len = dst.col + overtype_len - 1;
    if (final_len > types.max_str_len) {
        return false;
    }
    if (dst_line.f_link == null) {
        try textRealizeNull(allocator, dst.line);
        dst_line = dst_line.b_link.?;
    }

    if (final_len > dst_line.len()) {
        try line_ops.lineChangeLength(allocator, dst_line, final_len);
    }

    var new_col = dst.col;
    var repetitions: isize = 0;
    while (repetitions < count) : (repetitions += 1) {
        dst_line.str.?.copy(buf, 1, buf_len, new_col);
        new_col += buf_len;
    }

    if (new_col > dst_line.used) {
        dst_line.used = dst_line.str.?.trimmedLen(' ', @intCast(dst_line.len()));
    }
    markLineDirty(dst_line.group.?.frame, dst_line);
    dst.col += overtype_len;
    return true;
}

pub fn textInsertTpar(
    allocator: std.mem.Allocator,
    tp: *types.TParObject,
    before_mark: *types.MarkObject,
    equals_mark: *?*types.MarkObject,
) !bool {
    if (tp.con == null) {
        if (!try textInsert(allocator, true, 1, tp.str.?, tp.len, before_mark)) {
            return false;
        }
        try mark_ops.markCreate(allocator, before_mark.line, before_mark.col - tp.len, equals_mark);
        return true;
    }

    if (before_mark.col + tp.len > types.max_str_len) {
        return false;
    }

    var line_count: isize = 0;
    var tmp_tp = tp.con.?;
    while (tmp_tp.con != null) {
        line_count += 1;
        tmp_tp = tmp_tp.con.?;
    }
    if (tmp_tp.len + (before_mark.line.used - before_mark.col) > types.max_str_len) {
        return false;
    }

    var first_line: ?*types.LineHdrObject = null;
    var last_line: ?*types.LineHdrObject = null;
    if (line_count > 0) {
        const range = try line_ops.linesCreate(allocator, @intCast(line_count));
        first_line = range.first;
        last_line = range.last;
    }

    if (before_mark.line.f_link == null) {
        try textRealizeNull(allocator, before_mark.line);
    }
    if (!try textSplitLine(allocator, before_mark, 1, equals_mark)) {
        return false;
    }
    if (!try textInsert(allocator, true, 1, tp.str.?, tp.len, equals_mark.*.?)) {
        return false;
    }
    equals_mark.*.?.col -= tp.len;

    tmp_tp = tp.con.?;
    var tmp_line = first_line;
    var lines_written: isize = 0;
    while (lines_written < line_count) : (lines_written += 1) {
        try line_ops.lineChangeLength(allocator, tmp_line.?, tmp_tp.len);
        tmp_line.?.str.?.copy(tmp_tp.str.?, 1, tmp_tp.len, 1);
        tmp_line.?.used = if (tmp_tp.len == 0) 0 else tmp_line.?.str.?.trimmedLen(' ', tmp_tp.len);
        tmp_tp = tmp_tp.con.?;
        tmp_line = tmp_line.?.f_link;
    }

    if (line_count > 0) {
        try line_ops.linesInject(allocator, first_line.?, last_line.?, before_mark.line);
    }
    if (!try textInsert(allocator, true, 1, tmp_tp.str.?, tmp_tp.len, before_mark)) {
        return false;
    }
    return true;
}

fn textIntraRemove(
    allocator: std.mem.Allocator,
    mark_one: *types.MarkObject,
    size: isize,
) !void {
    const line = mark_one.line;
    const col_one = mark_one.col;
    const col_two = col_one + size;
    try mark_ops.marksSqueeze(allocator, line, col_one, line, col_two);
    try mark_ops.marksShift(allocator, line, col_two, types.max_str_len_p1 + 1 - col_two, line, col_one);
    if (size == 0) {
        return;
    }

    const old_used = line.used;
    if (col_one > old_used) {
        return;
    }
    const dst_len = old_used + 1 - col_one;
    if (col_two <= old_used) {
        var i: isize = 0;
        while (i < old_used + 1 - col_two) : (i += 1) {
            line.str.?.set(col_one + i, line.str.?.get(col_two + i));
        }
        i = old_used + 1 - col_two;
        while (i < dst_len) : (i += 1) {
            line.str.?.set(col_one + i, ' ');
        }
    } else {
        var i: isize = 0;
        while (i < dst_len) : (i += 1) {
            line.str.?.set(col_one + i, ' ');
        }
    }
    line.used = line.str.?.trimmedLen(' ', old_used);
    markLineDirty(line.group.?.frame, line);
}

fn textInterRemove(
    allocator: std.mem.Allocator,
    mark_one: *types.MarkObject,
    mark_two: *types.MarkObject,
) !bool {
    if (mark_two.line.f_link == null and mark_one.col != 1) {
        const line_one = mark_one.line;
        const col_one = mark_one.col;
        const extr_one = line_one.f_link.?;
        const extr_two = mark_two.line;
        try textIntraRemove(allocator, mark_one, types.max_str_len_p1 - mark_one.col);
        try mark_ops.marksSqueeze(allocator, line_one, col_one, mark_two.line, mark_two.col);
        try mark_ops.marksShift(allocator, mark_two.line, mark_two.col, types.max_str_len_p1 + 1 - mark_two.col, line_one, col_one);
        if (extr_one != extr_two) {
            line_ops.linesExtract(extr_one, extr_two.b_link.?);
        }
        return true;
    }

    var mark_start: ?*types.MarkObject = null;
    defer mark_ops.markDestroy(allocator, &mark_start);

    var text_len = mark_one.line.used;
    if (mark_one.col <= text_len) {
        text_len = mark_one.col - 1;
    }

    const strng = try newBlankString(allocator);
    defer strng.destroy();
    if (mark_one.col > 1) {
        strng.fillCopy(mark_one.line.str.?, 1, text_len, 1, mark_one.col - 1, ' ');
    }

    text_len = mark_one.col - 1;
    const delta = mark_one.col - mark_two.col;
    if (delta < 0) {
        try mark_ops.markCreate(allocator, mark_two.line, mark_one.col, &mark_start);
        try textIntraRemove(allocator, mark_start.?, mark_two.col - mark_start.?.col);
    } else if (delta > 0) {
        const strng_tail = try newBlankString(allocator);
        defer strng_tail.destroy();
        strng_tail.copy(strng, mark_two.col, delta, 1);
        if (!try textInsert(allocator, true, 1, strng_tail, delta, mark_two)) {
            return false;
        }
        text_len -= delta;
    }

    try mark_ops.markCreate(allocator, mark_two.line, 1, &mark_start);
    if (text_len > 0) {
        if (!try textOvertype(allocator, true, 1, strng, text_len, mark_start.?)) {
            return false;
        }
    }

    const col_one = mark_one.col;
    const extr_one = mark_one.line;
    const extr_two = mark_two.line.b_link.?;
    try mark_ops.marksSqueeze(allocator, extr_one, col_one, mark_two.line, mark_two.col);
    if (col_one > 1) {
        try mark_ops.marksShift(allocator, extr_one, 1, col_one - 1, mark_two.line, 1);
    }
    line_ops.linesExtract(extr_one, extr_two);
    return true;
}

pub fn textRemove(
    allocator: std.mem.Allocator,
    mark_one: *types.MarkObject,
    mark_two: *types.MarkObject,
) !bool {
    if (mark_one.line == mark_two.line) {
        try textIntraRemove(allocator, mark_one, mark_two.col - mark_one.col);
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
    const col_one = mark_one.col;
    const col_two = mark_two.col;
    var full_len = col_two - col_one;

    const text_str = try newBlankString(allocator);
    defer text_str.destroy();

    if (full_len != 0) {
        if (full_len * count > types.max_str_len) {
            return false;
        }
        var text_len = full_len;
        if (col_one > mark_one.line.used) {
            text_len = 0;
        } else if (col_two > mark_one.line.used) {
            text_len = mark_one.line.used + 1 - col_one;
        }
        text_str.fillCopy(mark_one.line.str.?, col_one, text_len, 1, full_len, ' ');
        text_len = full_len;

        var i: isize = 1;
        while (i < count) : (i += 1) {
            text_str.copy(text_str, 1, text_len, 1 + full_len);
            full_len += text_len;
        }
    }

    if (!copy_text) {
        var dst_col = dst.col;
        var dst_used = dst.line.used;
        if (mark_one.line == dst.line) {
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
        if (dst_col + full_len + tail_len > types.max_str_len_p1) {
            return false;
        }
        if (full_len != 0) {
            try textIntraRemove(allocator, mark_one, mark_two.col - mark_one.col);
        }
    }

    if (full_len != 0 and !try textInsert(allocator, true, 1, text_str, full_len, dst)) {
        return false;
    }
    const dst_col = dst.col;
    try mark_ops.markCreate(allocator, dst.line, dst_col - full_len, new_start);
    try mark_ops.markCreate(allocator, dst.line, dst_col, new_end);
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
    try mark_ops.markCreate(allocator, dst_line, dst_col, new_start);
    try mark_ops.markCreate(allocator, last_line, last_col, new_end);
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

    const line_one = mark_one.line;
    const col_one = mark_one.col;
    const line_two = mark_two.line;
    const col_two = mark_two.col;
    const line_one_nr = line_ops.lineToNumber(line_one);
    const line_two_nr = line_ops.lineToNumber(line_two);

    var dst_col = dst.col;
    var dst_used = dst.line.used;
    if (!copy_text and dst.line.group.?.frame == line_one.group.?.frame) {
        const line_dst_nr = line_ops.lineToNumber(dst.line);
        if (line_one_nr <= line_dst_nr and line_dst_nr <= line_two_nr) {
            if (line_two_nr == line_dst_nr and dst_col >= col_two) {
                dst_col = col_one + dst_col - col_two;
            } else if (line_one_nr != line_dst_nr or dst_col >= col_one) {
                dst_col = col_one;
            }

            var temp_len: isize = 0;
            if (col_two <= line_two.used) {
                temp_len = line_two.used + 1 - col_two;
            }
            dst_used = col_one - 1 + temp_len;
        }
    }

    if (col_two <= line_two.used and col_one + line_two.used - col_two > types.max_str_len_p1) return false;
    if (col_one <= line_one.used and dst_col + line_one.used - col_one > types.max_str_len_p1) return false;
    if (dst_col <= dst_used and col_two + dst_used - dst_col > types.max_str_len) return false;
    if (count > 1 and col_one <= line_one.used and col_two + line_one.used - col_one > types.max_str_len) return false;

    var lines_required = count * (line_two_nr - line_one_nr);
    if (!copy_text) {
        lines_required -= line_two_nr - line_one_nr - 1;
    }
    const range = try line_ops.linesCreate(allocator, @intCast(lines_required));
    var first_line = range.first;
    var last_line = range.last;

    var text_len: isize = 0;
    if (col_one <= line_one.used) {
        text_len = line_one.used + 1 - col_one;
        text_str.copy(line_one.str.?, col_one, text_len, 1);
    }

    var i = count - 1;
    while (i >= 0) : (i -= 1) {
        var next_dst_line = if (i == count - 1) first_line else blk: {
            var line = first_line;
            var skip: isize = 0;
            while (skip < (count - 1 - i) * (line_two_nr - line_one_nr)) : (skip += 1) {
                line = line.f_link.?;
            }
            break :blk line;
        };
        var next_src_line = line_one.f_link.?;

        if (i == 0 and !copy_text and (line_two_nr - line_one_nr > 1)) {
            const first_nicked = line_one.f_link.?;
            const last_nicked = line_two.b_link.?;
            try mark_ops.marksSqueeze(allocator, first_nicked, 1, last_nicked.f_link.?, 1);
            line_ops.linesExtract(first_nicked, last_nicked);
            last_nicked.f_link = next_dst_line;
            first_nicked.b_link = next_dst_line.b_link;
            if (first_nicked.b_link) |blink| {
                blink.f_link = first_nicked;
            }
            next_dst_line.b_link = last_nicked;
            if (next_dst_line == first_line) {
                first_line = first_nicked;
            }
            next_src_line = line_two;
        }

        while (next_src_line != line_two) {
            try line_ops.lineChangeLength(allocator, next_dst_line, next_src_line.used);
            next_dst_line.str.?.copy(next_src_line.str.?, 1, next_src_line.used, 1);
            next_dst_line.used = next_src_line.used;
            next_src_line = next_src_line.f_link.?;
            next_dst_line = next_dst_line.f_link.?;
        }

        if (i != 0) {
            try line_ops.lineChangeLength(allocator, next_dst_line, col_two - 1 + text_len);
            next_dst_line.str.?.copy(text_str, 1, text_len, col_two);
        } else {
            try line_ops.lineChangeLength(allocator, next_dst_line, col_two - 1);
        }

        if (col_two > 1) {
            if (col_two <= next_src_line.used) {
                next_dst_line.str.?.copy(next_src_line.str.?, 1, col_two - 1, 1);
            } else {
                next_dst_line.str.?.fillCopy(next_src_line.str.?, 1, next_src_line.used, 1, col_two - 1, ' ');
            }
        }
        next_dst_line.used = if (i != 0)
            next_dst_line.str.?.trimmedLen(' ', col_two - 1 + text_len)
        else
            col_two - 1;
    }

    if (!copy_text and !try textInterRemove(allocator, mark_one, mark_two)) {
        return false;
    }

    var dst_line = dst.line;
    dst_col = dst.col;

    const last_line_length = last_line.used;
    const tail_len = dst_line.used + 1 - dst_col;
    if (tail_len > 0) {
        try line_ops.lineChangeLength(allocator, last_line, last_line.used + tail_len);
        last_line.str.?.copy(dst_line.str.?, dst_col, tail_len, last_line_length + 1);
        last_line.used = last_line.str.?.trimmedLen(' ', last_line_length + tail_len);
    } else if (last_line_length > 0) {
        last_line.used = last_line.str.?.trimmedLen(' ', last_line_length);
    }

    if (dst_line.f_link == null) {
        if (dst_col != 1 or last_line_length != 0) {
            try textRealizeNull(allocator, dst_line);
            dst_line = dst_line.b_link.?;
        } else {
            if (first_line != last_line) {
                const first_nicked = last_line;
                last_line = last_line.b_link.?;
                last_line.f_link = null;
                first_nicked.b_link = null;
                first_nicked.f_link = first_line;
                first_line.b_link = first_nicked;
                first_line = first_nicked;
            }

            if (text_len > 0) {
                try line_ops.lineChangeLength(allocator, first_line, text_len);
                first_line.str.?.fillCopy(text_str, 1, text_len, 1, first_line.len(), ' ');
                first_line.used = text_len;
            }
            try line_ops.linesInject(allocator, first_line, last_line, dst_line);

            last_line = dst_line;
            dst_line = first_line;
            try createMarks(allocator, dst_line, dst_col, new_start, last_line, col_two, new_end);
            return true;
        }
    }

    try line_ops.linesInject(allocator, first_line, last_line, dst_line.f_link.?);
    try mark_ops.marksShift(allocator, dst_line, dst_col, types.max_str_len_p1 + 1 - dst_col, last_line, col_two);
    if (text_len > 0) {
        try line_ops.lineChangeLength(allocator, dst_line, dst_col + text_len - 1);
        dst_line.str.?.fillCopy(text_str, 1, text_len, dst_col, dst_line.len() + 1 - dst_col, ' ');
        dst_line.used = dst_col + text_len - 1;
        markLineDirty(dst_line.group.?.frame, dst_line);
    } else if (dst_col <= dst_line.used) {
        dst_line.str.?.fill(' ', dst_col, dst_line.used);
        dst_line.used = dst_line.str.?.trimmedLen(' ', dst_col);
        markLineDirty(dst_line.group.?.frame, dst_line);
    }

    try createMarks(allocator, dst_line, dst_col, new_start, last_line, col_two, new_end);
    return true;
}

pub fn textMove(
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
        const cmd_success = if (mark_one.line == mark_two.line)
            try textIntraMove(allocator, copy_text, count, mark_one, mark_two, dst, new_start, new_end)
        else
            try textInterMove(allocator, copy_text, count, mark_one, mark_two, dst, new_start, new_end);

        if (!cmd_success) {
            return false;
        }
        if (!copy_text) {
            mark_two.line.group.?.frame.text_modified = true;
            try mark_ops.markCreate(allocator, mark_two.line, mark_two.col, &mark_two.line.group.?.frame.marks[types.mark_modified]);
        }
        new_end.*.?.line.group.?.frame.text_modified = true;
        try mark_ops.markCreate(allocator, new_end.*.?.line, new_end.*.?.col, &new_end.*.?.line.group.?.frame.marks[types.mark_modified]);
    }
    return true;
}

pub fn textSplitLine(
    allocator: std.mem.Allocator,
    before_mark: *types.MarkObject,
    requested_new_col: isize,
    equals_mark: *?*types.MarkObject,
) !bool {
    if (before_mark.line.f_link == null) {
        return false;
    }

    var new_col = requested_new_col;
    if (new_col == 0) {
        new_col = textReturnCol(before_mark.line, before_mark.col, true);
    }

    var length = before_mark.line.used + 1 - before_mark.col;
    if (length <= 0) {
        length = 0;
    } else if (new_col + length > types.max_str_len_p1) {
        return false;
    }

    const range = try line_ops.linesCreate(allocator, 1);
    const new_line = range.first;

    var shift = new_col - before_mark.col;
    var cost: isize = types.max_int;
    if (before_mark.col <= before_mark.line.used and before_mark.line.scr_row_num != 0) {
        if (shift == 0) {
            cost = before_mark.col + before_mark.col;
        } else if (shift > 0) {
            cost = before_mark.col + before_mark.col + 3 * shift;
        } else {
            cost = before_mark.col + before_mark.col - 3 * shift;
        }
    }

    var equals_col: isize = undefined;
    var equals_line: *types.LineHdrObject = undefined;
    if (2 * length < cost) {
        equals_col = before_mark.col;
        equals_line = before_mark.line;
        if (length > 0) {
            try line_ops.lineChangeLength(allocator, new_line, new_col + length - 1);
            new_line.str.?.fillN(' ', new_col - 1, 1);
            new_line.str.?.copy(before_mark.line.str.?, before_mark.col, length, new_col);
            before_mark.line.str.?.fill(' ', before_mark.col, before_mark.col + length - 1);
            before_mark.line.used = before_mark.line.str.?.trimmedLen(' ', before_mark.line.used);
            markLineDirty(before_mark.line.group.?.frame, before_mark.line);
            new_line.used = new_col + length - 1;
        }
        try line_ops.linesInject(allocator, new_line, new_line, before_mark.line.f_link.?);
        try mark_ops.marksShift(allocator, before_mark.line, before_mark.col, types.max_str_len_p1 + 1 - before_mark.col, new_line, new_col);
    } else {
        equals_col = before_mark.col;
        equals_line = new_line;
        if (before_mark.col <= before_mark.line.used) {
            shift = before_mark.col - 1;
        } else {
            before_mark.col = before_mark.line.used;
            shift = before_mark.col - 1;
        }

        if (shift > 0) {
            try line_ops.lineChangeLength(allocator, new_line, shift);
            new_line.str.?.copy(before_mark.line.str.?, 1, shift, 1);
            new_line.used = new_line.str.?.trimmedLen(' ', shift);
        }

        try line_ops.linesInject(allocator, new_line, new_line, before_mark.line);
        markLineDirty(new_line.group.?.frame, new_line);
        if (before_mark.col > 1) {
            try mark_ops.marksShift(allocator, before_mark.line, 1, before_mark.col - 1, new_line, 1);
        }

        shift = new_col - before_mark.col;
        if (shift <= 0) {
            if (shift < 0) {
                before_mark.col += shift;
                try textIntraRemove(allocator, before_mark, -shift);
            }
            if (new_col > 1) {
                const blank = try newBlankString(allocator);
                defer blank.destroy();
                const save_col = before_mark.col;
                before_mark.col = 1;
                if (!try textOvertype(allocator, true, 1, blank, new_col - 1, before_mark)) {
                    return false;
                }
                before_mark.col = save_col;
            }
        } else {
            const blank = try newBlankString(allocator);
            defer blank.destroy();
            if (!try textInsert(allocator, true, 1, blank, shift, before_mark)) {
                return false;
            }
            if (new_col > 1) {
                const save_col = before_mark.col;
                before_mark.col = 1;
                if (!try textOvertype(allocator, true, 1, blank, new_col - 1, before_mark)) {
                    return false;
                }
                before_mark.col = save_col;
            }
        }
    }

    before_mark.line.group.?.frame.text_modified = true;
    try mark_ops.markCreate(allocator, before_mark.line, before_mark.col, &before_mark.line.group.?.frame.marks[types.mark_modified]);
    try mark_ops.markCreate(allocator, equals_line, equals_col, equals_mark);
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
    fixture.frame.margin_left = 5;
    try std.testing.expectEqual(@as(isize, 1), textReturnCol(fixture.content_lines[0], 3, false));
    try std.testing.expectEqual(@as(isize, 5), textReturnCol(fixture.content_lines[0], 10, false));

    fixture.frame.options.auto_indent = true;
    try line_ops.setLineContent(fixture.content_lines[0], "    A");
    try std.testing.expectEqual(@as(isize, 5), textReturnCol(fixture.content_lines[0], 10, false));
}

test "text insert handles empty middle and null lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var empty_fixture = try line_ops.setupLinkedLines(allocator, 2);
    var insert_mark = types.MarkObject{ .line = empty_fixture.content_lines[0], .col = 1 };
    const hello = try str_object.newStrObjectFrom(allocator, "Hi");
    try std.testing.expect(try textInsert(allocator, false, 1, hello, 2, &insert_mark));
    try expectLineContent(empty_fixture.content_lines[0], "Hi");

    const middle_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"Hello"});
    var middle_mark = types.MarkObject{ .line = middle_fixture.content_lines[0], .col = 4 };
    const xy = try str_object.newStrObjectFrom(allocator, "XY");
    try std.testing.expect(try textInsert(allocator, false, 1, xy, 2, &middle_mark));
    try expectLineContent(middle_fixture.content_lines[0], "HelXYlo");

    empty_fixture.frame.dot = try allocator.create(types.MarkObject);
    empty_fixture.frame.dot.?.* = .{ .line = empty_fixture.sentinel_line, .col = 1 };
    var null_mark = types.MarkObject{ .line = empty_fixture.sentinel_line, .col = 1 };
    const z = try str_object.newStrObjectFrom(allocator, "Z");
    try std.testing.expect(try textInsert(allocator, false, 1, z, 1, &null_mark));
    try std.testing.expect(empty_fixture.frame.text_modified);
}

test "text overtype advances destination mark" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"Hello"});
    var mark = types.MarkObject{ .line = fixture.content_lines[0], .col = 2 };
    const xy = try str_object.newStrObjectFrom(allocator, "XY");
    try std.testing.expect(try textOvertype(allocator, false, 1, xy, 2, &mark));
    try expectLineContent(fixture.content_lines[0], "HXYlo");
    try std.testing.expectEqual(@as(isize, 4), mark.col);
}

test "text remove works within and across lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const intra = try line_ops.createContentFrame(allocator, &[_][]const u8{"Hello World"});
    var mark_one = types.MarkObject{ .line = intra.content_lines[0], .col = 7 };
    var mark_two = types.MarkObject{ .line = intra.content_lines[0], .col = 12 };
    try std.testing.expect(try textRemove(allocator, &mark_one, &mark_two));
    try expectLineContent(intra.content_lines[0], "Hello");

    const inter = try line_ops.setupLinkedLines(allocator, 3);
    try line_ops.setLineContent(inter.content_lines[0], "First line");
    try line_ops.setLineContent(inter.content_lines[1], "Second line");
    try line_ops.setLineContent(inter.content_lines[2], "Third line");
    mark_one = .{ .line = inter.content_lines[0], .col = 7 };
    mark_two = .{ .line = inter.content_lines[2], .col = 7 };
    try std.testing.expect(try textRemove(allocator, &mark_one, &mark_two));
    try expectLineContent(mark_two.line, "First line");
}

test "text split line creates equals mark and preserves content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fixture = try line_ops.setupLinkedLines(allocator, 2);
    try line_ops.setLineContent(fixture.content_lines[0], "Hello World");
    fixture.frame.dot = try allocator.create(types.MarkObject);
    fixture.frame.dot.?.* = .{ .line = fixture.content_lines[0], .col = 1 };

    var before_mark = types.MarkObject{ .line = fixture.content_lines[0], .col = 7 };
    var equals_mark: ?*types.MarkObject = null;
    try std.testing.expect(try textSplitLine(allocator, &before_mark, 1, &equals_mark));
    try std.testing.expect(equals_mark != null);
    try std.testing.expect(fixture.frame.text_modified);
    try line_ops.validateFrameShape(fixture.frame);
}

test "text move copies and moves single-line ranges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const copy_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"Hello"});
    var mark_one = types.MarkObject{ .line = copy_fixture.content_lines[0], .col = 1 };
    var mark_two = types.MarkObject{ .line = copy_fixture.content_lines[0], .col = 6 };
    var dst = types.MarkObject{ .line = copy_fixture.content_lines[0], .col = 10 };
    var new_start: ?*types.MarkObject = null;
    var new_end: ?*types.MarkObject = null;
    try std.testing.expect(try textMove(allocator, true, 1, &mark_one, &mark_two, &dst, &new_start, &new_end));
    try std.testing.expect(new_start != null and new_end != null);

    const move_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"Hello World"});
    mark_one = .{ .line = move_fixture.content_lines[0], .col = 1 };
    mark_two = .{ .line = move_fixture.content_lines[0], .col = 6 };
    dst = .{ .line = move_fixture.content_lines[0], .col = 12 };
    new_start = null;
    new_end = null;
    try std.testing.expect(try textMove(allocator, false, 1, &mark_one, &mark_two, &dst, &new_start, &new_end));
    try std.testing.expect(move_fixture.frame.text_modified);
}

test "text move copies and moves multi-line ranges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const copy_fixture = try line_ops.setupLinkedLines(allocator, 4);
    try line_ops.setLineContent(copy_fixture.content_lines[0], "First");
    try line_ops.setLineContent(copy_fixture.content_lines[1], "Second");
    var mark_one = types.MarkObject{ .line = copy_fixture.content_lines[0], .col = 1 };
    var mark_two = types.MarkObject{ .line = copy_fixture.content_lines[1], .col = 7 };
    var dst = types.MarkObject{ .line = copy_fixture.content_lines[2], .col = 1 };
    var new_start: ?*types.MarkObject = null;
    var new_end: ?*types.MarkObject = null;
    try std.testing.expect(try textMove(allocator, true, 1, &mark_one, &mark_two, &dst, &new_start, &new_end));
    try expectLineContent(copy_fixture.content_lines[0], "First");
    try expectLineContent(copy_fixture.content_lines[1], "Second");

    const move_fixture = try line_ops.setupLinkedLines(allocator, 4);
    try line_ops.setLineContent(move_fixture.content_lines[0], "AAA");
    try line_ops.setLineContent(move_fixture.content_lines[1], "BBB");
    mark_one = .{ .line = move_fixture.content_lines[0], .col = 2 };
    mark_two = .{ .line = move_fixture.content_lines[1], .col = 3 };
    dst = .{ .line = move_fixture.content_lines[2], .col = 1 };
    new_start = null;
    new_end = null;
    try std.testing.expect(try textMove(allocator, false, 1, &mark_one, &mark_two, &dst, &new_start, &new_end));
    try std.testing.expect(move_fixture.frame.text_modified);
    try line_ops.validateFrameShape(move_fixture.frame);
}

test "text insert tpar handles simple and multiline chains" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const simple_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{""});
    var before_mark = types.MarkObject{ .line = simple_fixture.content_lines[0], .col = 1 };
    const hello = try str_object.newStrObjectFrom(allocator, "Hello");
    var simple_tpar = types.TParObject{ .len = 5, .str = hello };
    var equals_mark: ?*types.MarkObject = null;
    try std.testing.expect(try textInsertTpar(allocator, &simple_tpar, &before_mark, &equals_mark));
    try expectLineContent(simple_fixture.content_lines[0], "Hello");

    const multi_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"Hello World"});
    var mark: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, multi_fixture.content_lines[0], 7, &mark);
    const line1 = try str_object.newStrObjectFrom(allocator, "Line1");
    const line2 = try str_object.newStrObjectFrom(allocator, "Line2");
    const line3 = try str_object.newStrObjectFrom(allocator, "Line3");
    var tpar3 = types.TParObject{ .len = 5, .str = line3 };
    var tpar2 = types.TParObject{ .len = 5, .str = line2, .con = &tpar3 };
    var tpar1 = types.TParObject{ .len = 5, .str = line1, .con = &tpar2 };
    equals_mark = null;
    try std.testing.expect(try textInsertTpar(allocator, &tpar1, mark.?, &equals_mark));
    try std.testing.expect(equals_mark != null);
    try expectLineContent(equals_mark.?.line, "Hello Line1");
    try expectLineContent(equals_mark.?.line.f_link, "Line2");
    try expectLineContent(equals_mark.?.line.f_link.?.f_link, "Line3World");
}
