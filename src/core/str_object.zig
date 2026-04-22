const std = @import("std");

pub const min_index: isize = 1;

pub const StrObject = struct {
    allocator: std.mem.Allocator,
    array: []u8,

    pub fn size(self: *const StrObject) usize {
        return self.array.len;
    }

    pub fn len(self: *const StrObject) usize {
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
        if (combined_index < min_index or combined_index > @as(isize, @intCast(self.array.len))) {
            @panic("index out of range");
        }
    }

    fn adjustIndex(self: *const StrObject, index: isize, offset: isize) usize {
        self.checkIndex(index, offset);
        return @intCast(index + offset - min_index);
    }

    pub fn get(self: *const StrObject, index: isize) u8 {
        return self.array[self.adjustIndex(index, 0)];
    }

    pub fn set(self: *StrObject, index: isize, value: u8) void {
        self.array[self.adjustIndex(index, 0)] = value;
    }

    pub fn assign(self: *StrObject, str: []const u8) !void {
        if (self.array.len < str.len) {
            self.array = try self.allocator.realloc(self.array, str.len);
        }
        self.fillCopyBytes(str, 1, @intCast(self.array.len), ' ');
    }

    pub fn clone(self: *const StrObject) !*StrObject {
        const result = try self.allocator.create(StrObject);
        result.* = .{
            .allocator = self.allocator,
            .array = try self.allocator.alloc(u8, self.array.len),
        };
        @memcpy(result.array, self.array);
        return result;
    }

    pub fn equalAt(
        self: *const StrObject,
        other: *const StrObject,
        n: isize,
        src_offset: isize,
        dst_offset: isize,
    ) bool {
        if (n == 0) {
            return true;
        }
        self.checkIndex(src_offset, n - 1);
        other.checkIndex(dst_offset, n - 1);
        const src_idx = self.adjustIndex(src_offset, 0);
        const dst_idx = other.adjustIndex(dst_offset, 0);
        return std.mem.eql(
            u8,
            self.array[src_idx .. src_idx + @as(usize, @intCast(n))],
            other.array[dst_idx .. dst_idx + @as(usize, @intCast(n))],
        );
    }

    pub fn applyN(
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

    pub fn copy(
        self: *StrObject,
        src: *const StrObject,
        src_offset: isize,
        count: isize,
        dst_offset: isize,
    ) void {
        if (count <= 0) {
            return;
        }
        src.checkIndex(src_offset, count - 1);
        self.checkIndex(dst_offset, count - 1);
        const src_idx = src.adjustIndex(src_offset, 0);
        const dst_idx = self.adjustIndex(dst_offset, 0);
        const copy_len: usize = @intCast(count);
        if (@intFromPtr(self.array.ptr) == @intFromPtr(src.array.ptr) and dst_idx > src_idx and src_idx + copy_len > dst_idx) {
            std.mem.copyBackwards(u8, self.array[dst_idx .. dst_idx + copy_len], src.array[src_idx .. src_idx + copy_len]);
        } else {
            std.mem.copyForwards(u8, self.array[dst_idx .. dst_idx + copy_len], src.array[src_idx .. src_idx + copy_len]);
        }
    }

    pub fn copyN(
        self: *StrObject,
        src: []const u8,
        count: isize,
        dst_offset: isize,
    ) void {
        if (count <= 0) {
            return;
        }
        self.checkIndex(dst_offset, count - 1);
        const dst_idx = self.adjustIndex(dst_offset, 0);
        const copy_len: usize = @intCast(count);
        std.mem.copyForwards(u8, self.array[dst_idx .. dst_idx + copy_len], src[0..copy_len]);
    }

    pub fn erase(self: *StrObject, n: isize, from: isize) void {
        if (n <= 0) {
            return;
        }
        self.checkIndex(from, n - 1);
        const dst_idx = self.adjustIndex(from, 0);
        const count: usize = @intCast(n);
        std.mem.copyForwards(u8, self.array[dst_idx .. self.array.len - count], self.array[dst_idx + count ..]);
        self.fill(' ', @intCast(@as(isize, @intCast(self.array.len)) - n + 1), @intCast(self.array.len));
    }

    pub fn fill(self: *StrObject, value: u8, start: isize, end: isize) void {
        if (start > end) {
            return;
        }
        const start_idx = self.adjustIndex(start, 0);
        const end_idx = self.adjustIndex(end, 0) + 1;
        @memset(self.array[start_idx..end_idx], value);
    }

    pub fn fillN(self: *StrObject, value: u8, n: isize, start: isize) void {
        if (n <= 0) {
            return;
        }
        self.fill(value, start, start + n - 1);
    }

    pub fn fillCopy(
        self: *StrObject,
        src: *const StrObject,
        src_index: isize,
        src_len: isize,
        dst_index: isize,
        dst_len: isize,
        value: u8,
    ) void {
        if (dst_len <= 0) {
            return;
        }
        self.checkIndex(dst_index, dst_len - 1);
        const dst_idx = self.adjustIndex(dst_index, 0);
        const copy_len: usize = @intCast(@min(src_len, dst_len));
        if (copy_len > 0) {
            src.checkIndex(src_index, @intCast(copy_len - 1));
            const src_idx = src.adjustIndex(src_index, 0);
            std.mem.copyForwards(u8, self.array[dst_idx .. dst_idx + copy_len], src.array[src_idx .. src_idx + copy_len]);
        }
        if (@as(isize, @intCast(copy_len)) < dst_len) {
            @memset(self.array[dst_idx + copy_len .. dst_idx + @as(usize, @intCast(dst_len))], value);
        }
    }

    pub fn fillCopyBytes(
        self: *StrObject,
        src: []const u8,
        dst_index: isize,
        dst_len: isize,
        value: u8,
    ) void {
        var clamped_dst_len = dst_len;
        clamped_dst_len = @min(clamped_dst_len, @as(isize, @intCast(self.array.len)) - dst_index + min_index);
        if (clamped_dst_len <= 0) {
            return;
        }
        self.checkIndex(dst_index, clamped_dst_len - 1);
        const dst_idx = self.adjustIndex(dst_index, 0);
        const copy_len: usize = @min(src.len, @as(usize, @intCast(clamped_dst_len)));
        if (copy_len > 0) {
            std.mem.copyForwards(u8, self.array[dst_idx .. dst_idx + copy_len], src[0..copy_len]);
        }
        if (@as(isize, @intCast(copy_len)) < clamped_dst_len) {
            @memset(self.array[dst_idx + copy_len .. dst_idx + @as(usize, @intCast(clamped_dst_len))], value);
        }
    }

    pub fn insert(self: *StrObject, n: isize, at: isize) void {
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

    pub fn trimmedLen(self: *const StrObject, value: u8, from: isize) isize {
        var cursor = @min(from, @as(isize, @intCast(self.array.len)));
        while (cursor > 0) : (cursor -= 1) {
            if (self.array[@as(usize, @intCast(cursor - 1))] != value) {
                return cursor;
            }
        }
        return 0;
    }

    pub fn slice(self: *const StrObject, index: isize, length: isize) []const u8 {
        if (length == 0) {
            return "";
        }
        self.checkIndex(index, length - 1);
        const idx = self.adjustIndex(index, 0);
        return self.array[idx .. idx + @as(usize, @intCast(length))];
    }

    pub fn string(self: *const StrObject) []const u8 {
        return self.array;
    }

    pub fn trimmedString(self: *const StrObject) []const u8 {
        const length = self.trimmedLen(' ', @intCast(self.array.len));
        return self.array[0..@as(usize, @intCast(length))];
    }

    pub fn compare(self: *const StrObject, other: *const StrObject) isize {
        return switch (std.mem.order(u8, self.array, other.array)) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        };
    }

    pub fn equal(self: *const StrObject, other: *const StrObject) bool {
        return std.mem.eql(u8, self.array, other.array);
    }

    pub fn bytes(self: *const StrObject) ![]u8 {
        return self.allocator.dupe(u8, self.array);
    }
};

pub fn newBlankStrObject(allocator: std.mem.Allocator, size: usize) !*StrObject {
    const result = try allocator.create(StrObject);
    result.* = .{
        .allocator = allocator,
        .array = try allocator.alloc(u8, size),
    };
    @memset(result.array, ' ');
    return result;
}

pub fn newStrObjectFrom(allocator: std.mem.Allocator, str: []const u8) !*StrObject {
    const result = try allocator.create(StrObject);
    result.* = .{
        .allocator = allocator,
        .array = try allocator.dupe(u8, str),
    };
    return result;
}

pub fn newStrObjectCopy(
    allocator: std.mem.Allocator,
    src: *const StrObject,
    src_index: isize,
    src_len: isize,
    dst_len: isize,
) !*StrObject {
    const result = try newBlankStrObject(allocator, @intCast(dst_len));
    result.copy(src, src_index, @min(src_len, dst_len), 1);
    if (src_len < dst_len) {
        result.fill(' ', src_len + 1, dst_len);
    }
    return result;
}

test "blank string object contains blanks" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const s = try newBlankStrObject(allocator, 8);
    defer s.destroy();

    try std.testing.expectEqual(@as(usize, 8), s.len());
    for (s.array) |ch| {
        try std.testing.expectEqual(' ', ch);
    }
}

