const std = @import("std");
const chars = @import("chars.zig");
const patparse = @import("patparse.zig");
const types = @import("types.zig");

const TokenKind = enum {
    char,
    positional,
};

const Token = struct {
    kind: TokenKind,
    accept: types.AcceptSet,
};

const Node = union(enum) {
    token: Token,
    seq: []const *Node,
    alt: []const *Node,
    repeat: RepeatNode,
};

const RepeatNode = struct {
    child: *Node,
    min: usize,
    max: ?usize,
};

const CompiledPattern = struct {
    prefix: *Node,
    middle: *Node,
    suffix: *Node,
};

const Event = struct {
    kind: TokenKind,
    accept: types.AcceptSet = .{},
    ch: u8 = 0,
    before_col: isize,
    after_col: isize,
};

const Cursor = struct {
    event_index: usize,
    column: isize,
};

const MatchRange = struct {
    start_col: isize,
    finish_col: isize,
    total_end: Cursor,
};

const StartCursorList = struct {
    items: [2]Cursor = undefined,
    len: usize = 0,
};

const PatternError = error{
    InvalidPattern,
    UnexpectedEnd,
};

const ParseError = PatternError || std.mem.Allocator.Error;
const MatchError = std.mem.Allocator.Error;

const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    index: usize = 0,

    fn parse(self: *Parser) ParseError!CompiledPattern {
        var segments = std.ArrayListUnmanaged(*Node){};
        defer segments.deinit(self.allocator);

        try segments.append(self.allocator, try self.parseExpression(false));
        self.skipSpaces();
        while (self.peek() == ',') {
            self.index += 1;
            try segments.append(self.allocator, try self.parseExpression(false));
            self.skipSpaces();
        }

        if (self.peek() != null) {
            return PatternError.InvalidPattern;
        }

        const empty = try self.makeNode(.{ .seq = try self.allocator.dupe(*Node, &.{}) });
        return switch (segments.items.len) {
            1 => .{
                .prefix = empty,
                .middle = segments.items[0],
                .suffix = empty,
            },
            2 => .{
                .prefix = segments.items[0],
                .middle = segments.items[1],
                .suffix = empty,
            },
            3 => .{
                .prefix = segments.items[0],
                .middle = segments.items[1],
                .suffix = segments.items[2],
            },
            else => PatternError.InvalidPattern,
        };
    }

    fn parseExpression(self: *Parser, stop_at_rparen: bool) ParseError!*Node {
        var alternatives = std.ArrayListUnmanaged(*Node){};
        defer alternatives.deinit(self.allocator);

        try alternatives.append(self.allocator, try self.parseSequence(stop_at_rparen));
        self.skipSpaces();
        while (self.peek() == '|') {
            self.index += 1;
            try alternatives.append(self.allocator, try self.parseSequence(stop_at_rparen));
            self.skipSpaces();
        }

        if (alternatives.items.len == 1) {
            return alternatives.items[0];
        }
        return self.makeNode(.{ .alt = try self.allocator.dupe(*Node, alternatives.items) });
    }

    fn parseSequence(self: *Parser, stop_at_rparen: bool) ParseError!*Node {
        var pieces = std.ArrayListUnmanaged(*Node){};
        defer pieces.deinit(self.allocator);

        self.skipSpaces();
        while (self.peek()) |ch| {
            if (ch == ',' or ch == '|' or (stop_at_rparen and ch == ')')) {
                break;
            }
            try pieces.append(self.allocator, try self.parsePiece(stop_at_rparen));
            self.skipSpaces();
        }

        return self.makeNode(.{ .seq = try self.allocator.dupe(*Node, pieces.items) });
    }

    fn parsePiece(self: *Parser, stop_at_rparen: bool) ParseError!*Node {
        const repeat = try self.parseRepeat();
        const atom = try self.parseAtom(stop_at_rparen);
        if (repeat.min == 1 and repeat.max != null and repeat.max.? == 1) {
            return atom;
        }
        return self.makeNode(.{
            .repeat = .{
                .child = atom,
                .min = repeat.min,
                .max = repeat.max,
            },
        });
    }

    fn parseRepeat(self: *Parser) ParseError!RepeatNode {
        self.skipSpaces();
        const ch = self.peek() orelse return .{ .child = undefined, .min = 1, .max = 1 };
        return switch (ch) {
            types.PatternKStar => blk: {
                self.index += 1;
                break :blk .{ .child = undefined, .min = 0, .max = null };
            },
            types.PatternPlus => blk: {
                self.index += 1;
                break :blk .{ .child = undefined, .min = 1, .max = null };
            },
            '0'...'9' => blk: {
                const count = try self.parseCount();
                break :blk .{ .child = undefined, .min = count, .max = count };
            },
            types.PatternLRangeDelim => blk: {
                self.index += 1;
                self.skipSpaces();
                var min_count: usize = 0;
                var max_count: ?usize = null;
                if (self.peek()) |first| {
                    if (std.ascii.isDigit(first)) {
                        min_count = try self.parseCount();
                    }
                }
                self.skipSpaces();
                if (self.peek() != types.PatternComma) {
                    return PatternError.InvalidPattern;
                }
                self.index += 1;
                self.skipSpaces();
                if (self.peek()) |second| {
                    if (std.ascii.isDigit(second)) {
                        max_count = try self.parseCount();
                    }
                }
                self.skipSpaces();
                if (self.peek() != types.PatternRRangeDelim) {
                    return PatternError.InvalidPattern;
                }
                self.index += 1;
                break :blk .{
                    .child = undefined,
                    .min = min_count,
                    .max = max_count,
                };
            },
            else => .{ .child = undefined, .min = 1, .max = 1 },
        };
    }

    fn parseAtom(self: *Parser, stop_at_rparen: bool) ParseError!*Node {
        _ = stop_at_rparen;
        self.skipSpaces();
        const ch = self.peek() orelse return PatternError.UnexpectedEnd;

        switch (ch) {
            types.TpdLit => return self.parseQuotedLiteral(types.TpdLit),
            types.TpdExact => return self.parseQuotedLiteral(types.TpdExact),
            types.PatternLParen => {
                self.index += 1;
                const expr = try self.parseExpression(true);
                self.skipSpaces();
                if (self.peek() != types.PatternRParen) {
                    return PatternError.InvalidPattern;
                }
                self.index += 1;
                return expr;
            },
            types.PatternMark => {
                self.index += 1;
                var accept: types.AcceptSet = .{};
                patparse.setAdd(&accept, @intCast(types.PatternMarksStart + try self.parseMarkNumber()));
                return self.makeNode(.{
                    .token = .{
                        .kind = .positional,
                        .accept = accept,
                    },
                });
            },
            types.PatternEquals => {
                self.index += 1;
                return self.makeNode(.{
                    .token = .{
                        .kind = .positional,
                        .accept = patparse.singletonSet(types.PatternMarksEquals),
                    },
                });
            },
            types.PatternModified => {
                self.index += 1;
                return self.makeNode(.{
                    .token = .{
                        .kind = .positional,
                        .accept = patparse.singletonSet(types.PatternMarksModified),
                    },
                });
            },
            else => {},
        }

        var negate = false;
        if (ch == types.PatternNegate) {
            negate = true;
            self.index += 1;
        }

        const actual = self.peek() orelse return PatternError.UnexpectedEnd;
        var token = Token{
            .kind = .char,
            .accept = .{},
        };

        switch (actual) {
            types.PatternDefineSetU, types.PatternDefineSetL => {
                self.index += 1;
                token.accept = try self.parseDefineSet();
                if (negate) {
                    const full = patparse.rangeSet(types.PatternAlphaStart, types.MaxSetRange);
                    token.accept = patparse.setRemove(&full, &token.accept);
                }
            },
            '<', '>', '{', '}', '^' => {
                if (negate) {
                    return PatternError.InvalidPattern;
                }
                token.kind = .positional;
                token.accept = switch (actual) {
                    '<' => patparse.singletonSet(types.PatternBegLine),
                    '>' => patparse.singletonSet(types.PatternEndLine),
                    '{' => patparse.singletonSet(types.PatternLeftMargin),
                    '}' => patparse.singletonSet(types.PatternRightMargin),
                    '^' => patparse.singletonSet(types.PatternDotColumn),
                    else => unreachable,
                };
                self.index += 1;
            },
            else => {
                token.kind = .char;
                token.accept = switch (chars.ChToUpper(actual)) {
                    'S' => patparse.spaceSet,
                    'C' => patparse.printableSet,
                    'A' => patparse.alphaSet,
                    'L' => patparse.lowerSet,
                    'U' => patparse.upperSet,
                    'N' => patparse.numericSet,
                    'P' => patparse.punctuationSet,
                    else => return PatternError.InvalidPattern,
                };
                if (negate) {
                    const full = patparse.rangeSet(types.PatternAlphaStart, types.MaxSetRange);
                    token.accept = patparse.setRemove(&full, &token.accept);
                }
                self.index += 1;
            },
        }

        return self.makeNode(.{ .token = token });
    }

    fn parseQuotedLiteral(self: *Parser, delimiter: u8) ParseError!*Node {
        self.index += 1;
        var pieces = std.ArrayListUnmanaged(*Node){};
        defer pieces.deinit(self.allocator);

        while (true) {
            const ch = self.peek() orelse return PatternError.InvalidPattern;
            if (ch == delimiter) {
                self.index += 1;
                break;
            }
            self.index += 1;
            var accept: types.AcceptSet = .{};
            if (delimiter == types.TpdExact or !chars.ChIsLetter(ch)) {
                patparse.setAdd(&accept, ch);
            } else if (chars.ChIsLower(ch)) {
                patparse.setAdd(&accept, ch);
                patparse.setAdd(&accept, chars.ChToUpper(ch));
            } else {
                patparse.setAdd(&accept, ch);
                patparse.setAdd(&accept, chars.ChToLower(ch));
            }
            try pieces.append(self.allocator, try self.makeNode(.{
                .token = .{
                    .kind = .char,
                    .accept = accept,
                },
            }));
        }

        return self.makeNode(.{ .seq = try self.allocator.dupe(*Node, pieces.items) });
    }

    fn parseDefineSet(self: *Parser) ParseError!types.AcceptSet {
        const delimiter = self.peek() orelse return PatternError.InvalidPattern;
        self.index += 1;

        var set: types.AcceptSet = .{};
        while (true) {
            const ch1 = self.peek() orelse return PatternError.InvalidPattern;
            if (ch1 == delimiter) {
                self.index += 1;
                break;
            }
            self.index += 1;
            var ch2 = ch1;
            if (self.index + 1 < self.source.len and self.source[self.index] == '.' and self.source[self.index + 1] == '.') {
                self.index += 2;
                ch2 = self.peek() orelse return PatternError.InvalidPattern;
                self.index += 1;
            }
            patparse.setAddRange(&set, ch1, ch2);
        }
        return set;
    }

    fn parseCount(self: *Parser) ParseError!usize {
        var value: usize = 0;
        var saw_digit = false;
        while (self.peek()) |ch| {
            if (!std.ascii.isDigit(ch)) break;
            saw_digit = true;
            value = (value * 10) + (ch - '0');
            self.index += 1;
        }
        if (!saw_digit) {
            return PatternError.InvalidPattern;
        }
        return value;
    }

    fn parseMarkNumber(self: *Parser) ParseError!usize {
        const value = try self.parseCount();
        if (value < types.MinUserMarkNumber or value > types.MaxUserMarkNumber) {
            return PatternError.InvalidPattern;
        }
        return value;
    }

    fn skipSpaces(self: *Parser) void {
        while (self.peek() == ' ') {
            self.index += 1;
        }
    }

    fn peek(self: *const Parser) ?u8 {
        if (self.index >= self.source.len) return null;
        return self.source[self.index];
    }

    fn makeNode(self: *Parser, value: Node) ParseError!*Node {
        const node = try self.allocator.create(Node);
        node.* = value;
        return node;
    }
};

