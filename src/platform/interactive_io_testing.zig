const std = @import("std");
const types = @import("../core/types.zig");

var input: ?[]const u8 = null;
var input_index: usize = 0;
var pending_key: ?u8 = null;
var pending_input_key: ?isize = null;
var dimensions_override: ?DimensionsOverride = null;

pub const DimensionsOverride = struct {
    width: isize,
    height: isize,
};

pub fn isActive() bool {
    return input != null;
}

pub fn installInput(source: []const u8) void {
    input = source;
    input_index = 0;
    pending_key = null;
    pending_input_key = null;
}

pub fn clearInput() void {
    input = null;
    input_index = 0;
    pending_key = null;
    pending_input_key = null;
    dimensions_override = null;
}

pub fn takeBackInputKey(key: isize) void {
    pending_input_key = key;
}

pub fn setDimensionsOverride(width: isize, height: isize) void {
    dimensions_override = .{
        .width = width,
        .height = height,
    };
}

pub fn getDimensionsOverride() ?DimensionsOverride {
    return dimensions_override;
}

pub fn readKey() ?u8 {
    if (pending_key) |key| {
        pending_key = null;
        return key;
    }
    if (input) |source| {
        if (input_index >= source.len) {
            return null;
        }
        const key = source[input_index];
        input_index += 1;
        return key;
    }
    return null;
}

fn takeBackKey(key: u8) void {
    pending_key = key;
}

fn decodeCsiFinal(final: u8) ?isize {
    return switch (final) {
        'A' => types.TerminalKeyCodes.UpArrow,
        'B' => types.TerminalKeyCodes.DownArrow,
        'C' => types.TerminalKeyCodes.RightArrow,
        'D' => types.TerminalKeyCodes.LeftArrow,
        'H' => types.TerminalKeyCodes.Home,
        'Z' => types.TerminalKeyCodes.BackTab,
        else => null,
    };
}

fn decodeCsiTilde(final: u8) ?isize {
    return switch (final) {
        '1', '7' => types.TerminalKeyCodes.Home,
        '2' => types.TerminalKeyCodes.InsertChar,
        '3' => types.TerminalKeyCodes.DeleteChar,
        '5' => types.TerminalKeyCodes.PageUp,
        '6' => types.TerminalKeyCodes.PageDown,
        else => null,
    };
}

pub fn readInputKey() ?isize {
    if (pending_input_key) |key| {
        pending_input_key = null;
        return key;
    }

    const first = readKey() orelse return null;
    if (first != 27) {
        return first;
    }

    const second = readKey() orelse return first;
    switch (second) {
        '[' => {
            const third = readKey() orelse return first;
            if (decodeCsiFinal(third)) |decoded| {
                return decoded;
            }
            if (third >= '0' and third <= '9') {
                const fourth = readKey() orelse return first;
                if (fourth == '~') {
                    if (decodeCsiTilde(third)) |decoded| {
                        return decoded;
                    }
                }
            }
            return first;
        },
        'O' => {
            const third = readKey() orelse return first;
            return decodeCsiFinal(third) orelse first;
        },
        else => {
            takeBackKey(second);
            return first;
        },
    }
}

test "interactive io testing harness reads queued bytes" {
    installInput("ab\rQ");
    defer clearInput();

    try std.testing.expectEqual(@as(?u8, 'a'), readKey());
    try std.testing.expectEqual(@as(?u8, 'b'), readKey());
    takeBackKey('x');
    try std.testing.expectEqual(@as(?u8, 'x'), readKey());
}

test "interactive io testing harness decodes common escape sequences" {
    installInput("\x1b[A\x1b[B\x1b[C\x1b[D\x1b[H\x1b[Z\x1b[2~\x1b[3~\x1b[5~\x1b[6~");
    defer clearInput();

    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.UpArrow), readInputKey());
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.DownArrow), readInputKey());
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.RightArrow), readInputKey());
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.LeftArrow), readInputKey());
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.Home), readInputKey());
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.BackTab), readInputKey());
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.InsertChar), readInputKey());
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.DeleteChar), readInputKey());
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.PageUp), readInputKey());
    try std.testing.expectEqual(@as(?isize, types.TerminalKeyCodes.PageDown), readInputKey());
}
