const std = @import("std");
const chars = @import("chars.zig");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const text = @import("text.zig");
const types = @import("types.zig");

fn moveMarkInPlace(
    allocator: std.mem.Allocator,
    mark: *types.MarkObject,
    line: *types.LineHdrObject,
    col: isize,
) !void {
    var slot: ?*types.MarkObject = mark;
    try mark_ops.markCreate(allocator, line, col, &slot);
}

fn moveDot(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    line: *types.LineHdrObject,
    col: isize,
) !void {
    try mark_ops.markCreate(allocator, line, col, &frame.dot);
}

pub fn currentWord(
    allocator: std.mem.Allocator,
    dot: *types.MarkObject,
) !bool {
    if (dot.Line.used + 2 < dot.Col) {
        if (dot.Line.f_link == null or dot.Line.f_link.?.used == 0) {
            return false;
        }
        dot.Col = dot.Line.used;
    } else if (dot.Line.used < dot.Col) {
        dot.Col = dot.Line.used;
    }

    if (dot.Col == 0) return false;

    while (dot.Col > 1 and chars.chIsWordElement(0, dot.Line.str.?.get(dot.Col))) {
        dot.Col -= 1;
    }
    if (chars.chIsWordElement(0, dot.Line.str.?.get(dot.Col))) {
        if (dot.Line.b_link == null or dot.Line.b_link.?.used == 0) {
            return false;
        }
        try moveMarkInPlace(allocator, dot, dot.Line.b_link.?, dot.Line.b_link.?.used);
    }

    var element: usize = 0;
    while (!chars.chIsWordElement(element, dot.Line.str.?.get(dot.Col))) {
        element += 1;
    }
    while (dot.Col > 1 and chars.chIsWordElement(element, dot.Line.str.?.get(dot.Col))) {
        dot.Col -= 1;
    }
    if (!chars.chIsWordElement(element, dot.Line.str.?.get(dot.Col))) {
        dot.Col += 1;
    }
    return true;
}

pub fn nextWord(
    allocator: std.mem.Allocator,
    dot: *types.MarkObject,
) !bool {
    if (dot.Col > dot.Line.used) {
        if (dot.Line.used == 0) return false;
        dot.Col = dot.Line.used;
    }

    var element: usize = 0;
    while (!chars.chIsWordElement(element, dot.Line.str.?.get(dot.Col))) {
        element += 1;
    }
    while (dot.Col < dot.Line.used and chars.chIsWordElement(element, dot.Line.str.?.get(dot.Col))) {
        dot.Col += 1;
    }
    if (chars.chIsWordElement(element, dot.Line.str.?.get(dot.Col))) {
        if (dot.Line.f_link == null or dot.Line.f_link.?.used == 0) {
            return false;
        }
        try moveMarkInPlace(allocator, dot, dot.Line.f_link.?, 1);
    }
    while (chars.chIsWordElement(0, dot.Line.str.?.get(dot.Col))) {
        dot.Col += 1;
    }
    return true;
}

pub fn previousWord(
    allocator: std.mem.Allocator,
    dot: *types.MarkObject,
) !bool {
    var element: usize = 0;
    while (!chars.chIsWordElement(element, dot.Line.str.?.get(dot.Col))) {
        element += 1;
    }
    while (dot.Col > 1 and chars.chIsWordElement(element, dot.Line.str.?.get(dot.Col))) {
        dot.Col -= 1;
    }
    if (chars.chIsWordElement(element, dot.Line.str.?.get(dot.Col))) {
        if (dot.Line.b_link == null or dot.Line.b_link.?.used == 0) {
            return false;
        }
        try moveMarkInPlace(allocator, dot, dot.Line.b_link.?, dot.Line.b_link.?.used);
    }
    return currentWord(allocator, dot);
}

