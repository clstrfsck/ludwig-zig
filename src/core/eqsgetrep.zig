const std = @import("std");
const chars = @import("chars.zig");
const dfa = @import("dfa.zig");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const patparse = @import("patparse.zig");
const recognize = @import("recognize.zig");
const str_object = @import("str_object.zig");
const text = @import("text.zig");
const types = @import("types.zig");

fn absCount(value: isize) isize {
    return if (value < 0) -value else value;
}

fn nextSearchLine(line: ?*types.LineHdrObject, backwards: bool) ?*types.LineHdrObject {
    const candidate = if (backwards) line.?.b_link else line.?.f_link;
    if (candidate == null or candidate.?.str == null) {
        return null;
    }
    return candidate;
}

fn prepareLiteralTarget(
    tpar: *types.TParObject,
) !struct {
    exactcase: bool,
    target: *str_object.StrObject,
} {
    const target = try tpar.str.?.clone();
    const exactcase = tpar.Dlm == types.tpd_exact;
    if (!exactcase) {
        target.applyN(chars.chToUpper, tpar.Len, 1);
    }
    return .{
        .exactcase = exactcase,
        .target = target,
    };
}

pub fn eqsgetrepSamePatternDef(pattern1: *const types.PatternDefType, pattern2: *const types.PatternDefType) bool {
    if (pattern1.Length != 0 and pattern2.Length != 0 and pattern1.Length == pattern2.Length) {
        return pattern1.Strng.?.equalAt(pattern2.Strng.?, pattern1.Length, 1, 1);
    }
    return false;
}

pub fn eqsgetrepPatternBuild(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    tpar: *types.TParObject,
    pattern_ptr: *?*types.DFATableObject,
) !bool {
    var pattern_definition: types.PatternDefType = .{};
    var nfa_table: types.NFATableType = [_]types.NFATransitionType{.{}} ** (types.max_nfa_state_range + 1);
    var first_pattern_start: isize = 0;
    var pattern_final_state: isize = 0;
    var left_context_end: isize = 0;
    var middle_context_end: isize = 0;
    var states_used: isize = 0;

    if (!patparse.patternParser(
        frame,
        tpar,
        &nfa_table,
        &first_pattern_start,
        &pattern_final_state,
        &left_context_end,
        &middle_context_end,
        &pattern_definition,
        &states_used,
    )) {
        return false;
    }

    const already_built = if (pattern_ptr.*) |existing|
        eqsgetrepSamePatternDef(&pattern_definition, &existing.Definition)
    else
        false;

    if (!already_built) {
        if (!try dfa.patternDFATableInitialize(allocator, pattern_ptr, pattern_definition)) {
            return false;
        }
        var dfa_start: isize = 0;
        var dfa_end: isize = 0;
        if (!try dfa.patternDFAConvert(
            &nfa_table,
            pattern_ptr.*.?,
            first_pattern_start,
            &pattern_final_state,
            left_context_end,
            middle_context_end,
            &dfa_start,
            &dfa_end,
        )) {
            return false;
        }
    }
    return true;
}

pub fn eqsGetRepEqs(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    tpar: *types.TParObject,
) !bool {
    var success = false;

    if (tpar.Dlm == types.tpd_smart) {
        if (!try eqsgetrepPatternBuild(allocator, frame, tpar, &frame.eqs_pattern_ptr)) {
            return false;
        }
        var mark_flag = false;
        var start_col: isize = 0;
        var end_pos: isize = 0;
        const found = try recognize.patternRecognize(
            allocator,
            frame,
            frame.eqs_pattern_ptr.?,
            frame.dot.?.Line,
            frame.dot.?.Col,
            &mark_flag,
            &start_col,
            &end_pos,
        );

        success = switch (rept) {
            .LeadParamNone, .LeadParamPlus => frame.dot.?.Col == start_col and found,
            .LeadParamMinus => !((frame.dot.?.Col == start_col) and found),
            .LeadParamPIndef => end_pos <= frame.dot.?.Line.used and found,
            .LeadParamNIndef => end_pos >= frame.dot.?.Line.used and found,
            else => false,
        };
        if (success and rept != .LeadParamMinus) {
            try mark_ops.markCreate(allocator, frame.dot.?.Line, end_pos, &frame.marks[types.mark_equals]);
        }
        return success;
    }

    const prepared = try prepareLiteralTarget(tpar);
    defer prepared.target.destroy();

    var start_col = frame.dot.?.Col;
    const length = blk: {
        if (start_col > frame.dot.?.Line.used) {
            start_col = 1;
            break :blk @as(isize, 0);
        }
        break :blk @min(frame.dot.?.Line.used + 1 - frame.dot.?.Col, tpar.Len);
    };

    var nch_ident: isize = 0;
    const result = chars.chCompareStr(
        prepared.target,
        1,
        tpar.Len,
        frame.dot.?.Line.str.?,
        start_col,
        length,
        prepared.exactcase,
        &nch_ident,
    );
    success = switch (rept) {
        .LeadParamNone, .LeadParamPlus => result == 0,
        .LeadParamMinus => result != 0,
        .LeadParamPIndef => result <= 0,
        .LeadParamNIndef => result >= 0,
        else => false,
    };
    if (success and rept != .LeadParamMinus) {
        try mark_ops.markCreate(
            allocator,
            frame.dot.?.Line,
            frame.dot.?.Col + nch_ident,
            &frame.marks[types.mark_equals],
        );
    }
    return success;
}

