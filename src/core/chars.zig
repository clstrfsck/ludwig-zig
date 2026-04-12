const std = @import("std");
const str_object = @import("str_object.zig");
const types = @import("types.zig");

pub fn chIsPrintable(ch: u8) bool {
    return ch >= 32 and ch <= 126;
}

pub fn chIsSpace(ch: u8) bool {
    return std.ascii.isWhitespace(ch);
}

pub fn chIsLetter(ch: u8) bool {
    return std.ascii.isAlphabetic(ch);
}

pub fn chIsLower(ch: u8) bool {
    return std.ascii.isLower(ch);
}
pub fn chIsNumeric(ch: u8) bool {
    return std.ascii.isDigit(ch);
}

pub fn chIsPunctuation(ch: u8) bool {
    return chIsPrintable(ch) and !chIsLetter(ch) and !chIsNumeric(ch) and !chIsSpace(ch);
}

pub fn chIsWordElement(set: usize, ch: u8) bool {
    return switch (set) {
        0 => chIsSpace(ch),
        1 => chIsPrintable(ch) and !chIsSpace(ch),
        else => false,
    };
}

pub fn chKeyToUpper(key: isize) isize {
    if (key >= 0 and key <= types.max_set_range) {
        return @intCast(chToUpper(@intCast(key)));
    }
    return key;
}

pub fn chToUpper(ch: u8) u8 {
    return std.ascii.toUpper(ch);
}

pub fn chToLower(ch: u8) u8 {
    return std.ascii.toLower(ch);
}

pub fn chCompareStr(
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
            if (target.get(st1 + i) != text.get(st2 + i)) break;
        }
    } else {
        while (i < len1 and i < len2) : (i += 1) {
            if (target.get(st1 + i) != chToUpper(text.get(st2 + i))) break;
        }
    }
    nch_ident.* = i;

    if (i < len1 and i < len2) {
        const ch1 = target.get(st1 + i);
        const ch2 = if (exactcase) text.get(st2 + i) else chToUpper(text.get(st2 + i));
        return if (ch1 < ch2) -1 else if (ch1 > ch2) 1 else 0;
    }
    return if (len1 < len2) -1 else if (len1 > len2) 1 else 0;
}

pub fn chReverseStr(
    src: *const str_object.StrObject,
    dst: *str_object.StrObject,
    len: isize,
) void {
    const half = @divTrunc(len + 1, 2);
    if (half > 0) {
        var i: isize = 0;
        while (i < half) : (i += 1) {
            const ch = src.get(i + 1);
            dst.set(i + 1, src.get(len - i));
            dst.set(len - i, ch);
        }
    }
}

pub fn chSearchStr(
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
    const s = try str_object.newStrObjectCopy(allocator, text, st2, len2, len2);
    defer s.destroy();

    if (backwards) {
        chReverseStr(s, s, len2);
        found_loc.* = len2;
    } else {
        found_loc.* = 0;
    }

    if (!exactcase) {
        s.applyN(chToUpper, len2, 1);
    }

    var i: isize = 1;
    while (i <= len2 - len1 + 1) : (i += 1) {
        if (s.equalAt(target, len1, i, st1)) {
            found_loc.* = if (backwards) len2 - (i + len1) + 1 else i - 1;
            return true;
        }
    }
    return false;
}

test "character helpers match ASCII word and case rules" {
    try std.testing.expect(chIsPrintable('A'));
    try std.testing.expect(chIsSpace(' '));
    try std.testing.expect(chIsLetter('z'));
    try std.testing.expect(chIsNumeric('7'));
    try std.testing.expect(chIsPunctuation('!'));
    try std.testing.expect(chIsWordElement(0, ' '));
    try std.testing.expect(chIsWordElement(1, 'A'));
    try std.testing.expectEqual(@as(u8, 'A'), chToUpper('a'));
    try std.testing.expectEqual(@as(u8, 'z'), chToLower('Z'));
    try std.testing.expectEqual(@as(isize, 'Q'), chKeyToUpper('q'));
}

test "character string compare matches exact and folded behavior" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const hello = try str_object.newStrObjectFrom(allocator, "HELLO");
    const hello_lower = try str_object.newStrObjectFrom(allocator, "hello");
    const world = try str_object.newStrObjectFrom(allocator, "WORLD");
    var nch_ident: isize = 0;

    try std.testing.expectEqual(@as(isize, 0), chCompareStr(hello, 1, 5, hello, 1, 5, true, &nch_ident));
    try std.testing.expectEqual(@as(isize, 5), nch_ident);
    try std.testing.expectEqual(@as(isize, 0), chCompareStr(hello, 1, 5, hello_lower, 1, 5, false, &nch_ident));
    try std.testing.expectEqual(@as(isize, -1), chCompareStr(hello, 1, 5, world, 1, 5, false, &nch_ident));
}

test "character reverse and search utilities operate on StrObject" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const hello = try str_object.newStrObjectFrom(allocator, "HELLO WORLD TEST");
    const world = try str_object.newStrObjectFrom(allocator, "WORLD");
    const reverse_target = try str_object.newStrObjectFrom(allocator, "DLROW");
    const dst = try str_object.newBlankStrObject(allocator, 5);
    var found_loc: isize = 0;

    chReverseStr(world, dst, 5);
    try std.testing.expectEqualStrings("DLROW", dst.slice(1, 5));
    try std.testing.expect(try chSearchStr(allocator, world, 1, 5, hello, 1, 16, true, false, &found_loc));
    try std.testing.expectEqual(@as(isize, 6), found_loc);
    try std.testing.expect(try chSearchStr(allocator, reverse_target, 1, 5, hello, 1, 16, true, true, &found_loc));
    try std.testing.expectEqual(@as(isize, 6), found_loc);
}