pub fn newwordAdvanceWord(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var new_dot: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &new_dot);
    defer mark_ops.markDestroy(allocator, &new_dot);

    var rept_mut = rept;
    var count_mut = count;

    if (rept_mut == .LeadParamMarker) {
        const index: usize = @intCast(count_mut);
        try moveMarkInPlace(allocator, new_dot.?, frame.marks[index].?.Line, frame.marks[index].?.Col);
        rept_mut = .LeadParamNInt;
        count_mut = 0;
    }
    if (rept_mut == .LeadParamPInt and count_mut == 0) {
        rept_mut = .LeadParamNInt;
    }

    switch (rept_mut) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            while (count_mut > 0) : (count_mut -= 1) {
                if (!try nextWord(allocator, new_dot.?)) return false;
            }
            try moveDot(allocator, frame, new_dot.?.Line, new_dot.?.Col);
        },
        .LeadParamMinus, .LeadParamNInt => {
            count_mut = -count_mut;
            if (!try currentWord(allocator, new_dot.?)) return false;
            while (count_mut > 0) : (count_mut -= 1) {
                if (!try previousWord(allocator, new_dot.?)) return false;
            }
            try moveDot(allocator, frame, new_dot.?.Line, new_dot.?.Col);
        },
        .LeadParamPIndef => {
            if (new_dot.?.Line.used == 0) return false;
            if (new_dot.?.Col > new_dot.?.Line.used + 2) {
                if (new_dot.?.Line.f_link == null or new_dot.?.Line.f_link.?.used == 0) return false;
                new_dot.?.Col = new_dot.?.Line.used;
            }
            while (try nextWord(allocator, new_dot.?)) {
                try moveDot(allocator, frame, new_dot.?.Line, new_dot.?.Col);
            }
            if (new_dot.?.Line.used + 2 > types.max_str_len_p1) {
                try moveDot(allocator, frame, new_dot.?.Line, types.max_str_len_p1);
            } else {
                try moveDot(allocator, frame, new_dot.?.Line, new_dot.?.Line.used + 2);
            }
        },
        .LeadParamNIndef => {
            if (!try currentWord(allocator, new_dot.?)) return false;
            try moveDot(allocator, frame, new_dot.?.Line, new_dot.?.Col);
            while (try previousWord(allocator, new_dot.?)) {
                try moveDot(allocator, frame, new_dot.?.Line, new_dot.?.Col);
            }
        },
        else => return false,
    }
    return true;
}

