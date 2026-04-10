const std = @import("std");
const chars = @import("chars.zig");
const types = @import("types.zig");

comptime {
    @setEvalBranchQuota(10_000);
}

pub const quotedSet = blk: {
    var set = [_]bool{false} ** (types.MaxSetRange + 1);
    set[types.TpdLit] = true;
    set[types.TpdExact] = true;
    break :blk set;
};

pub const delimitedSet = blk: {
    var set = [_]bool{false} ** (types.MaxSetRange + 1);
    set[types.PatternKStar] = true;
    set[types.PatternPlus] = true;
    set[types.PatternLRangeDelim] = true;
    var ch: u8 = '0';
    while (ch <= '9') : (ch += 1) {
        set[ch] = true;
    }
    break :blk set;
};

pub const charsetsSet = blk: {
    var set = [_]bool{false} ** (types.MaxSetRange + 1);
    for ("sSaAcClLuUnNpP") |ch| {
        set[ch] = true;
    }
    break :blk set;
};

pub const positionalsSet = blk: {
    var set = [_]bool{false} ** (types.MaxSetRange + 1);
    for ("<>{}^") |ch| {
        set[ch] = true;
    }
    break :blk set;
};

pub const chAndPosSet = blk: {
    var set = [_]bool{false} ** (types.MaxSetRange + 1);
    var i: usize = 0;
    while (i <= types.MaxSetRange) : (i += 1) {
        set[i] = charsetsSet[i] or positionalsSet[i];
    }
    break :blk set;
};

