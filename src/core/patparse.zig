const std = @import("std");
const chars = @import("chars.zig");
const types = @import("types.zig");

pub const quoted_set = blk: {
    var set = [_]bool{false} ** (types.max_set_range + 1);
    set[types.tpd_lit] = true;
    set[types.tpd_exact] = true;
    break :blk set;
};

pub const delimited_set = blk: {
    var set = [_]bool{false} ** (types.max_set_range + 1);
    set[types.pattern_k_star] = true;
    set[types.pattern_plus] = true;
    set[types.pattern_l_range_delim] = true;
    var ch: u8 = '0';
    while (ch <= '9') : (ch += 1) {
        set[ch] = true;
    }
    break :blk set;
};

pub const charsets_set = blk: {
    var set = [_]bool{false} ** (types.max_set_range + 1);
    for ("sSaAcClLuUnNpP") |ch| {
        set[ch] = true;
    }
    break :blk set;
};

pub const positionals_set = blk: {
    var set = [_]bool{false} ** (types.max_set_range + 1);
    for ("<>{}^") |ch| {
        set[ch] = true;
    }
    break :blk set;
};

pub const ch_and_pos_set = blk: {
    var set = [_]bool{false} ** (types.max_set_range + 1);
    var i: usize = 0;
    while (i <= types.max_set_range) : (i += 1) {
        set[i] = charsets_set[i] or positionals_set[i];
    }
    break :blk set;
};

pub const syntax_set = blk: {
    var set = [_]bool{false} ** (types.max_set_range + 1);
    for ([_]u8{
        types.tpd_span,        types.tpd_prompt,            types.tpd_exact,      types.tpd_lit,
        types.pattern_l_paren, types.pattern_l_range_delim, types.pattern_k_star, types.pattern_plus,
        types.pattern_negate,  types.pattern_mark,          types.pattern_equals, types.pattern_modified,
        '{',                   '}',                         '<',                  '>',
        '^',
    }) |ch| {
        set[ch] = true;
    }
    var digit: u8 = '0';
    while (digit <= '9') : (digit += 1) {
        set[digit] = true;
    }
    var lower: u8 = 'a';
    while (lower <= 'z') : (lower += 1) {
        set[lower] = true;
    }
    var upper: u8 = 'A';
    while (upper <= 'Z') : (upper += 1) {
        set[upper] = true;
    }
    break :blk set;
};

pub const space_set = initSpaceSet();
pub const printable_set = initPrintableSet();
pub const alpha_set = initAlphaSet();
pub const lower_set = initLowerSet();
pub const upper_set = initUpperSet();
pub const numeric_set = initNumericSet();
pub const punctuation_set = initPunctuationSet();

pub fn singletonSet(ch: u8) types.AcceptSet {
    var set: types.AcceptSet = .{};
    setAdd(&set, ch);
    return set;
}

pub fn rangeSet(start: u8, end: u8) types.AcceptSet {
    var set: types.AcceptSet = .{};
    setAddRange(&set, start, end);
    return set;
}

pub fn setUnion(a: *const types.AcceptSet, b: *const types.AcceptSet) types.AcceptSet {
    var out: types.AcceptSet = .{};
    var i: usize = 0;
    while (i <= types.max_set_range) : (i += 1) {
        if (a.bit(i) == 1 or b.bit(i) == 1) {
            out.setBit(i);
        }
    }
    return out;
}

pub fn setRemove(a: *const types.AcceptSet, b: *const types.AcceptSet) types.AcceptSet {
    var out: types.AcceptSet = .{};
    var i: usize = 0;
    while (i <= types.max_set_range) : (i += 1) {
        if (a.bit(i) == 1 and b.bit(i) == 0) {
            out.setBit(i);
        }
    }
    return out;
}

pub fn setAdd(set: *types.AcceptSet, ch: u8) void {
    set.setBit(ch);
}

pub fn setAddRange(set: *types.AcceptSet, start: u8, end: u8) void {
    var ch: u16 = start;
    while (ch <= end) : (ch += 1) {
        set.setBit(ch);
    }
}

fn initSpaceSet() types.AcceptSet {
    return singletonSet(' ');
}

fn initPrintableSet() types.AcceptSet {
    return rangeSet(32, 126);
}

fn initLowerSet() types.AcceptSet {
    return rangeSet('a', 'z');
}

fn initUpperSet() types.AcceptSet {
    return rangeSet('A', 'Z');
}

fn initAlphaSet() types.AcceptSet {
    return setUnion(&lower_set, &upper_set);
}