test "get set and 1-based indexing" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const s = try newBlankStrObject(allocator, 10);
    defer s.destroy();

    s.set(1, 'A');
    s.set(10, 'Z');
    try std.testing.expectEqual('A', s.get(1));
    try std.testing.expectEqual('Z', s.get(10));
}

test "assign pads with spaces" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const s = try newBlankStrObject(allocator, 8);
    defer s.destroy();

    try s.assign("Hello");
    try std.testing.expectEqualStrings("Hello", s.slice(1, 5));
    try std.testing.expectEqual(' ', s.get(6));
}

test "clone produces an independent copy" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const original = try newBlankStrObject(allocator, 8);
    defer original.destroy();
    original.set(2, 'B');

    const clone = try original.clone();
    defer clone.destroy();
    clone.set(2, 'X');

    try std.testing.expectEqual('B', original.get(2));
    try std.testing.expectEqual('X', clone.get(2));
}

test "erase shifts and fills vacated space" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const s = try newStrObjectFrom(allocator, "ABCDEFGHIJ");
    defer s.destroy();

    s.erase(3, 4);
    try std.testing.expectEqualStrings("ABCGHIJ", s.trimmedString());
    try std.testing.expectEqual(' ', s.get(8));
    try std.testing.expectEqual(' ', s.get(9));
    try std.testing.expectEqual(' ', s.get(10));
}

test "fill copy bytes truncates and pads" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const s = try newBlankStrObject(allocator, 8);
    defer s.destroy();

    s.fillCopyBytes("Hello", 1, 8, '-');
    try std.testing.expectEqualStrings("Hello---", s.string());
}

test "trimmed length and slice preserve semantics" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const s = try newBlankStrObject(allocator, 12);
    defer s.destroy();

    try s.assign("Hello  ");
    try std.testing.expectEqual(@as(isize, 5), s.trimmedLen(' ', 12));
    try std.testing.expectEqualStrings("ell", s.slice(2, 3));
}

test "compare and equal match byte ordering" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const a = try newStrObjectFrom(allocator, "AAAA");
    defer a.destroy();
    const b = try newStrObjectFrom(allocator, "BBBB");
    defer b.destroy();
    const c = try newStrObjectFrom(allocator, "AAAA");
    defer c.destroy();

    try std.testing.expect(a.compare(b) < 0);
    try std.testing.expect(a.equal(c));
    try std.testing.expect(!a.equal(b));
}