pub fn newwordDeleteWord(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    frame_oops: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var old_pos: ?*types.MarkObject = null;
    var here: ?*types.MarkObject = null;
    var other_mark: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &old_pos);
    defer mark_ops.markDestroy(allocator, &old_pos);
    defer mark_ops.markDestroy(allocator, &here);
    defer mark_ops.markDestroy(allocator, &other_mark);

    if (!try newwordAdvanceWord(allocator, frame, .LeadParamPInt, 0)) return false;
    try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &here);
    if (!try newwordAdvanceWord(allocator, frame, rept, count)) {
        try moveDot(allocator, frame, old_pos.?.Line, old_pos.?.Col);
        return false;
    }

    const old_dot_col = frame.dot.?.Col;
    try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &other_mark);
    const line_nr = line_ops.lineToNumber(other_mark.?.Line);
    const new_line_nr = line_ops.lineToNumber(here.?.Line);
    if (line_nr > new_line_nr or (line_nr == new_line_nr and other_mark.?.Col > here.?.Col)) {
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

pub fn currentParagraph(
    allocator: std.mem.Allocator,
    dot: *types.MarkObject,
) !bool {
    var new_line = dot.Line;
    var pos: isize = 0;
    if (dot.Col < dot.Line.used) {
        pos = dot.Col;
        while (pos > 1 and chars.chIsWordElement(0, new_line.str.?.get(pos))) {
            pos -= 1;
        }
        if (chars.chIsWordElement(0, new_line.str.?.get(pos))) {
            if (new_line.b_link == null) return false;
            new_line = new_line.b_link.?;
        }
    }
    while (new_line.b_link != null and new_line.used == 0) {
        new_line = new_line.b_link.?;
    }
    if (new_line.used == 0) return false;
    while (new_line.b_link != null and new_line.used != 0) {
        new_line = new_line.b_link.?;
    }
    if (new_line.used == 0) {
        new_line = new_line.f_link.?;
    }
    pos = 1;
    while (chars.chIsWordElement(0, new_line.str.?.get(pos))) {
        pos += 1;
    }
    try moveMarkInPlace(allocator, dot, new_line, pos);
    return true;
}

pub fn nextParagraph(
    allocator: std.mem.Allocator,
    dot: *types.MarkObject,
) !bool {
    var new_line = dot.Line;
    var pos: isize = 0;
    if (dot.Col < dot.Line.used) {
        pos = dot.Col;
        while (pos > 1 and chars.chIsWordElement(0, new_line.str.?.get(pos))) {
            pos -= 1;
        }
        if (chars.chIsWordElement(0, new_line.str.?.get(pos))) {
            if (new_line.b_link == null) {
                dot.Col = 1;
                while (chars.chIsWordElement(0, new_line.str.?.get(dot.Col))) {
                    dot.Col += 1;
                }
                return true;
            }
            new_line = new_line.b_link.?;
        }
    }
    while (new_line.f_link != null and new_line.used != 0) {
        new_line = new_line.f_link.?;
    }
    if (new_line.used != 0) return false;
    while (new_line.f_link != null and new_line.used == 0) {
        new_line = new_line.f_link.?;
    }
    if (new_line.used == 0) return false;
    pos = 1;
    while (chars.chIsWordElement(0, new_line.str.?.get(pos))) {
        pos += 1;
    }
    try moveMarkInPlace(allocator, dot, new_line, pos);
    return true;
}

pub fn newwordAdvanceParagraph(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var new_dot: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &new_dot);
    defer mark_ops.markDestroy(allocator, &new_dot);

    var rept_mut = rept;
    var count_mut = count;
    if (rept_mut == .LeadParamMarker) {
        const index: usize = @intCast(count_mut);
        try moveMarkInPlace(allocator, new_dot.?, frame.marks[index].?.Line, frame.marks[index].?.Col);
        rept_mut = .LeadParamNInt;
        count_mut = 0;
    }
    if (rept_mut == .LeadParamPInt and count_mut == 0) {
        rept_mut = .LeadParamNInt;
    }

    switch (rept_mut) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            while (count_mut > 0) : (count_mut -= 1) {
                if (!try nextParagraph(allocator, new_dot.?)) return false;
            }
            try moveDot(allocator, frame, new_dot.?.Line, new_dot.?.Col);
        },
        .LeadParamMinus, .LeadParamNInt => {
            count_mut = -count_mut;
            if (!try currentParagraph(allocator, new_dot.?)) return false;
            while (count_mut > 0) : (count_mut -= 1) {
                if (new_dot.?.Line.b_link == null) return false;
                try moveMarkInPlace(allocator, new_dot.?, new_dot.?.Line.b_link.?, 1);
                if (!try currentParagraph(allocator, new_dot.?)) return false;
            }
            try moveDot(allocator, frame, new_dot.?.Line, new_dot.?.Col);
        },
        .LeadParamPIndef => try moveDot(allocator, frame, frame.last_group.?.last_line.?, frame.margin_left),
        .LeadParamNIndef => {
            var new_line = new_dot.?.Line;
            while (new_line.b_link != null and new_line.used == 0) {
                new_line = new_line.b_link.?;
            }
            if (new_line.used == 0) return false;
            new_line = frame.first_group.?.first_line.?;
            while (new_line.used == 0) {
                new_line = new_line.f_link.?;
            }
            var pos: isize = 1;
            while (chars.chIsWordElement(0, new_line.str.?.get(pos))) {
                pos += 1;
            }
            try moveDot(allocator, frame, new_line, pos);
        },
        else => {},
    }
    return true;
}

pub fn newwordDeleteParagraph(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    frame_oops: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    var old_pos: ?*types.MarkObject = null;
    var here: ?*types.MarkObject = null;
    var other_mark: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, frame.dot.?.Line, frame.dot.?.Col, &old_pos);
    defer mark_ops.markDestroy(allocator, &old_pos);
    defer mark_ops.markDestroy(allocator, &here);
    defer mark_ops.markDestroy(allocator, &other_mark);

    if (!try newwordAdvanceParagraph(allocator, frame, .LeadParamPInt, 0)) return false;
    try mark_ops.markCreate(allocator, frame.dot.?.Line, 1, &here);
    if (!try newwordAdvanceParagraph(allocator, frame, rept, count)) {
        try moveDot(allocator, frame, old_pos.?.Line, old_pos.?.Col);
        return false;
    }
    try mark_ops.markCreate(allocator, frame.dot.?.Line, 1, &other_mark);
    const line_nr = line_ops.lineToNumber(other_mark.?.Line);
    const new_line_nr = line_ops.lineToNumber(here.?.Line);
    if (line_nr > new_line_nr) {
        const another_mark = here;
        here = other_mark;
        other_mark = another_mark;
    }

    if (frame != frame_oops) {
        if (frame_oops.span == null) return false;
        try mark_ops.markCreate(allocator, frame_oops.last_group.?.last_line.?, 1, &frame_oops.span.?.mark_two);
        return text.textMove(allocator, false, 1, other_mark.?, here.?, frame_oops.span.?.mark_two.?, &frame_oops.marks[types.mark_equals], &frame_oops.dot);
    }
    return text.textRemove(allocator, other_mark.?, here.?);
}