pub fn eqsgetrepDumbGet(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    count: isize,
    tpar: *types.TParObject,
    from_span: bool,
) !bool {
    _ = from_span;
    if (count == 0) {
        return true;
    }

    const prepared = try prepareLiteralTarget(tpar);
    defer prepared.target.destroy();

    var new_len = tpar.Len;
    const tail_space = new_len > 1 and prepared.target.get(new_len) == ' ';
    if (tail_space) {
        new_len -= 1;
    }

    var pattern = prepared.target;
    const backwards = count < 0;
    var count_mut = absCount(count);
    var reverse_pattern: ?*str_object.StrObject = null;
    defer if (reverse_pattern) |tmp| tmp.destroy();

    if (backwards) {
        reverse_pattern = try str_object.newBlankStrObject(allocator, types.max_str_len);
        chars.chReverseStr(prepared.target, reverse_pattern.?, new_len);
        pattern = reverse_pattern.?;
    }

    const dot_line = frame.dot.?.Line;
    const dot_col = frame.dot.?.Col;
    var line = dot_line;
    var start_col: isize = if (backwards) 1 else dot_col;
    var length: isize = if (backwards)
        @min(frame.dot.?.Col - 1, line.used)
    else if (start_col > line.used)
        0
    else
        line.used + 1 - start_col;

    while (count_mut > 0) {
        var found = false;
        var offset: isize = 0;
        if (length != 0) {
            found = try chars.chSearchStr(
                allocator,
                pattern,
                1,
                new_len,
                line.str.?,
                start_col,
                length,
                prepared.exactcase,
                backwards,
                &offset,
            );
        }

        if (found) {
            var process_match = true;
            if (tail_space) {
                var tail_char: u8 = 0;
                if (start_col + offset + new_len <= line.used) {
                    tail_char = line.str.?.get(start_col + offset + new_len);
                } else if (start_col + offset + new_len == line.used + 1) {
                    tail_char = if (line.used + 1 == types.max_str_len_p1) 0 else ' ';
                }
                if (tail_char != ' ') {
                    if (backwards) {
                        start_col = start_col + offset + new_len - 1;
                    } else {
                        start_col += 1;
                    }
                    process_match = false;
                }
            }

            if (process_match) {
                start_col += offset;
                if (!backwards) {
                    start_col += tpar.Len;
                }
                count_mut -= 1;
                if (count_mut == 0) {
                    try mark_ops.markCreate(allocator, line, start_col, &frame.dot);
                    if (backwards) {
                        try mark_ops.markCreate(allocator, line, start_col + tpar.Len, &frame.marks[types.mark_equals]);
                    } else {
                        try mark_ops.markCreate(allocator, line, start_col - tpar.Len, &frame.marks[types.mark_equals]);
                    }
                    return true;
                }
            }

            if (backwards) {
                length = start_col - 1;
                start_col = 1;
            } else if (start_col > line.used) {
                length = 0;
            } else {
                length = line.used + 1 - start_col;
            }
        } else {
            line = nextSearchLine(line, backwards) orelse break;
            start_col = 1;
            length = line.used;
        }
    }
    return false;
}