fn appendCursorUnique(list: *std.ArrayListUnmanaged(Cursor), allocator: std.mem.Allocator, cursor: Cursor) !void {
    for (list.items) |existing| {
        if (existing.event_index == cursor.event_index and existing.column == cursor.column) {
            return;
        }
    }
    try list.append(allocator, cursor);
}

fn acceptSetIntersects(a: *const types.AcceptSet, b: *const types.AcceptSet) bool {
    var index: usize = 0;
    while (index <= types.MaxSetRange) : (index += 1) {
        if (a.Bit(index) == 1 and b.Bit(index) == 1) {
            return true;
        }
    }
    return false;
}

fn searchableLineUsed(line: *types.LineHdrObject) isize {
    return if (line.FLink == null) 0 else line.Used;
}

fn buildEvents(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    line: *types.LineHdrObject,
) ![]Event {
    var events = std.ArrayListUnmanaged(Event){};
    const used = searchableLineUsed(line);
    const final_col = used + 1;
    var col: isize = 1;
    while (col <= final_col) : (col += 1) {
        var positional: types.AcceptSet = .{};
        if (col == 1) {
            patparse.setAdd(&positional, types.PatternBegLine);
        }
        if (col > used) {
            patparse.setAdd(&positional, types.PatternEndLine);
        }
        if (col == frame.MarginLeft) {
            patparse.setAdd(&positional, types.PatternLeftMargin);
        }
        if (col == frame.MarginRight) {
            patparse.setAdd(&positional, types.PatternRightMargin);
        }
        if (frame.Dot != null and col == frame.Dot.?.Col) {
            patparse.setAdd(&positional, types.PatternDotColumn);
        }
        for (0..types.MaxMarkNumber + 1) |mark_no| {
            if (frame.Marks[mark_no]) |mark| {
                if (mark.Line == line and mark.Col == col) {
                    patparse.setAdd(&positional, @intCast(mark_no + types.PatternMarksStart));
                }
            }
        }

        if (!positional.isEmpty()) {
            try events.append(allocator, .{
                .kind = .positional,
                .accept = positional,
                .before_col = col,
                .after_col = col,
            });
        }
        if (col <= used) {
            try events.append(allocator, .{
                .kind = .char,
                .ch = line.Str.?.Get(col),
                .before_col = col,
                .after_col = col + 1,
            });
        }
    }
    try events.append(allocator, .{
        .kind = .char,
        .ch = ' ',
        .before_col = final_col,
        .after_col = final_col,
    });
    return events.toOwnedSlice(allocator);
}

