const std = @import("std");

pub const MinIndex: isize = 1;

pub const StrObject = struct {
    allocator: std.mem.Allocator,
    array: []u8,

    pub fn Size(self: *const StrObject) usize {
        return self.array.len;
    }

    pub fn Len(self: *const StrObject) usize {
        return self.array.len;
    }

    pub fn deinit(self: *StrObject) void {
        self.allocator.free(self.array);
        self.array = &.{};
    }

    pub fn destroy(self: *StrObject) void {
        const allocator = self.allocator;
        self.deinit();
        allocator.destroy(self);
    }

    fn checkIndex(self: *const StrObject, index: isize, offset: isize) void {
        if (offset > 0 and index > std.math.maxInt(isize) - offset) {
            @panic("index + offset overflow");
        }
        if (offset < 0 and index < std.math.minInt(isize) - offset) {
            @panic("index + offset underflow");
        }
        const combined_index = index + offset;
        if (combined_index < MinIndex or combined_index > @as(isize, @intCast(self.array.len))) {
            @panic("index out of range");
        }
    }

    fn adjustIndex(self: *const StrObject, index: isize, offset: isize) usize {
        self.checkIndex(index, offset);
        return @intCast(index + offset - MinIndex);
    }

    pub fn Get(self: *const StrObject, index: isize) u8 {
        return self.array[self.adjustIndex(index, 0)];
    }

    pub fn Set(self: *StrObject, index: isize, value: u8) void {
        self.array[self.adjustIndex(index, 0)] = value;
    }

    pub fn Assign(self: *StrObject, str: []const u8) !void {
        if (self.array.len < str.len) {
            self.array = try self.allocator.realloc(self.array, str.len);
        }
        self.FillCopyBytes(str, 1, @intCast(self.array.len), ' ');
    }

    pub fn Clone(self: *const StrObject) !*StrObject {
        const result = try self.allocator.create(StrObject);
        result.* = .{
            .allocator = self.allocator,
            .array = try self.allocator.alloc(u8, self.array.len),
        };
        @memcpy(result.array, self.array);
        return result;
    }

    pub fn EqualAt(
        self: *const StrObject,
        other: *const StrObject,
        n: isize,
        srcOffset: isize,
        dstOffset: isize,
    ) bool {
        if (n == 0) {
            return true;
        }
        self.checkIndex(srcOffset, n - 1);
        other.checkIndex(dstOffset, n - 1);
        const src_idx = self.adjustIndex(srcOffset, 0);
        const dst_idx = other.adjustIndex(dstOffset, 0);
        return std.mem.eql(
            u8,
            self.array[src_idx .. src_idx + @as(usize, @intCast(n))],
            other.array[dst_idx .. dst_idx + @as(usize, @intCast(n))],
        );
    }

    pub fn ApplyN(
        self: *StrObject,
        comptime f: fn (u8) u8,
        n: isize,
        start: isize,
    ) void {
        if (n <= 0) {
            return;
        }
        const idx = self.adjustIndex(start, 0);
        const count: usize = @intCast(n);
        for (self.array[idx .. idx + count]) |*ch| {
            ch.* = f(ch.*);
        }
    }

    pub fn Copy(
        self: *StrObject,
        src: *const StrObject,
        srcOffset: isize,
        count: isize,
        dstOffset: isize,
    ) void {
        if (count <= 0) {
            return;
        }
        src.checkIndex(srcOffset, count - 1);
        self.checkIndex(dstOffset, count - 1);
        const src_idx = src.adjustIndex(srcOffset, 0);
        const dst_idx = self.adjustIndex(dstOffset, 0);
        const len: usize = @intCast(count);
        if (@intFromPtr(self.array.ptr) == @intFromPtr(src.array.ptr) and dst_idx > src_idx and src_idx + len > dst_idx) {
            std.mem.copyBackwards(u8, self.array[dst_idx .. dst_idx + len], src.array[src_idx .. src_idx + len]);
        } else {
            std.mem.copyForwards(u8, self.array[dst_idx .. dst_idx + len], src.array[src_idx .. src_idx + len]);
        }
    }

    pub fn CopyN(
        self: *StrObject,
        src: []const u8,
        count: isize,
        dstOffset: isize,
    ) void {
        if (count <= 0) {
            return;
        }
        self.checkIndex(dstOffset, count - 1);
        const dst_idx = self.adjustIndex(dstOffset, 0);
        const len: usize = @intCast(count);
        std.mem.copyForwards(u8, self.array[dst_idx .. dst_idx + len], src[0..len]);
    }

    pub fn Erase(self: *StrObject, n: isize, from: isize) void {
        if (n <= 0) {
            return;
        }
        self.checkIndex(from, n - 1);
        const dst_idx = self.adjustIndex(from, 0);
        const count: usize = @intCast(n);
        std.mem.copyForwards(u8, self.array[dst_idx .. self.array.len - count], self.array[dst_idx + count ..]);
        self.Fill(' ', @intCast(@as(isize, @intCast(self.array.len)) - n + 1), @intCast(self.array.len));
    }

    pub fn Fill(self: *StrObject, value: u8, start: isize, end: isize) void {
        if (start > end) {
            return;
        }
        const start_idx = self.adjustIndex(start, 0);
        const end_idx = self.adjustIndex(end, 0) + 1;
        @memset(self.array[start_idx..end_idx], value);
    }

    pub fn FillN(self: *StrObject, value: u8, n: isize, start: isize) void {
        if (n <= 0) {
            return;
        }
        self.Fill(value, start, start + n - 1);
    }

    pub fn FillCopy(
        self: *StrObject,
        src: *const StrObject,
        srcIndex: isize,
        srcLen: isize,
        dstIndex: isize,
        dstLen: isize,
        value: u8,
    ) void {
        if (dstLen <= 0) {
            return;
        }
        self.checkIndex(dstIndex, dstLen - 1);
        const dst_idx = self.adjustIndex(dstIndex, 0);
        const len: usize = @intCast(@min(srcLen, dstLen));
        if (len > 0) {
            src.checkIndex(srcIndex, @intCast(len - 1));
            const src_idx = src.adjustIndex(srcIndex, 0);
            std.mem.copyForwards(u8, self.array[dst_idx .. dst_idx + len], src.array[src_idx .. src_idx + len]);
        }
        if (@as(isize, @intCast(len)) < dstLen) {
            @memset(self.array[dst_idx + len .. dst_idx + @as(usize, @intCast(dstLen))], value);
        }
    }

    pub fn FillCopyBytes(
        self: *StrObject,
        src: []const u8,
        dstIndex: isize,
        dstLen: isize,
        value: u8,
    ) void {
        var clamped_dst_len = dstLen;
        clamped_dst_len = @min(clamped_dst_len, @as(isize, @intCast(self.array.len)) - dstIndex + MinIndex);
        if (clamped_dst_len <= 0) {
            return;
        }
        self.checkIndex(dstIndex, clamped_dst_len - 1);
        const dst_idx = self.adjustIndex(dstIndex, 0);
        const len: usize = @min(src.len, @as(usize, @intCast(clamped_dst_len)));
        if (len > 0) {
            std.mem.copyForwards(u8, self.array[dst_idx .. dst_idx + len], src[0..len]);
        }
        if (@as(isize, @intCast(len)) < clamped_dst_len) {
            @memset(self.array[dst_idx + len .. dst_idx + @as(usize, @intCast(clamped_dst_len))], value);
        }
    }

    pub fn Insert(self: *StrObject, n: isize, at: isize) void {
        if (n <= 0) {
            return;
        }
        const at_idx = self.adjustIndex(at, 0);
        const count: usize = @intCast(n);
        if (at_idx + count > self.array.len) {
            @panic("insert out of range");
        }
        std.mem.copyBackwards(
            u8,
            self.array[at_idx + count ..],
            self.array[at_idx .. self.array.len - count],
        );
    }

    pub fn TrimmedLen(self: *const StrObject, value: u8, from: isize) isize {
        var cursor = @min(from, @as(isize, @intCast(self.array.len)));
        while (cursor > 0) : (cursor -= 1) {
            if (self.array[@as(usize, @intCast(cursor - 1))] != value) {
                return cursor;
            }
        }
        return 0;
    }

    pub fn Slice(self: *const StrObject, index: isize, length: isize) []const u8 {
        if (length == 0) {
            return "";
        }
        self.checkIndex(index, length - 1);
        const idx = self.adjustIndex(index, 0);
        return self.array[idx .. idx + @as(usize, @intCast(length))];
    }

    pub fn String(self: *const StrObject) []const u8 {
        return self.array;
    }

    pub fn TrimmedString(self: *const StrObject) []const u8 {
        const length = self.TrimmedLen(' ', @intCast(self.array.len));
        return self.array[0..@as(usize, @intCast(length))];
    }

    pub fn Compare(self: *const StrObject, other: *const StrObject) isize {
        return switch (std.mem.order(u8, self.array, other.array)) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        };
    }

    pub fn Equal(self: *const StrObject, other: *const StrObject) bool {
        return std.mem.eql(u8, self.array, other.array);
    }

    pub fn Bytes(self: *const StrObject) ![]u8 {
        return self.allocator.dupe(u8, self.array);
    }
};

