const std = @import("std");

pub fn printMessage(io: std.Io, message: []const u8) void {
    var buf: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buf);
    defer writer.interface.flush() catch {};
    writer.interface.print("{s}\n", .{message}) catch {};
}

pub fn printLines(io: std.Io, lines: []const []const u8, leading_blank_lines: usize) void {
    var buf: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buf);
    defer writer.interface.flush() catch {};

    var blanks: usize = 0;
    while (blanks < leading_blank_lines) : (blanks += 1) {
        writer.interface.print("\n", .{}) catch {};
    }
    for (lines) |line| {
        writer.interface.print("{s}\n", .{line}) catch {};
    }
}