fn startCursorsForColumn(events: []const Event, column: isize, skip_initial_positional: bool) StartCursorList {
    var result: StartCursorList = .{};
    for (events, 0..) |event, index| {
        if (event.before_col < column) continue;
        if (event.before_col > column) break;
        if (skip_initial_positional and event.kind == .positional) continue;
        result.items[result.len] = .{
            .event_index = index,
            .column = column,
        };
        result.len += 1;
    }
    return result;
}

const Matcher = struct {
    allocator: std.mem.Allocator,
    events: []const Event,

    fn matchNode(self: *Matcher, node: *const Node, cursor: Cursor) MatchError![]Cursor {
        return switch (node.*) {
            .token => |token| try self.matchToken(token, cursor),
            .seq => |nodes| try self.matchSequence(nodes, cursor),
            .alt => |nodes| try self.matchAlternatives(nodes, cursor),
            .repeat => |repeat_node| try self.matchRepeatNode(repeat_node, cursor),
        };
    }

    fn matchToken(self: *Matcher, token: Token, cursor: Cursor) MatchError![]Cursor {
        if (cursor.event_index >= self.events.len) {
            return &.{};
        }
        const event = self.events[cursor.event_index];
        if (event.kind != token.kind) {
            return &.{};
        }
        const ok = switch (event.kind) {
            .char => token.accept.Bit(event.ch) == 1,
            .positional => acceptSetIntersects(&token.accept, &event.accept),
        };
        if (!ok) {
            return &.{};
        }
        return try self.allocator.dupe(Cursor, &.{.{
            .event_index = cursor.event_index + 1,
            .column = event.after_col,
        }});
    }

    fn matchSequence(self: *Matcher, nodes: []const *Node, cursor: Cursor) MatchError![]Cursor {
        var cursors = try self.allocator.dupe(Cursor, &.{cursor});
        for (nodes) |child| {
            var next = std.ArrayListUnmanaged(Cursor){};
            for (cursors) |current| {
                const results = try self.matchNode(child, current);
                for (results) |result| {
                    try appendCursorUnique(&next, self.allocator, result);
                }
            }
            cursors = try next.toOwnedSlice(self.allocator);
            if (cursors.len == 0) {
                return &.{};
            }
        }
        return cursors;
    }

    fn matchAlternatives(self: *Matcher, nodes: []const *Node, cursor: Cursor) MatchError![]Cursor {
        var results = std.ArrayListUnmanaged(Cursor){};
        for (nodes) |child| {
            const child_results = try self.matchNode(child, cursor);
            for (child_results) |result| {
                try appendCursorUnique(&results, self.allocator, result);
            }
        }
        return results.toOwnedSlice(self.allocator);
    }

    fn matchRepeatNode(self: *Matcher, repeat_node: RepeatNode, cursor: Cursor) MatchError![]Cursor {
        var results = std.ArrayListUnmanaged(Cursor){};
        try self.matchRepeatRecursive(repeat_node, cursor, 0, &results);
        return results.toOwnedSlice(self.allocator);
    }

    fn matchRepeatRecursive(
        self: *Matcher,
        repeat_node: RepeatNode,
        cursor: Cursor,
        count: usize,
        out: *std.ArrayListUnmanaged(Cursor),
    ) MatchError!void {
        if (count >= repeat_node.min) {
            try appendCursorUnique(out, self.allocator, cursor);
        }
        if (repeat_node.max) |max_count| {
            if (count >= max_count) {
                return;
            }
        }

        const child_results = try self.matchNode(repeat_node.child, cursor);
        for (child_results) |next_cursor| {
            if (next_cursor.event_index == cursor.event_index and next_cursor.column == cursor.column) {
                if (count + 1 >= repeat_node.min) {
                    try appendCursorUnique(out, self.allocator, next_cursor);
                }
                continue;
            }
            try self.matchRepeatRecursive(repeat_node, next_cursor, count + 1, out);
        }
    }
};