pub fn NewBlankStrObject(allocator: std.mem.Allocator, size: usize) !*StrObject {
    const result = try allocator.create(StrObject);
    result.* = .{
        .allocator = allocator,
        .array = try allocator.alloc(u8, size),
    };
    @memset(result.array, ' ');
    return result;
}

pub fn NewStrObjectFrom(allocator: std.mem.Allocator, str: []const u8) !*StrObject {
    const result = try allocator.create(StrObject);
    result.* = .{
        .allocator = allocator,
        .array = try allocator.dupe(u8, str),
    };
    return result;
}

pub fn NewStrObjectCopy(
    allocator: std.mem.Allocator,
    src: *const StrObject,
    srcIndex: isize,
    srcLen: isize,
    dstLen: isize,
) !*StrObject {
    const result = try NewBlankStrObject(allocator, @intCast(dstLen));
    result.Copy(src, srcIndex, @min(srcLen, dstLen), 1);
    if (srcLen < dstLen) {
        result.Fill(' ', srcLen + 1, dstLen);
    }
    return result;
}

pub fn EmptyStrObject(allocator: std.mem.Allocator) !*StrObject {
    return NewBlankStrObject(allocator, 0);
}

test "blank string object contains blanks" {
    const allocator = std.testing.allocator;
    const s = try NewBlankStrObject(allocator, 8);
    defer s.destroy();

    try std.testing.expectEqual(@as(usize, 8), s.Len());
    for (s.array) |ch| {
        try std.testing.expectEqual(' ', ch);
    }
}