pub fn eqsgetrepPatternGet(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    count: isize,
    tpar: *types.TParObject,
    from_span: bool,
    replace_flag: bool,
) !bool {
    _ = from_span;
    if (count == 0) {
        return true;
    }

    const pattern_ptr = if (!replace_flag) blk: {
        if (!try eqsgetrepPatternBuild(allocator, frame, tpar, &frame.get_pattern_ptr)) {
            return false;
        }
        break :blk frame.get_pattern_ptr.?;
    } else frame.rep_pattern_ptr.?;

    const dot_line = frame.dot.?.Line;
    const dot_col = frame.dot.?.Col;
    var line = dot_line;
    var mark_flag = false;
    const backwards = count < 0;
    var start_col: isize = if (backwards) 1 else dot_col;
    var count_mut = absCount(count);
    if (start_col > line.used) {
        start_col = line.used + 1;
    }

    while (count_mut > 0) {
        var matched_start_col: isize = 0;
        var matched_finish_col: isize = 0;
        if (try recognize.patternRecognize(
            allocator,
            frame,
            pattern_ptr,
            line,
            start_col,
            &mark_flag,
            &matched_start_col,
            &matched_finish_col,
        )) {
            if (!((line == dot_line) and (matched_finish_col >= dot_col) and backwards)) {
                count_mut -= 1;
                if (count_mut == 0) {
                    if (backwards) {
                        try mark_ops.markCreate(allocator, line, matched_start_col, &frame.dot);
                        try mark_ops.markCreate(allocator, line, matched_finish_col, &frame.marks[types.mark_equals]);
                    } else {
                        try mark_ops.markCreate(allocator, line, matched_finish_col, &frame.dot);
                        try mark_ops.markCreate(allocator, line, matched_start_col, &frame.marks[types.mark_equals]);
                    }
                    return true;
                }
                start_col = matched_finish_col;
                if (start_col == matched_start_col) {
                    mark_flag = true;
                }
                if (start_col > line.used) {
                    line = nextSearchLine(line, backwards) orelse break;
                    mark_flag = false;
                    start_col = 1;
                }
            } else {
                line = nextSearchLine(line, true) orelse break;
                mark_flag = false;
                start_col = 1;
            }
        } else {
            line = nextSearchLine(line, backwards) orelse break;
            mark_flag = false;
            start_col = 1;
        }
    }
    return false;
}

pub fn eqsGetRepGet(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    count: isize,
    tpar: *types.TParObject,
    from_span: bool,
) !bool {
    if (tpar.Dlm == types.tpd_smart) {
        return eqsgetrepPatternGet(allocator, frame, count, tpar, from_span, false);
    }
    return eqsgetrepDumbGet(allocator, frame, count, tpar, from_span);
}

fn markPrecedes(left: *types.MarkObject, right: *types.MarkObject) bool {
    const left_line_nr = line_ops.lineToNumber(left.Line);
    const right_line_nr = line_ops.lineToNumber(right.Line);
    return left_line_nr < right_line_nr or (left_line_nr == right_line_nr and left.Col <= right.Col);
}

fn normalizeMatchRange(frame: *types.FrameObject) struct {
    start_line: *types.LineHdrObject,
    start_col: isize,
    end_line: *types.LineHdrObject,
    end_col: isize,
} {
    const dot = frame.dot.?;
    const eql = frame.marks[types.mark_equals].?;
    if (markPrecedes(dot, eql)) {
        return .{
            .start_line = dot.Line,
            .start_col = dot.Col,
            .end_line = eql.Line,
            .end_col = eql.Col,
        };
    }
    return .{
        .start_line = eql.Line,
        .start_col = eql.Col,
        .end_line = dot.Line,
        .end_col = dot.Col,
    };
}