fn betterMatch(candidate: MatchRange, current_best: MatchRange) bool {
    if (candidate.total_end.column != current_best.total_end.column) {
        return candidate.total_end.column > current_best.total_end.column;
    }
    return candidate.total_end.event_index > current_best.total_end.event_index;
}

fn matchCompiledPattern(
    allocator: std.mem.Allocator,
    pattern: CompiledPattern,
    events: []const Event,
    start_cursor: Cursor,
) !?MatchRange {
    var matcher = Matcher{
        .allocator = allocator,
        .events = events,
    };

    const prefix_results = try matcher.matchNode(pattern.prefix, start_cursor);
    var best: ?MatchRange = null;

    for (prefix_results) |prefix_cursor| {
        const middle_start = prefix_cursor.column;
        const middle_results = try matcher.matchNode(pattern.middle, prefix_cursor);
        for (middle_results) |middle_cursor| {
            const suffix_results = try matcher.matchNode(pattern.suffix, middle_cursor);
            for (suffix_results) |suffix_cursor| {
                const candidate = MatchRange{
                    .start_col = middle_start,
                    .finish_col = middle_cursor.column,
                    .total_end = suffix_cursor,
                };
                if (best == null or betterMatch(candidate, best.?)) {
                    best = candidate;
                }
            }
        }
    }
    return best;
}