fn buildWordFrame(
    allocator: std.mem.Allocator,
    contents: []const []const u8,
) !line_ops.FrameFixture {
    return line_ops.createContentFrame(allocator, contents);
}

test "current next and previous word follow paragraph boundaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try buildWordFrame(allocator, &[_][]const u8{"hello world foo"});
    var dot: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 8, &dot);
    try std.testing.expect(try currentWord(allocator, dot.?));
    try std.testing.expectEqual(@as(isize, 7), dot.?.Col);
    try std.testing.expect(try nextWord(allocator, dot.?));
    try std.testing.expectEqual(@as(isize, 13), dot.?.Col);
    try std.testing.expect(try previousWord(allocator, dot.?));
    try std.testing.expectEqual(@as(isize, 7), dot.?.Col);
}

test "newword advance word supports forward backward and marker movement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try buildWordFrame(allocator, &[_][]const u8{"hello world foo"});
    try std.testing.expect(try newwordAdvanceWord(allocator, fixture.frame, .LeadParamNone, 1));
    try std.testing.expectEqual(@as(isize, 7), fixture.frame.dot.?.Col);

    try moveDot(allocator, fixture.frame, fixture.content_lines[0], 9);
    try std.testing.expect(try newwordAdvanceWord(allocator, fixture.frame, .LeadParamNInt, -1));
    try std.testing.expectEqual(@as(isize, 1), fixture.frame.dot.?.Col);

    try mark_ops.markCreate(allocator, fixture.content_lines[0], 14, &fixture.frame.marks[1]);
    try std.testing.expect(try newwordAdvanceWord(allocator, fixture.frame, .LeadParamMarker, 1));
    try std.testing.expectEqual(@as(isize, 13), fixture.frame.dot.?.Col);
}

test "newword advance paragraph finds current next and first paragraphs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const fixture = try buildWordFrame(allocator, &[_][]const u8{ "hello world", "", "foo bar" });
    try moveDot(allocator, fixture.frame, fixture.content_lines[0], 5);
    try std.testing.expect(try newwordAdvanceParagraph(allocator, fixture.frame, .LeadParamPInt, 0));
    try std.testing.expect(fixture.frame.dot.?.Line == fixture.content_lines[0]);
    try std.testing.expectEqual(@as(isize, 1), fixture.frame.dot.?.Col);

    try std.testing.expect(try newwordAdvanceParagraph(allocator, fixture.frame, .LeadParamNone, 1));
    try std.testing.expect(fixture.frame.dot.?.Line == fixture.content_lines[2]);

    try std.testing.expect(try newwordAdvanceParagraph(allocator, fixture.frame, .LeadParamNIndef, 0));
    try std.testing.expect(fixture.frame.dot.?.Line == fixture.content_lines[0]);
}

test "newword delete word and paragraph remove text ranges" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const word_fixture = try buildWordFrame(allocator, &[_][]const u8{"hello world"});
    try moveDot(allocator, word_fixture.frame, word_fixture.content_lines[0], 1);
    try std.testing.expect(try newwordDeleteWord(allocator, word_fixture.frame, word_fixture.frame, .LeadParamNone, 1));
    try std.testing.expectEqualStrings("world", line_ops.getLineContent(word_fixture.content_lines[0]));

    const para_fixture = try buildWordFrame(allocator, &[_][]const u8{ "hello world", "", "foo bar" });
    try moveDot(allocator, para_fixture.frame, para_fixture.content_lines[0], 1);
    try std.testing.expect(try newwordDeleteParagraph(allocator, para_fixture.frame, para_fixture.frame, .LeadParamNone, 1));
}