test "get set and 1-based indexing" {
    const allocator = std.testing.allocator;
    const s = try NewBlankStrObject(allocator, 10);
    defer s.destroy();

    s.Set(1, 'A');
    s.Set(10, 'Z');
    try std.testing.expectEqual('A', s.Get(1));
    try std.testing.expectEqual('Z', s.Get(10));
}

test "assign pads with spaces" {
    const allocator = std.testing.allocator;
    const s = try NewBlankStrObject(allocator, 8);
    defer s.destroy();

    try s.Assign("Hello");
    try std.testing.expectEqualStrings("Hello", s.Slice(1, 5));
    try std.testing.expectEqual(' ', s.Get(6));
}

test "clone produces an independent copy" {
    const allocator = std.testing.allocator;
    const original = try NewBlankStrObject(allocator, 8);
    defer original.destroy();
    original.Set(2, 'B');

    const clone = try original.Clone();
    defer clone.destroy();
    clone.Set(2, 'X');

    try std.testing.expectEqual('B', original.Get(2));
    try std.testing.expectEqual('X', clone.Get(2));
}

test "erase shifts and fills vacated space" {
    const allocator = std.testing.allocator;
    const s = try NewStrObjectFrom(allocator, "ABCDEFGHIJ");
    defer s.destroy();

    s.Erase(3, 4);
    try std.testing.expectEqualStrings("ABCGHIJ", s.TrimmedString());
    try std.testing.expectEqual(' ', s.Get(8));
    try std.testing.expectEqual(' ', s.Get(9));
    try std.testing.expectEqual(' ', s.Get(10));
}

test "fill copy bytes truncates and pads" {
    const allocator = std.testing.allocator;
    const s = try NewBlankStrObject(allocator, 8);
    defer s.destroy();

    s.FillCopyBytes("Hello", 1, 8, '-');
    try std.testing.expectEqualStrings("Hello---", s.String());
}

test "trimmed length and slice preserve Go semantics" {
    const allocator = std.testing.allocator;
    const s = try NewBlankStrObject(allocator, 12);
    defer s.destroy();

    try s.Assign("Hello  ");
    try std.testing.expectEqual(@as(isize, 5), s.TrimmedLen(' ', 12));
    try std.testing.expectEqualStrings("ell", s.Slice(2, 3));
}

test "compare and equal match byte ordering" {
    const allocator = std.testing.allocator;
    const a = try NewStrObjectFrom(allocator, "AAAA");
    defer a.destroy();
    const b = try NewStrObjectFrom(allocator, "BBBB");
    defer b.destroy();
    const c = try NewStrObjectFrom(allocator, "AAAA");
    defer c.destroy();

    try std.testing.expect(a.Compare(b) < 0);
    try std.testing.expect(a.Equal(c));
    try std.testing.expect(!a.Equal(b));
}