fn patternSource(definition: types.PatternDefType) []const u8 {
    return definition.Strng.?.Slice(1, definition.Length);
}

pub fn PatternRecognize(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    dfa_table_pointer: *types.DFATableObject,
    line: *types.LineHdrObject,
    start_col: isize,
    mark_flag: *bool,
    start_pos: *isize,
    finish_pos: *isize,
) !bool {
    if (dfa_table_pointer.Definition.Strng == null or dfa_table_pointer.Definition.Length == 0) {
        return false;
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp = arena.allocator();

    var parser = Parser{
        .allocator = temp,
        .source = patternSource(dfa_table_pointer.Definition),
    };
    const compiled = parser.parse() catch return false;
    const events = try buildEvents(temp, frame, line);
    const last_col = searchableLineUsed(line) + 1;
    var column = @min(start_col, last_col);

    while (column <= last_col) : (column += 1) {
        const starts = startCursorsForColumn(events, column, column == start_col and mark_flag.*);
        var best: ?MatchRange = null;
        var idx: usize = 0;
        while (idx < starts.len) : (idx += 1) {
            if (try matchCompiledPattern(temp, compiled, events, starts.items[idx])) |match| {
                if (best == null or betterMatch(match, best.?)) {
                    best = match;
                }
            }
        }
        if (best) |match| {
            start_pos.* = match.start_col;
            finish_pos.* = match.finish_col;
            mark_flag.* = false;
            return true;
        }
    }

    mark_flag.* = false;
    return false;
}

test "pattern recognize matches literals classes and anchored contexts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{
        "Hello WORLD",
        "abc",
        "foo@bar.com",
    });

    var dfa: types.DFATableObject = .{
        .Definition = .{
            .Strng = try @import("str_object.zig").NewStrObjectFrom(allocator, "'world'"),
            .Length = 7,
        },
    };
    var mark_flag = false;
    var start_pos: isize = 0;
    var finish_pos: isize = 0;
    try std.testing.expect(try PatternRecognize(allocator, fixture.frame, &dfa, fixture.content_lines[0], 1, &mark_flag, &start_pos, &finish_pos));
    try std.testing.expectEqual(@as(isize, 7), start_pos);
    try std.testing.expectEqual(@as(isize, 12), finish_pos);

    dfa.Definition = .{
        .Strng = try @import("str_object.zig").NewStrObjectFrom(allocator, "<+a>"),
        .Length = 4,
    };
    try std.testing.expect(try PatternRecognize(allocator, fixture.frame, &dfa, fixture.content_lines[1], 1, &mark_flag, &start_pos, &finish_pos));
    try std.testing.expectEqual(@as(isize, 1), start_pos);
    try std.testing.expectEqual(@as(isize, 4), finish_pos);

    dfa.Definition = .{
        .Strng = try @import("str_object.zig").NewStrObjectFrom(allocator, "'a','b','c'"),
        .Length = 11,
    };
    try std.testing.expect(try PatternRecognize(allocator, fixture.frame, &dfa, fixture.content_lines[1], 1, &mark_flag, &start_pos, &finish_pos));
    try std.testing.expectEqual(@as(isize, 2), start_pos);
    try std.testing.expectEqual(@as(isize, 3), finish_pos);

    const email_pattern = "+a'@'+a'.'+a";
    dfa.Definition = .{
        .Strng = try @import("str_object.zig").NewStrObjectFrom(allocator, email_pattern),
        .Length = email_pattern.len,
    };
    try std.testing.expect(try PatternRecognize(allocator, fixture.frame, &dfa, fixture.content_lines[2], 1, &mark_flag, &start_pos, &finish_pos));
    try std.testing.expectEqual(@as(isize, 1), start_pos);
    try std.testing.expectEqual(@as(isize, 12), finish_pos);
}

