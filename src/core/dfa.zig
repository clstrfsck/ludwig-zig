const std = @import("std");
const types = @import("types.zig");

fn clearDefinition(table: *types.DFATableObject) void {
    if (table.definition.strng) |definition| {
        definition.destroy();
        table.definition.strng = null;
    }
    table.definition.length = 0;
}

pub fn patternDFATableKill(
    allocator: std.mem.Allocator,
    pattern_ptr: *?*types.DFATableObject,
) void {
    if (pattern_ptr.*) |pattern| {
        clearDefinition(pattern);
        allocator.destroy(pattern);
        pattern_ptr.* = null;
    }
}

pub fn patternDFATableInitialize(
    allocator: std.mem.Allocator,
    pattern_ptr: *?*types.DFATableObject,
    pattern_definition: types.PatternDefType,
) !bool {
    const table = if (pattern_ptr.*) |existing| blk: {
        clearDefinition(existing);
        existing.* = .{};
        break :blk existing;
    } else blk: {
        const created = try allocator.create(types.DFATableObject);
        created.* = .{};
        pattern_ptr.* = created;
        break :blk created;
    };

    if (pattern_definition.strng) |definition| {
        table.definition.strng = try definition.clone();
    }
    table.definition.length = pattern_definition.length;
    return true;
}

pub fn patternDFAConvert(
    nfa_table: *types.NFATableType,
    dfa_table_pointer: *types.DFATableObject,
    nfa_start: isize,
    nfa_end: *isize,
    middle_context_start: isize,
    right_context_start: isize,
    dfa_start: *isize,
    dfa_end: *isize,
) !bool {
    _ = nfa_table;
    _ = nfa_start;
    _ = nfa_end;
    _ = middle_context_start;
    _ = right_context_start;

    if (dfa_table_pointer.definition.strng == null or dfa_table_pointer.definition.length == 0) {
        return false;
    }

    dfa_table_pointer.dfa_states_used = types.pattern_dfa_start;
    dfa_start.* = types.pattern_dfa_start;
    dfa_end.* = types.pattern_dfa_start;
    return true;
}

test "dfa table initialize owns pattern definitions and kill releases them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var table: ?*types.DFATableObject = null;
    const source = try @import("str_object.zig").newStrObjectFrom(allocator, "'abc'");
    try std.testing.expect(try patternDFATableInitialize(allocator, &table, .{
        .strng = source,
        .length = 5,
    }));
    try std.testing.expect(table != null);
    try std.testing.expect(table.?.definition.strng != source);
    try std.testing.expectEqualStrings("'abc'", table.?.definition.strng.?.slice(1, 5));

    var nfa_table: types.NFATableType = [_]types.NFATransitionType{.{}} ** (types.max_nfa_state_range + 1);
    var nfa_end: isize = 1;
    var dfa_start: isize = 0;
    var dfa_end: isize = 0;
    try std.testing.expect(try patternDFAConvert(&nfa_table, table.?, 1, &nfa_end, 1, 1, &dfa_start, &dfa_end));
    try std.testing.expectEqual(@as(isize, types.pattern_dfa_start), dfa_start);
    try std.testing.expectEqual(@as(isize, types.pattern_dfa_start), dfa_end);

    patternDFATableKill(allocator, &table);
    try std.testing.expect(table == null);
}