pub fn eqsGetRepRep(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
    tpar: *types.TParObject,
    tpar2: *types.TParObject,
    from_span: bool,
) !bool {
    _ = from_span;
    var result = false;
    var old_dot: ?*types.MarkObject = null;
    var old_equals: ?*types.MarkObject = null;
    defer {
        mark_ops.markDestroy(allocator, &old_dot);
        mark_ops.markDestroy(allocator, &old_equals);
    }

    try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &old_dot);
    if (frame.marks[types.mark_equals]) |eql| {
        try mark_ops.markCreate(allocator, eql.Line, eql.Col, &old_equals);
    }

    if (tpar.Dlm == types.tpd_smart) {
        if (!try eqsgetrepPatternBuild(allocator, frame, tpar, &frame.rep_pattern_ptr)) {
            return result;
        }
    }

    const getcount: isize = switch (rept) {
        .LeadParamMinus, .LeadParamNIndef, .LeadParamNInt => -1,
        else => 1,
    };

    var remaining = count;
    if (rept == .LeadParamPIndef or rept == .LeadParamNIndef) {
        remaining = types.max_int;
    } else if (remaining < 0) {
        remaining = -remaining;
    }

    while (remaining > 0) {
        const found = if (tpar.Dlm == types.tpd_smart)
            try eqsgetrepPatternGet(allocator, frame, getcount, tpar, true, true)
        else
            try eqsgetrepDumbGet(allocator, frame, getcount, tpar, true);
        if (!found) {
            break;
        }

        var replace_start: ?*types.MarkObject = null;
        var replace_end: ?*types.MarkObject = null;
        defer {
            mark_ops.markDestroy(allocator, &replace_start);
            mark_ops.markDestroy(allocator, &replace_end);
        }

        const range = normalizeMatchRange(frame);
        try mark_ops.markCreate(allocator, range.start_line, range.start_col, &replace_start);
        try mark_ops.markCreate(allocator, range.end_line, range.end_col, &replace_end);

        if (!try text.textRemove(allocator, replace_start.?, replace_end.?)) {
            return result;
        }
        if (!try text.textInsertTpar(allocator, tpar2, replace_start.?, &frame.marks[types.mark_equals])) {
            return result;
        }

        const inserted_start_line = frame.marks[types.mark_equals].?.Line;
        const inserted_start_col = frame.marks[types.mark_equals].?.Col;
        const inserted_end_line = replace_start.?.Line;
        const inserted_end_col = replace_start.?.Col;

        if (getcount > 0) {
            try mark_ops.markCreate(allocator, inserted_end_line, inserted_end_col, &frame.dot);
            try mark_ops.markCreate(allocator, inserted_start_line, inserted_start_col, &frame.marks[types.mark_equals]);
        } else {
            try mark_ops.markCreate(allocator, inserted_start_line, inserted_start_col, &frame.dot);
            try mark_ops.markCreate(allocator, inserted_end_line, inserted_end_col, &frame.marks[types.mark_equals]);
        }

        try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &old_dot);
        if (frame.marks[types.mark_equals]) |eql| {
            try mark_ops.markCreate(allocator, eql.Line, eql.Col, &old_equals);
        } else {
            mark_ops.markDestroy(allocator, &old_equals);
        }

        frame.text_modified = true;
        try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &frame.marks[types.mark_modified]);
        remaining -= 1;
    }

    try mark_ops.markCreate(allocator, old_dot.?.Line, old_dot.?.Col, &frame.dot);
    if (old_equals) |eql| {
        try mark_ops.markCreate(allocator, eql.Line, eql.Col, &frame.marks[types.mark_equals]);
    } else {
        mark_ops.markDestroy(allocator, &frame.marks[types.mark_equals]);
    }
    result = remaining == 0 or rept == .LeadParamPIndef or rept == .LeadParamNIndef;
    return result;
}

test "eqs get rep eqs supports smart patterns and literal comparisons" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{"Hello WORLD"});
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 7, &fixture.frame.dot);

    var smart = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "'world'"),
        .Len = 7,
        .Dlm = types.tpd_smart,
    };
    try std.testing.expect(try eqsGetRepEqs(allocator, fixture.frame, .LeadParamNone, &smart));
    try std.testing.expectEqual(@as(isize, 12), fixture.frame.marks[types.mark_equals].?.Col);

    try mark_ops.markCreate(allocator, fixture.content_lines[0], 1, &fixture.frame.dot);
    var literal = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "HELLO"),
        .Len = 5,
        .Dlm = types.tpd_lit,
    };
    try std.testing.expect(try eqsGetRepEqs(allocator, fixture.frame, .LeadParamNone, &literal));
    try std.testing.expectEqual(@as(isize, 6), fixture.frame.marks[types.mark_equals].?.Col);
}

test "eqs get rep get searches forward and backward for smart and literal targets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{
        "zero",
        "foo@bar.com",
        "hello world test",
    });

    try mark_ops.markCreate(allocator, fixture.content_lines[0], 1, &fixture.frame.dot);
    const email_pattern = "+a'@'+a'.'+a";
    var smart = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, email_pattern),
        .Len = email_pattern.len,
        .Dlm = types.tpd_smart,
    };
    try std.testing.expect(try eqsGetRepGet(allocator, fixture.frame, 1, &smart, true));
    try std.testing.expect(fixture.frame.dot.?.Line == fixture.content_lines[1]);
    try std.testing.expectEqual(@as(isize, 12), fixture.frame.dot.?.Col);
    try std.testing.expectEqual(@as(isize, 1), fixture.frame.marks[types.mark_equals].?.Col);

    try mark_ops.markCreate(allocator, fixture.content_lines[2], 12, &fixture.frame.dot);
    var literal = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "world"),
        .Len = 5,
        .Dlm = types.tpd_lit,
    };
    try std.testing.expect(try eqsGetRepGet(allocator, fixture.frame, -1, &literal, true));
    try std.testing.expect(fixture.frame.dot.?.Line == fixture.content_lines[2]);
    try std.testing.expectEqual(@as(isize, 7), fixture.frame.dot.?.Col);
    try std.testing.expectEqual(@as(isize, 12), fixture.frame.marks[types.mark_equals].?.Col);
}