fn initNumericSet() types.AcceptSet {
    return rangeSet('0', '9');
}

fn initPunctuationSet() types.AcceptSet {
    var set: types.AcceptSet = .{};
    for ([_]u8{ 33, 34, 39, 40, 41, 44, 46, 58, 59, 63, 96 }) |ch| {
        setAdd(&set, ch);
    }
    return set;
}

const RepeatSpec = struct {
    min: isize = 1,
    indefinite: bool = false,
};

fn patternCharAt(pattern: *types.TParObject, pos: isize) ?u8 {
    if (pattern.str == null or pos < 1 or pos > pattern.len) return null;
    return pattern.str.?.get(pos);
}

fn skipSpaces(pattern: *types.TParObject, pos: *isize) void {
    while (patternCharAt(pattern, pos.*)) |ch| {
        if (ch != ' ') break;
        pos.* += 1;
    }
}

fn emitAcceptState(
    nfa_table: *types.NFATableType,
    current_state: *isize,
    accept_set: types.AcceptSet,
    indefinite: bool,
) bool {
    if (current_state.* > types.max_nfa_state_range) return false;
    nfa_table[@intCast(current_state.*)].epsilon_out = false;
    nfa_table[@intCast(current_state.*)].accept_set = accept_set;
    nfa_table[@intCast(current_state.*)].indefinite = indefinite;
    nfa_table[@intCast(current_state.*)].next_state = current_state.* + 1;
    current_state.* += 1;
    return current_state.* <= types.max_nfa_state_range + 1;
}

fn fullPatternSet() types.AcceptSet {
    return rangeSet(types.pattern_alpha_start, types.max_set_range);
}

fn parseDefineSet(pattern: *types.TParObject, pos: *isize, out: *types.AcceptSet) bool {
    const delimiter = patternCharAt(pattern, pos.*) orelse return false;
    pos.* += 1;
    var seen_close = false;
    while (patternCharAt(pattern, pos.*)) |ch1| {
        if (ch1 == delimiter) {
            seen_close = true;
            pos.* += 1;
            break;
        }
        var ch2 = ch1;
        pos.* += 1;
        if (patternCharAt(pattern, pos.*)) |dot1| {
            if (dot1 == '.') {
                if (patternCharAt(pattern, pos.* + 1)) |dot2| {
                    if (dot2 == '.') {
                        ch2 = patternCharAt(pattern, pos.* + 2) orelse return false;
                        pos.* += 3;
                    }
                }
            }
        }
        setAddRange(out, ch1, ch2);
    }
    return seen_close;
}

fn parseQuotedLiteral(
    pattern: *types.TParObject,
    pos: *isize,
    delimiter: u8,
    nfa_table: *types.NFATableType,
    current_state: *isize,
    repeat: RepeatSpec,
) bool {
    var chars_seen: isize = 0;
    var literal = std.ArrayList(u8){};
    defer literal.deinit(std.heap.page_allocator);

    while (patternCharAt(pattern, pos.*)) |ch| {
        if (ch == delimiter) {
            pos.* += 1;
            if (chars_seen == 0) {
                return true;
            }
            var reps_left = if (repeat.min > 0) repeat.min else 1;
            while (reps_left > 0) : (reps_left -= 1) {
                for (literal.items, 0..) |item, idx| {
                    const accept = singletonSet(if (delimiter == types.tpd_exact) item else chars.chToUpper(item));
                    const indefinite = repeat.indefinite and reps_left == 1 and idx == literal.items.len - 1;
                    if (!emitAcceptState(nfa_table, current_state, accept, indefinite)) return false;
                }
            }
            return true;
        }
        literal.append(std.heap.page_allocator, ch) catch return false;
        chars_seen += 1;
        pos.* += 1;
    }
    return false;
}

fn parseMark(pattern: *types.TParObject, pos: *isize, out: *types.AcceptSet) bool {
    const first = patternCharAt(pattern, pos.*) orelse return false;
    if (first < '0' or first > '9') return false;
    var value: isize = 0;
    while (patternCharAt(pattern, pos.*)) |ch| {
        if (ch < '0' or ch > '9') break;
        value = (value * 10) + (ch - '0');
        pos.* += 1;
    }
    if (value < types.min_user_mark_number or value > types.max_user_mark_number) return false;
    setAdd(out, @intCast(value + types.pattern_marks_start));
    return true;
}