test "pattern recognize handles positional marks and initial mark flag skipping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{"abc"});
    try @import("mark.zig").MarkCreate(allocator, fixture.content_lines[0], 1, &fixture.frame.Marks[1]);
    fixture.frame.MarginLeft = 1;

    var dfa: types.DFATableObject = .{
        .Definition = .{
            .Strng = try @import("str_object.zig").NewStrObjectFrom(allocator, "@1"),
            .Length = 2,
        },
    };
    var mark_flag = false;
    var start_pos: isize = 0;
    var finish_pos: isize = 0;
    try std.testing.expect(try PatternRecognize(allocator, fixture.frame, &dfa, fixture.content_lines[0], 1, &mark_flag, &start_pos, &finish_pos));
    try std.testing.expectEqual(@as(isize, 1), start_pos);
    try std.testing.expectEqual(@as(isize, 1), finish_pos);

    dfa.Definition = .{
        .Strng = try @import("str_object.zig").NewStrObjectFrom(allocator, "'a'"),
        .Length = 3,
    };
    mark_flag = true;
    try std.testing.expect(try PatternRecognize(allocator, fixture.frame, &dfa, fixture.content_lines[0], 1, &mark_flag, &start_pos, &finish_pos));
    try std.testing.expectEqual(@as(isize, 1), start_pos);
    try std.testing.expectEqual(@as(isize, 2), finish_pos);
}

test "pattern recognize keeps the longest same-column repeat match" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try @import("line.zig").createContentFrame(allocator, &[_][]const u8{"1234def"});
    const pattern = "[,3]N";
    var dfa: types.DFATableObject = .{
        .Definition = .{
            .Strng = try @import("str_object.zig").NewStrObjectFrom(allocator, pattern),
            .Length = pattern.len,
        },
    };
    var mark_flag = false;
    var start_pos: isize = 0;
    var finish_pos: isize = 0;

    try std.testing.expect(try PatternRecognize(
        allocator,
        fixture.frame,
        &dfa,
        fixture.content_lines[0],
        1,
        &mark_flag,
        &start_pos,
        &finish_pos,
    ));
    try std.testing.expectEqual(@as(isize, 1), start_pos);
    try std.testing.expectEqual(@as(isize, 4), finish_pos);
}
