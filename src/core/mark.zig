const std = @import("std");
const types = @import("types.zig");

fn removeFromMarks(mark_list: *std.ArrayList(*types.MarkObject), mark: *types.MarkObject) void {
    for (mark_list.items, 0..) |existing, index| {
        if (existing == mark) {
            _ = mark_list.orderedRemove(index);
            return;
        }
    }
}

pub fn markCreate(
    allocator: std.mem.Allocator,
    in_line: *types.LineHdrObject,
    column: isize,
    mark_slot: *?*types.MarkObject,
) !void {
    if (mark_slot.* == null) {
        const new_mark = try allocator.create(types.MarkObject);
        new_mark.* = .{
            .line = in_line,
            .col = column,
        };
        try in_line.marks.insert(allocator, 0, new_mark);
        mark_slot.* = new_mark;
        return;
    }

    const current_mark = mark_slot.*.?;
    if (current_mark.line == in_line) {
        current_mark.col = column;
        return;
    }

    removeFromMarks(&current_mark.line.marks, current_mark);
    try in_line.marks.insert(allocator, 0, current_mark);
    current_mark.line = in_line;
    current_mark.col = column;
}

pub fn markDestroy(
    allocator: std.mem.Allocator,
    mark_slot: *?*types.MarkObject,
) void {
    if (mark_slot.*) |mark| {
        removeFromMarks(&mark.line.marks, mark);
        allocator.destroy(mark);
        mark_slot.* = null;
    }
}

pub fn marksSqueeze(
    allocator: std.mem.Allocator,
    first_line: *types.LineHdrObject,
    first_column: isize,
    last_line: *types.LineHdrObject,
    last_column: isize,
) !void {
    if (first_line == last_line) {
        for (last_line.marks.items) |mark| {
            if (mark.col >= first_column and mark.col < last_column) {
                mark.col = last_column;
            }
        }
        return;
    }

    for (last_line.marks.items) |mark| {
        if (mark.col < last_column) {
            mark.col = last_column;
        }
    }

    var current_line: ?*types.LineHdrObject = first_line;
    var column = first_column;
    while (current_line) |line| {
        if (line == last_line) {
            break;
        }
        var index: usize = 0;
        while (index < line.marks.items.len) {
            const mark = line.marks.items[index];
            if (mark.col >= column) {
                mark.col = last_column;
                mark.line = last_line;
                try last_line.marks.insert(allocator, 0, mark);
                _ = line.marks.orderedRemove(index);
            } else {
                index += 1;
            }
        }
        current_line = line.f_link;
        column = 1;
    }
}

pub fn marksShift(
    allocator: std.mem.Allocator,
    source_line: *types.LineHdrObject,
    source_column: isize,
    width: isize,
    dest_line: *types.LineHdrObject,
    dest_column: isize,
) !void {
    const source_end = source_column + width - 1;
    const offset = dest_column - source_column;

    if (source_line == dest_line) {
        for (source_line.marks.items) |mark| {
            if (mark.col >= source_column and mark.col <= source_end) {
                mark.col = @min(mark.col + offset, types.max_str_len_p1);
            }
        }
        return;
    }

    var index: usize = 0;
    while (index < source_line.marks.items.len) {
        const mark = source_line.marks.items[index];
        if (mark.col >= source_column and mark.col <= source_end) {
            mark.line = dest_line;
            mark.col = @min(mark.col + offset, types.max_str_len_p1);
            try dest_line.marks.insert(allocator, 0, mark);
            _ = source_line.marks.orderedRemove(index);
        } else {
            index += 1;
        }
    }
}

fn createTestLine(allocator: std.mem.Allocator) !*types.LineHdrObject {
    const line = try allocator.create(types.LineHdrObject);
    line.* = .{};
    line.f_link = line;
    line.b_link = line;
    return line;
}

fn createLinkedLines(allocator: std.mem.Allocator, count: usize) ![]*types.LineHdrObject {
    const lines = try allocator.alloc(*types.LineHdrObject, count);
    for (lines) |*slot| {
        slot.* = try allocator.create(types.LineHdrObject);
        slot.*.* = .{};
    }
    for (lines, 0..) |line, index| {
        line.b_link = if (index == 0) lines[count - 1] else lines[index - 1];
        line.f_link = if (index == count - 1) lines[0] else lines[index + 1];
    }
    return lines;
}

test "mark create move and destroy preserve line mark lists" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const line1 = try createTestLine(allocator);
    const line2 = try createTestLine(allocator);

    var mark: ?*types.MarkObject = null;
    try markCreate(allocator, line1, 10, &mark);
    try std.testing.expect(mark != null);
    try std.testing.expectEqual(@as(usize, 1), line1.marks.items.len);

    try markCreate(allocator, line2, 15, &mark);
    try std.testing.expectEqual(@as(usize, 0), line1.marks.items.len);
    try std.testing.expectEqual(@as(usize, 1), line2.marks.items.len);
    try std.testing.expectEqual(@as(isize, 15), mark.?.col);

    markDestroy(allocator, &mark);
    try std.testing.expect(mark == null);
    try std.testing.expectEqual(@as(usize, 0), line2.marks.items.len);

    line1.marks.deinit(allocator);
    line2.marks.deinit(allocator);
    allocator.destroy(line1);
    allocator.destroy(line2);
}

test "marks squeeze across lines moves marks to the last line" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lines = try createLinkedLines(allocator, 3);
    defer allocator.free(lines);
    defer for (lines) |line| {
        line.marks.deinit(allocator);
        allocator.destroy(line);
    };

    var mark1: ?*types.MarkObject = null;
    var mark2: ?*types.MarkObject = null;
    var mark3: ?*types.MarkObject = null;
    try markCreate(allocator, lines[0], 5, &mark1);
    try markCreate(allocator, lines[0], 15, &mark2);
    try markCreate(allocator, lines[1], 10, &mark3);

    try marksSqueeze(allocator, lines[0], 10, lines[2], 20);
    try std.testing.expectEqual(@as(isize, 5), mark1.?.col);
    try std.testing.expect(mark1.?.line == lines[0]);
    try std.testing.expect(mark2.?.line == lines[2]);
    try std.testing.expect(mark3.?.line == lines[2]);
    try std.testing.expectEqual(@as(isize, 20), mark2.?.col);
    try std.testing.expectEqual(@as(isize, 20), mark3.?.col);

    markDestroy(allocator, &mark1);
    markDestroy(allocator, &mark2);
    markDestroy(allocator, &mark3);
}

test "marks shift clamps to max_str_len_p1 and preserves out-of-range marks" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const line1 = try createTestLine(allocator);
    const line2 = try createTestLine(allocator);
    defer {
        line1.marks.deinit(allocator);
        line2.marks.deinit(allocator);
        allocator.destroy(line1);
        allocator.destroy(line2);
    }

    var mark1: ?*types.MarkObject = null;
    var mark2: ?*types.MarkObject = null;
    try markCreate(allocator, line1, 10, &mark1);
    try markCreate(allocator, line1, 25, &mark2);

    try marksShift(allocator, line1, 10, 10, line2, types.max_str_len_p1 + 50);
    try std.testing.expect(mark1.?.line == line2);
    try std.testing.expectEqual(@as(isize, types.max_str_len_p1), mark1.?.col);
    try std.testing.expect(mark2.?.line == line1);
    try std.testing.expectEqual(@as(isize, 25), mark2.?.col);

    markDestroy(allocator, &mark1);
    markDestroy(allocator, &mark2);
}