fn parseRepeat(pattern: *types.TParObject, pos: *isize) ?RepeatSpec {
    const ch = patternCharAt(pattern, pos.*) orelse return RepeatSpec{};
    switch (ch) {
        types.pattern_k_star => {
            pos.* += 1;
            return .{ .min = 0, .indefinite = true };
        },
        types.pattern_plus => {
            pos.* += 1;
            return .{ .min = 1, .indefinite = true };
        },
        '0'...'9' => {
            var count: isize = 0;
            while (patternCharAt(pattern, pos.*)) |digit| {
                if (digit < '0' or digit > '9') break;
                count = (count * 10) + (digit - '0');
                pos.* += 1;
            }
            return .{ .min = if (count > 0) count else 1 };
        },
        types.pattern_l_range_delim => {
            pos.* += 1;
            var start: isize = 0;
            var saw_digit = false;
            while (patternCharAt(pattern, pos.*)) |digit| {
                if (digit < '0' or digit > '9') break;
                start = (start * 10) + (digit - '0');
                pos.* += 1;
                saw_digit = true;
            }
            if (!saw_digit and patternCharAt(pattern, pos.*) != types.pattern_comma) return null;
            if (patternCharAt(pattern, pos.*) != types.pattern_comma) return null;
            pos.* += 1;
            var indefinite = true;
            if (patternCharAt(pattern, pos.*)) |digit| {
                if (digit >= '0' and digit <= '9') {
                    indefinite = false;
                    while (patternCharAt(pattern, pos.*)) |digit2| {
                        if (digit2 < '0' or digit2 > '9') break;
                        pos.* += 1;
                    }
                }
            }
            if (patternCharAt(pattern, pos.*) != types.pattern_r_range_delim) return null;
            pos.* += 1;
            return .{ .min = if (start > 0) start else 1, .indefinite = indefinite or start == 0 };
        },
        else => return RepeatSpec{},
    }
}

fn parseAtom(
    pattern: *types.TParObject,
    pos: *isize,
    nfa_table: *types.NFATableType,
    current_state: *isize,
    depth: isize,
) bool {
    skipSpaces(pattern, pos);
    const repeat = parseRepeat(pattern, pos) orelse return false;
    skipSpaces(pattern, pos);
    const ch = patternCharAt(pattern, pos.*) orelse return false;

    if (!syntax_set[ch] and !delimited_set[ch] and ch != types.pattern_bar and ch != types.pattern_comma and ch != types.pattern_r_paren) {
        return false;
    }

    if (quoted_set[ch]) {
        pos.* += 1;
        return parseQuotedLiteral(pattern, pos, ch, nfa_table, current_state, repeat);
    }

    if (ch == types.pattern_l_paren) {
        pos.* += 1;
        if (depth + 2 > types.pattern_max_depth) return false;
        if (!parseSequence(pattern, pos, nfa_table, current_state, depth + 2, true)) return false;
        skipSpaces(pattern, pos);
        if (patternCharAt(pattern, pos.*) != types.pattern_r_paren) return false;
        pos.* += 1;
        return true;
    }

    var negate = false;
    if (ch == types.pattern_negate) {
        negate = true;
        pos.* += 1;
        skipSpaces(pattern, pos);
    }

    const actual = patternCharAt(pattern, pos.*) orelse return false;
    var accept: types.AcceptSet = .{};

    switch (actual) {
        types.pattern_mark => {
            pos.* += 1;
            if (!parseMark(pattern, pos, &accept)) return false;
        },
        types.pattern_equals => {
            if (negate) return false;
            setAdd(&accept, types.pattern_marks_equals);
            pos.* += 1;
        },
        types.pattern_modified => {
            if (negate) return false;
            setAdd(&accept, types.pattern_marks_modified);
            pos.* += 1;
        },
        types.pattern_define_set_u, types.pattern_define_set_l => {
            pos.* += 1;
            if (!parseDefineSet(pattern, pos, &accept)) return false;
            if (negate) {
                const full = fullPatternSet();
                accept = setRemove(&full, &accept);
            }
        },
        '<', '>', '{', '}', '^' => {
            if (negate) return false;
            switch (actual) {
                '<' => setAdd(&accept, types.pattern_beg_line),
                '>' => setAdd(&accept, types.pattern_end_line),
                '{' => setAdd(&accept, types.pattern_left_margin),
                '}' => setAdd(&accept, types.pattern_right_margin),
                '^' => setAdd(&accept, types.pattern_dot_column),
                else => unreachable,
            }
            pos.* += 1;
        },
        else => {
            const upper = chars.chToUpper(actual);
            switch (upper) {
                'S' => accept = space_set,
                'C' => accept = printable_set,
                'A' => accept = alpha_set,
                'L' => accept = lower_set,
                'U' => accept = upper_set,
                'N' => accept = numeric_set,
                'P' => accept = punctuation_set,
                else => return false,
            }
            if (negate) {
                const full = fullPatternSet();
                accept = setRemove(&full, &accept);
            }
            pos.* += 1;
        },
    }

    var reps_left = if (repeat.min > 0) repeat.min else 1;
    while (reps_left > 0) : (reps_left -= 1) {
        if (!emitAcceptState(nfa_table, current_state, accept, repeat.indefinite and reps_left == 1)) return false;
    }
    return true;
}

