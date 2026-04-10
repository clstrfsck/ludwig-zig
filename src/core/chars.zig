const std = @import("std");
const str_object = @import("str_object.zig");
const types = @import("types.zig");

pub fn ChIsPrintable(ch: u8) bool {
    return ch >= 32 and ch <= 126;
}

pub fn ChIsSpace(ch: u8) bool {
    return std.ascii.isWhitespace(ch);
}

pub fn ChIsLetter(ch: u8) bool {
    return std.ascii.isAlphabetic(ch);
}

pub fn ChIsLower(ch: u8) bool {
    return std.ascii.isLower(ch);
}
pub fn ChIsNumeric(ch: u8) bool {
    return std.ascii.isDigit(ch);
}

pub fn ChIsPunctuation(ch: u8) bool {
    return ChIsPrintable(ch) and !ChIsLetter(ch) and !ChIsNumeric(ch) and !ChIsSpace(ch);
}

pub fn ChIsWordElement(set: usize, ch: u8) bool {
    return switch (set) {
        0 => ChIsSpace(ch),
        1 => ChIsPrintable(ch) and !ChIsSpace(ch),
        else => false,
    };
}

pub fn ChKeyToUpper(key: isize) isize {
    if (key >= 0 and key <= types.MaxSetRange) {
        return @intCast(ChToUpper(@intCast(key)));
    }
    return key;
}

pub fn ChToUpper(ch: u8) u8 {
    return std.ascii.toUpper(ch);
}

pub fn ChToLower(ch: u8) u8 {
    return std.ascii.toLower(ch);
}

pub fn ChCompareStr(
    target: *const str_object.StrObject,
    st1: isize,
    len1: isize,
    text: *const str_object.StrObject,
    st2: isize,
    len2: isize,
    exactcase: bool,
    nch_ident: *isize,
) isize {
    var i: isize = 0;
    if (exactcase) {
        while (i < len1 and i < len2) : (i += 1) {
            if (target.Get(st1 + i) != text.Get(st2 + i)) break;
        }
    } else {
        while (i < len1 and i < len2) : (i += 1) {
            if (target.Get(st1 + i) != ChToUpper(text.Get(st2 + i))) break;
        }
    }
    nch_ident.* = i;

    if (i < len1 and i < len2) {
        const ch1 = target.Get(st1 + i);
        const ch2 = if (exactcase) text.Get(st2 + i) else ChToUpper(text.Get(st2 + i));
        return if (ch1 < ch2) -1 else if (ch1 > ch2) 1 else 0;
    }
    return if (len1 < len2) -1 else if (len1 > len2) 1 else 0;
}

pub fn ChReverseStr(
    src: *const str_object.StrObject,
    dst: *str_object.StrObject,
    len: isize,
) void {
    const half = @divTrunc(len + 1, 2);
    if (half > 0) {
        var i: isize = 0;
        while (i < half) : (i += 1) {
            const ch = src.Get(i + 1);
            dst.Set(i + 1, src.Get(len - i));
            dst.Set(len - i, ch);
        }
    }
}

pub fn ChSearchStr(
    allocator: std.mem.Allocator,
    target: *const str_object.StrObject,
    st1: isize,
    len1: isize,
    text: *const str_object.StrObject,
    st2: isize,
    len2: isize,
    exactcase: bool,
    backwards: bool,
    found_loc: *isize,
) !bool {
    const s = try str_object.NewStrObjectCopy(allocator, text, st2, len2, len2);
    defer s.destroy();

    if (backwards) {
        ChReverseStr(s, s, len2);
        found_loc.* = len2;
    } else {
        found_loc.* = 0;
    }

    if (!exactcase) {
        s.ApplyN(ChToUpper, len2, 1);
    }

    var i: isize = 1;
    while (i <= len2 - len1 + 1) : (i += 1) {
        if (s.EqualAt(target, len1, i, st1)) {
            found_loc.* = if (backwards) len2 - (i + len1) + 1 else i - 1;
            return true;
        }
    }
    return false;
}

test "character helpers match ASCII word and case rules" {
    try std.testing.expect(ChIsPrintable('A'));
    try std.testing.expect(ChIsSpace(' '));
    try std.testing.expect(ChIsLetter('z'));
    try std.testing.expect(ChIsNumeric('7'));
    try std.testing.expect(ChIsPunctuation('!'));
    try std.testing.expect(ChIsWordElement(0, ' '));
    try std.testing.expect(ChIsWordElement(1, 'A'));
    try std.testing.expectEqual(@as(u8, 'A'), ChToUpper('a'));
    try std.testing.expectEqual(@as(u8, 'z'), ChToLower('Z'));
    try std.testing.expectEqual(@as(isize, 'Q'), ChKeyToUpper('q'));
}

test "character string compare matches exact and folded behavior" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const hello = try str_object.NewStrObjectFrom(allocator, "HELLO");
    const hello_lower = try str_object.NewStrObjectFrom(allocator, "hello");
    const world = try str_object.NewStrObjectFrom(allocator, "WORLD");
    var nch_ident: isize = 0;

    try std.testing.expectEqual(@as(isize, 0), ChCompareStr(hello, 1, 5, hello, 1, 5, true, &nch_ident));
    try std.testing.expectEqual(@as(isize, 5), nch_ident);
    try std.testing.expectEqual(@as(isize, 0), ChCompareStr(hello, 1, 5, hello_lower, 1, 5, false, &nch_ident));
    try std.testing.expectEqual(@as(isize, -1), ChCompareStr(hello, 1, 5, world, 1, 5, false, &nch_ident));
}

test "character reverse and search utilities operate on StrObject" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const hello = try str_object.NewStrObjectFrom(allocator, "HELLO WORLD TEST");
    const world = try str_object.NewStrObjectFrom(allocator, "WORLD");
    const reverse_target = try str_object.NewStrObjectFrom(allocator, "DLROW");
    const dst = try str_object.NewBlankStrObject(allocator, 5);
    var found_loc: isize = 0;

    ChReverseStr(world, dst, 5);
    try std.testing.expectEqualStrings("DLROW", dst.Slice(1, 5));
    try std.testing.expect(try ChSearchStr(allocator, world, 1, 5, hello, 1, 16, true, false, &found_loc));
    try std.testing.expectEqual(@as(isize, 6), found_loc);
    try std.testing.expect(try ChSearchStr(allocator, reverse_target, 1, 5, hello, 1, 16, true, true, &found_loc));
    try std.testing.expectEqual(@as(isize, 6), found_loc);
}