pub const syntaxSet = blk: {
    var set = [_]bool{false} ** (types.MaxSetRange + 1);
    for ([_]u8{
        types.TpdSpan,       types.TpdPrompt,          types.TpdExact,      types.TpdLit,
        types.PatternLParen, types.PatternLRangeDelim, types.PatternKStar,  types.PatternPlus,
        types.PatternNegate, types.PatternMark,        types.PatternEquals, types.PatternModified,
        '{',                 '}',                      '<',                 '>',
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

pub const spaceSet = initSpaceSet();
pub const printableSet = initPrintableSet();
pub const alphaSet = initAlphaSet();
pub const lowerSet = initLowerSet();
pub const upperSet = initUpperSet();
pub const numericSet = initNumericSet();
pub const punctuationSet = initPunctuationSet();

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
    while (i <= types.MaxSetRange) : (i += 1) {
        if (a.Bit(i) == 1 or b.Bit(i) == 1) {
            out.setBit(i);
        }
    }
    return out;
}

pub fn setRemove(a: *const types.AcceptSet, b: *const types.AcceptSet) types.AcceptSet {
    var out: types.AcceptSet = .{};
    var i: usize = 0;
    while (i <= types.MaxSetRange) : (i += 1) {
        if (a.Bit(i) == 1 and b.Bit(i) == 0) {
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
    return setUnion(&lowerSet, &upperSet);
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
    if (pattern.Str == null or pos < 1 or pos > pattern.Len) return null;
    return pattern.Str.?.Get(pos);
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
    if (current_state.* > types.MaxNFAStateRange) return false;
    nfa_table[@intCast(current_state.*)].EpsilonOut = false;
    nfa_table[@intCast(current_state.*)].AcceptSet = accept_set;
    nfa_table[@intCast(current_state.*)].Indefinite = indefinite;
    nfa_table[@intCast(current_state.*)].NextState = current_state.* + 1;
    current_state.* += 1;
    return current_state.* <= types.MaxNFAStateRange + 1;
}

fn fullPatternSet() types.AcceptSet {
    return rangeSet(types.PatternAlphaStart, types.MaxSetRange);
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
    var literal = std.ArrayListUnmanaged(u8){};
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
                    const accept = singletonSet(if (delimiter == types.TpdExact) item else chars.ChToUpper(item));
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
    if (value < types.MinUserMarkNumber or value > types.MaxUserMarkNumber) return false;
    setAdd(out, @intCast(value + types.PatternMarksStart));
    return true;
}

fn parseRepeat(pattern: *types.TParObject, pos: *isize) ?RepeatSpec {
    const ch = patternCharAt(pattern, pos.*) orelse return RepeatSpec{};
    switch (ch) {
        types.PatternKStar => {
            pos.* += 1;
            return .{ .min = 0, .indefinite = true };
        },
        types.PatternPlus => {
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
        types.PatternLRangeDelim => {
            pos.* += 1;
            var start: isize = 0;
            var saw_digit = false;
            while (patternCharAt(pattern, pos.*)) |digit| {
                if (digit < '0' or digit > '9') break;
                start = (start * 10) + (digit - '0');
                pos.* += 1;
                saw_digit = true;
            }
            if (!saw_digit and patternCharAt(pattern, pos.*) != types.PatternComma) return null;
            if (patternCharAt(pattern, pos.*) != types.PatternComma) return null;
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
            if (patternCharAt(pattern, pos.*) != types.PatternRRangeDelim) return null;
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

    if (!syntaxSet[ch] and !delimitedSet[ch] and ch != types.PatternBar and ch != types.PatternComma and ch != types.PatternRParen) {
        return false;
    }

    if (quotedSet[ch]) {
        pos.* += 1;
        return parseQuotedLiteral(pattern, pos, ch, nfa_table, current_state, repeat);
    }

    if (ch == types.PatternLParen) {
        pos.* += 1;
        if (depth + 2 > types.PatternMaxDepth) return false;
        if (!parseSequence(pattern, pos, nfa_table, current_state, depth + 2, true)) return false;
        skipSpaces(pattern, pos);
        if (patternCharAt(pattern, pos.*) != types.PatternRParen) return false;
        pos.* += 1;
        return true;
    }

    var negate = false;
    if (ch == types.PatternNegate) {
        negate = true;
        pos.* += 1;
        skipSpaces(pattern, pos);
    }

    const actual = patternCharAt(pattern, pos.*) orelse return false;
    var accept: types.AcceptSet = .{};

    switch (actual) {
        types.PatternMark => {
            pos.* += 1;
            if (!parseMark(pattern, pos, &accept)) return false;
        },
        types.PatternEquals => {
            if (negate) return false;
            setAdd(&accept, types.PatternMarksEquals);
            pos.* += 1;
        },
        types.PatternModified => {
            if (negate) return false;
            setAdd(&accept, types.PatternMarksModified);
            pos.* += 1;
        },
        types.PatternDefineSetU, types.PatternDefineSetL => {
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
                '<' => setAdd(&accept, types.PatternBegLine),
                '>' => setAdd(&accept, types.PatternEndLine),
                '{' => setAdd(&accept, types.PatternLeftMargin),
                '}' => setAdd(&accept, types.PatternRightMargin),
                '^' => setAdd(&accept, types.PatternDotColumn),
                else => unreachable,
            }
            pos.* += 1;
        },
        else => {
            const upper = chars.ChToUpper(actual);
            switch (upper) {
                'S' => accept = spaceSet,
                'C' => accept = printableSet,
                'A' => accept = alphaSet,
                'L' => accept = lowerSet,
                'U' => accept = upperSet,
                'N' => accept = numericSet,
                'P' => accept = punctuationSet,
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
        if (ch == types.PatternComma or ch == types.PatternBar or (stop_at_rparen and ch == types.PatternRParen)) break;
        if (!parseAtom(pattern, pos, nfa_table, current_state, depth)) return false;
        saw_content = true;
        skipSpaces(pattern, pos);
    }

    skipSpaces(pattern, pos);
    while (patternCharAt(pattern, pos.*) == types.PatternBar) {
        pos.* += 1;
        skipSpaces(pattern, pos);
        if (patternCharAt(pattern, pos.*) == types.PatternRParen or patternCharAt(pattern, pos.*) == types.PatternComma or patternCharAt(pattern, pos.*) == null) {
            continue;
        }
        if (!parseSequence(pattern, pos, nfa_table, current_state, depth, stop_at_rparen)) return false;
        saw_content = true;
        skipSpaces(pattern, pos);
    }
    return saw_content or patternCharAt(pattern, pos.*) == types.PatternRParen;
}

pub fn PatternParser(
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
    nfa_table.* = [_]types.NFATransitionType{.{}} ** (types.MaxNFAStateRange + 1);
    if (pattern.Str == null or pattern.Len == 0) return false;

    pattern_definition.* = .{
        .Strng = pattern.Str,
        .Length = pattern.Len,
    };

    first_pattern_start.* = types.PatternNFAStart;
    left_context_end.* = first_pattern_start.*;
    middle_context_end.* = left_context_end.*;

    var pos: isize = 1;
    var current_state: isize = types.PatternNFAStart;

    if (!parseSequence(pattern, &pos, nfa_table, &current_state, 2, false)) return false;
    skipSpaces(pattern, &pos);
    if (patternCharAt(pattern, pos) == types.PatternComma) {
        left_context_end.* = current_state;
        pos += 1;
        if (!parseSequence(pattern, &pos, nfa_table, &current_state, 2, false)) return false;
        skipSpaces(pattern, &pos);
        if (patternCharAt(pattern, pos) == types.PatternComma) {
            middle_context_end.* = current_state;
            pos += 1;
            if (!parseSequence(pattern, &pos, nfa_table, &current_state, 2, false)) return false;
        } else {
            middle_context_end.* = left_context_end.*;
        }
    }

    skipSpaces(pattern, &pos);
    if (pos <= pattern.Len) return false;

    pattern_final_state.* = current_state;
    states_used.* = current_state;
    return current_state > types.PatternNFAStart;
}

fn countBits(set: *const types.AcceptSet) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i <= types.MaxSetRange) : (i += 1) {
        if (set.Bit(i) == 1) count += 1;
    }
    return count;
}

test "pattern helper sets build expected character memberships" {
    const az = rangeSet('a', 'z');
    try std.testing.expectEqual(@as(u1, 1), singletonSet('a').Bit('a'));
    try std.testing.expectEqual(@as(usize, 26), countBits(&az));
    try std.testing.expectEqual(@as(u1, 1), spaceSet.Bit(' '));
    try std.testing.expectEqual(@as(u1, 1), lowerSet.Bit('a'));
    try std.testing.expectEqual(@as(u1, 1), upperSet.Bit('A'));
    try std.testing.expectEqual(@as(u1, 1), alphaSet.Bit('z'));
    try std.testing.expectEqual(@as(u1, 1), numericSet.Bit('8'));
    try std.testing.expectEqual(@as(u1, 1), punctuationSet.Bit('!'));
    try std.testing.expect(quotedSet[types.TpdLit]);
    try std.testing.expect(delimitedSet[types.PatternKStar]);
    try std.testing.expect(charsetsSet['s']);
    try std.testing.expect(positionalsSet['<']);
    try std.testing.expect(chAndPosSet['^']);
    try std.testing.expect(syntaxSet['a']);
}

test "pattern parser accepts common pattern forms and populates accept sets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const single_class = "s";
    const tpar = types.TParObject{
        .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, single_class),
        .Len = single_class.len,
    };
    var nfa_table: types.NFATableType = [_]types.NFATransitionType{.{}} ** (types.MaxNFAStateRange + 1);
    var pattern_def: types.PatternDefType = .{};
    var first_start: isize = 0;
    var final_state: isize = 0;
    var left_end: isize = 0;
    var middle_end: isize = 0;
    var states_used: isize = 0;

    try std.testing.expect(PatternParser(null, @constCast(&tpar), &nfa_table, &first_start, &final_state, &left_end, &middle_end, &pattern_def, &states_used));
    try std.testing.expect(states_used > types.PatternNFAStart);
    try std.testing.expectEqual(@as(u1, 1), nfa_table[types.PatternNFAStart].AcceptSet.Bit(' '));

    const email_like = "+a'@'+a'.'+a";
    var literal = types.TParObject{
        .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, email_like),
        .Len = email_like.len,
    };
    try std.testing.expect(PatternParser(null, &literal, &nfa_table, &first_start, &final_state, &left_end, &middle_end, &pattern_def, &states_used));

    const context_source = "'a','b','c'";
    var context_pattern = types.TParObject{
        .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, context_source),
        .Len = context_source.len,
    };
    try std.testing.expect(PatternParser(null, &context_pattern, &nfa_table, &first_start, &final_state, &left_end, &middle_end, &pattern_def, &states_used));
    try std.testing.expect(left_end != first_start);
    try std.testing.expect(middle_end != left_end);

    const trailing_bar_source = "('+'|'-'|)+n";
    var trailing_bar = types.TParObject{
        .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, trailing_bar_source),
        .Len = trailing_bar_source.len,
    };
    try std.testing.expect(PatternParser(null, &trailing_bar, &nfa_table, &first_start, &final_state, &left_end, &middle_end, &pattern_def, &states_used));
}

test "pattern parser rejects malformed inputs and enforces nesting limits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var nfa_table: types.NFATableType = [_]types.NFATransitionType{.{}} ** (types.MaxNFAStateRange + 1);
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
            .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, content),
            .Len = @intCast(content.len),
        };
        try std.testing.expect(!PatternParser(null, &tpar, &nfa_table, &first_start, &final_state, &left_end, &middle_end, &pattern_def, &states_used));
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
            .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, content),
            .Len = @intCast(content.len),
        };
        try std.testing.expect(PatternParser(null, &tpar, &nfa_table, &first_start, &final_state, &left_end, &middle_end, &pattern_def, &states_used));
    }
}