fn parseSequence(
    pattern: *types.TParObject,
    pos: *isize,
    nfa_table: *types.NFATableType,
    current_state: *isize,
    depth: isize,
    stop_at_rparen: bool,
) bool {
    var saw_content = false;
    while (true) {
        skipSpaces(pattern, pos);
        const ch = patternCharAt(pattern, pos.*) orelse break;
        if (ch == types.pattern_comma or ch == types.pattern_bar or (stop_at_rparen and ch == types.pattern_r_paren)) break;
        if (!parseAtom(pattern, pos, nfa_table, current_state, depth)) return false;
        saw_content = true;
        skipSpaces(pattern, pos);
    }

    skipSpaces(pattern, pos);
    while (patternCharAt(pattern, pos.*) == types.pattern_bar) {
        pos.* += 1;
        skipSpaces(pattern, pos);
        if (patternCharAt(pattern, pos.*) == types.pattern_r_paren or patternCharAt(pattern, pos.*) == types.pattern_comma or patternCharAt(pattern, pos.*) == null) {
            continue;
        }
        if (!parseSequence(pattern, pos, nfa_table, current_state, depth, stop_at_rparen)) return false;
        saw_content = true;
        skipSpaces(pattern, pos);
    }
    return saw_content or patternCharAt(pattern, pos.*) == types.pattern_r_paren;
}

pub fn patternParser(
    frame: ?*types.FrameObject,
    pattern: *types.TParObject,
    nfa_table: *types.NFATableType,
    first_pattern_start: *isize,
    pattern_final_state: *isize,
    left_context_end: *isize,
    middle_context_end: *isize,
    pattern_definition: *types.PatternDefType,
    states_used: *isize,
) bool {
    _ = frame;
    nfa_table.* = [_]types.NFATransitionType{.{}} ** (types.max_nfa_state_range + 1);
    if (pattern.str == null or pattern.len == 0) return false;

    pattern_definition.* = .{
        .strng = pattern.str,
        .length = pattern.len,
    };

    first_pattern_start.* = types.pattern_nfa_start;
    left_context_end.* = first_pattern_start.*;
    middle_context_end.* = left_context_end.*;

    var pos: isize = 1;
    var current_state: isize = types.pattern_nfa_start;

    if (!parseSequence(pattern, &pos, nfa_table, &current_state, 2, false)) return false;
    skipSpaces(pattern, &pos);
    if (patternCharAt(pattern, pos) == types.pattern_comma) {
        left_context_end.* = current_state;
        pos += 1;
        if (!parseSequence(pattern, &pos, nfa_table, &current_state, 2, false)) return false;
        skipSpaces(pattern, &pos);
        if (patternCharAt(pattern, pos) == types.pattern_comma) {
            middle_context_end.* = current_state;
            pos += 1;
            if (!parseSequence(pattern, &pos, nfa_table, &current_state, 2, false)) return false;
        } else {
            middle_context_end.* = left_context_end.*;
        }
    }

    skipSpaces(pattern, &pos);
    if (pos <= pattern.len) return false;

    pattern_final_state.* = current_state;
    states_used.* = current_state;
    return current_state > types.pattern_nfa_start;
}

fn countBits(set: *const types.AcceptSet) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i <= types.max_set_range) : (i += 1) {
        if (set.bit(i) == 1) count += 1;
    }
    return count;
}

