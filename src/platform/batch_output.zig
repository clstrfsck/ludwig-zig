const std = @import("std");

pub fn printMessage(message: []const u8) void {
    std.fs.File.stdout().deprecatedWriter().print("{s}\n", .{message}) catch {};
}

pub fn printLines(lines: []const []const u8, leading_blank_lines: usize) void {
    const writer = std.fs.File.stdout().deprecatedWriter();
    var blanks: usize = 0;
    while (blanks < leading_blank_lines) : (blanks += 1) {
        writer.print("\n", .{}) catch {};
    }
    for (lines) |line| {
        writer.print("{s}\n", .{line}) catch {};
    }
}