test "eqs get rep get prefers the longest bounded repeat at the first match column" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{"1234def"});
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 1, &fixture.frame.dot);

    const pattern = "[,3]N";
    var smart = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, pattern),
        .Len = pattern.len,
        .Dlm = types.tpd_smart,
    };
    try std.testing.expect(try eqsGetRepGet(allocator, fixture.frame, 1, &smart, true));
    try std.testing.expect(fixture.frame.dot.?.Line == fixture.content_lines[0]);
    try std.testing.expectEqual(@as(isize, 4), fixture.frame.dot.?.Col);
    try std.testing.expectEqual(@as(isize, 1), fixture.frame.marks[types.mark_equals].?.Col);
}

test "eqs get rep get does not match visible eop labels as text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"abc"});
    try line_ops.lineChangeLength(allocator, fixture.sentinel_line, @intCast("<End of File>  ".len));
    try line_ops.setLineContent(fixture.sentinel_line, "<End of File>  ");
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 1, &fixture.frame.dot);

    const pattern = "U";
    var smart = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, pattern),
        .Len = pattern.len,
        .Dlm = types.tpd_smart,
    };
    try std.testing.expect(!try eqsGetRepGet(allocator, fixture.frame, 1, &smart, true));
}

test "eqs get rep replace updates content and preserves forward and backward cursor semantics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const forward_fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{"hello world test"});
    try mark_ops.markCreate(allocator, forward_fixture.content_lines[0], 1, &forward_fixture.frame.dot);
    var target = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "world"),
        .Len = 5,
        .Dlm = types.tpd_lit,
    };
    var replacement = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "earth"),
        .Len = 5,
        .Dlm = types.tpd_lit,
    };
    try std.testing.expect(try eqsGetRepRep(allocator, forward_fixture.frame, .LeadParamPlus, 1, &target, &replacement, true));
    try std.testing.expectEqualStrings("hello earth test", forward_fixture.content_lines[0].str.?.slice(1, 16));
    try std.testing.expectEqual(@as(isize, 12), forward_fixture.frame.dot.?.Col);
    try std.testing.expectEqual(@as(isize, 7), forward_fixture.frame.marks[types.mark_equals].?.Col);
    try std.testing.expect(forward_fixture.frame.text_modified);
    try std.testing.expect(forward_fixture.frame.marks[types.mark_modified] != null);

    const backward_fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{"hello world test"});
    try mark_ops.markCreate(allocator, backward_fixture.content_lines[0], 12, &backward_fixture.frame.dot);
    try std.testing.expect(try eqsGetRepRep(allocator, backward_fixture.frame, .LeadParamMinus, -1, &target, &replacement, true));
    try std.testing.expectEqualStrings("hello earth test", backward_fixture.content_lines[0].str.?.slice(1, 16));
    try std.testing.expectEqual(@as(isize, 7), backward_fixture.frame.dot.?.Col);
    try std.testing.expectEqual(@as(isize, 12), backward_fixture.frame.marks[types.mark_equals].?.Col);
}

test "eqs get rep replace supports multiline replacement chains" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{"Hello World"});
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 1, &fixture.frame.dot);

    var target = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "World"),
        .Len = 5,
        .Dlm = types.tpd_lit,
    };
    var repl2 = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "Line2"),
        .Len = 5,
    };
    var repl1 = types.TParObject{
        .str = try str_object.newStrObjectFrom(allocator, "Line1"),
        .Len = 5,
        .Con = &repl2,
    };

    try std.testing.expect(try eqsGetRepRep(allocator, fixture.frame, .LeadParamPlus, 1, &target, &repl1, true));
    try std.testing.expectEqualStrings("Hello Line1", fixture.content_lines[0].str.?.slice(1, 11));
    try std.testing.expect(fixture.content_lines[0].f_link != null);
    try std.testing.expectEqualStrings("Line2", fixture.content_lines[0].f_link.?.str.?.slice(1, 5));
}