test "pattern helper sets build expected character memberships" {
    const az = rangeSet('a', 'z');
    try std.testing.expectEqual(@as(u1, 1), singletonSet('a').bit('a'));
    try std.testing.expectEqual(@as(usize, 26), countBits(&az));
    try std.testing.expectEqual(@as(u1, 1), space_set.bit(' '));
    try std.testing.expectEqual(@as(u1, 1), lower_set.bit('a'));
    try std.testing.expectEqual(@as(u1, 1), upper_set.bit('A'));
    try std.testing.expectEqual(@as(u1, 1), alpha_set.bit('z'));
    try std.testing.expectEqual(@as(u1, 1), numeric_set.bit('8'));
    try std.testing.expectEqual(@as(u1, 1), punctuation_set.bit('!'));
    try std.testing.expect(quoted_set[types.tpd_lit]);
    try std.testing.expect(delimited_set[types.pattern_k_star]);
    try std.testing.expect(charsets_set['s']);
    try std.testing.expect(positionals_set['<']);
    try std.testing.expect(ch_and_pos_set['^']);
    try std.testing.expect(syntax_set['a']);
}

test "pattern parser accepts common pattern forms and populates accept sets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const single_class = "s";
    const tpar = types.TParObject{
        .str = try @import("str_object.zig").newStrObjectFrom(allocator, single_class),
        .len = single_class.len,
    };
    var nfa_table: types.NFATableType = [_]types.NFATransitionType{.{}} ** (types.max_nfa_state_range + 1);
    var pattern_def: types.PatternDefType = .{};
    var first_start: isize = 0;
    var final_state: isize = 0;
    var left_end: isize = 0;
    var middle_end: isize = 0;
    var states_used: isize = 0;

    try std.testing.expect(patternParser(null, @constCast(&tpar), &nfa_table, &first_start, &final_state, &left_end, &middle_end, &pattern_def, &states_used));
    try std.testing.expect(states_used > types.pattern_nfa_start);
    try std.testing.expectEqual(@as(u1, 1), nfa_table[types.pattern_nfa_start].accept_set.bit(' '));

    const email_like = "+a'@'+a'.'+a";
    var literal = types.TParObject{
        .str = try @import("str_object.zig").newStrObjectFrom(allocator, email_like),
        .len = email_like.len,
    };
    try std.testing.expect(patternParser(null, &literal, &nfa_table, &first_start, &final_state, &left_end, &middle_end, &pattern_def, &states_used));

    const context_source = "'a','b','c'";
    var context_pattern = types.TParObject{
        .str = try @import("str_object.zig").newStrObjectFrom(allocator, context_source),
        .len = context_source.len,
    };
    try std.testing.expect(patternParser(null, &context_pattern, &nfa_table, &first_start, &final_state, &left_end, &middle_end, &pattern_def, &states_used));
    try std.testing.expect(left_end != first_start);
    try std.testing.expect(middle_end != left_end);

    const trailing_bar_source = "('+'|'-'|)+n";
    var trailing_bar = types.TParObject{
        .str = try @import("str_object.zig").newStrObjectFrom(allocator, trailing_bar_source),
        .len = trailing_bar_source.len,
    };
    try std.testing.expect(patternParser(null, &trailing_bar, &nfa_table, &first_start, &final_state, &left_end, &middle_end, &pattern_def, &states_used));
}

test "pattern parser rejects malformed inputs and enforces nesting limits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var nfa_table: types.NFATableType = [_]types.NFATransitionType{.{}} ** (types.max_nfa_state_range + 1);
    var pattern_def: types.PatternDefType = .{};
    var first_start: isize = 0;
    var final_state: isize = 0;
    var left_end: isize = 0;
    var middle_end: isize = 0;
    var states_used: isize = 0;

    for ([_][]const u8{
        "",
        "'abc",
        "\"abc",
        "('abc'",
        "@0",
        "@10",
        "@",
        "-<",
        "-",
        "[2a]n",
        "[2,5n",
        "[",
        "D",
        "D'abc",
        "((((((((((a))))))))))",
        "#",
    }) |content| {
        var tpar = types.TParObject{
            .str = try @import("str_object.zig").newStrObjectFrom(allocator, content),
            .len = @intCast(content.len),
        };
        try std.testing.expect(!patternParser(null, &tpar, &nfa_table, &first_start, &final_state, &left_end, &middle_end, &pattern_def, &states_used));
    }

    for ([_][]const u8{
        "@1",
        "=",
        "%",
        "D'abc'",
        "-D'abc'",
        "D'a..z'",
        "(((((((((a)))))))))",
    }) |content| {
        var tpar = types.TParObject{
            .str = try @import("str_object.zig").newStrObjectFrom(allocator, content),
            .len = @intCast(content.len),
        };
        try std.testing.expect(patternParser(null, &tpar, &nfa_table, &first_start, &final_state, &left_end, &middle_end, &pattern_def, &states_used));
    }
}
