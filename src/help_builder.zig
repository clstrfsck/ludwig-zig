const builtin = @import("builtin");
const std = @import("std");

pub const entry_size: usize = 77;
pub const key_size: usize = 4;
pub const default_input_file = "ludwighlp.t";
pub const default_output_file = "ludwighlp.idx";

pub fn buildHelpIndex(
    allocator: std.mem.Allocator,
    input: []const u8,
    diagnostics: *std.ArrayList(u8),
) ![]u8 {
    var index: std.ArrayList(u8) = .empty;
    defer index.deinit(allocator);

    var contents: std.ArrayList(u8) = .empty;
    defer contents.deinit(allocator);

    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(allocator);

    var cursor: usize = 0;
    var section: []const u8 = "0";
    var index_lines: usize = 0;
    var contents_lines: usize = 0;

    while (cursor < input.len) {
        var flag = input[cursor];
        cursor += 1;

        var line: []const u8 = "";
        if (flag == '\n') {
            flag = ' ';
        } else {
            const line_start = cursor;
            while (cursor < input.len and input[cursor] != '\n') : (cursor += 1) {}
            line = input[line_start..cursor];
            if (cursor < input.len and input[cursor] == '\n') {
                cursor += 1;
            }
        }

        if (line.len > entry_size) {
            if (flag != '!' and flag != '{') {
                try appendFmt(diagnostics, allocator, "Line too long--truncated\n", .{});
                try appendFmt(diagnostics, allocator, "{s}>>\n", .{line});
            }
            line = line[0..entry_size];
        }

        switch (flag) {
            '\\' => {
                if (line.len > 0) {
                    switch (line[0]) {
                        '%' => try appendLine(&body, allocator, "\\%"),
                        '#' => {
                            if (!std.mem.eql(u8, section, "0")) {
                                try appendFmt(&index, allocator, "{d: >8}\n", .{body.items.len});
                            }
                        },
                        else => {
                            if (!std.mem.eql(u8, section, "0")) {
                                try appendFmt(&index, allocator, "{d: >8}\n", .{body.items.len});
                            }
                            section = if (line.len >= key_size) line[0..key_size] else line;
                            if (!std.mem.eql(u8, section, "0")) {
                                index_lines += 1;
                                try appendFmt(
                                    &index,
                                    allocator,
                                    "{s: >4} {d: >8}",
                                    .{ section, body.items.len },
                                );
                            }
                        },
                    }
                }
            },
            '+' => {
                contents_lines += 1;
                try appendLine(&contents, allocator, line);
                try appendLine(&body, allocator, line);
            },
            ' ' => {
                if (std.mem.eql(u8, section, "0")) {
                    contents_lines += 1;
                    try appendLine(&contents, allocator, line);
                } else {
                    try appendLine(&body, allocator, line);
                }
            },
            '{', '!' => {},
            else => {
                try appendFmt(diagnostics, allocator, "Illegal flag character.\n", .{});
                try appendFmt(diagnostics, allocator, "{c}{s}>>\n", .{ flag, line });
            },
        }

        if (flag == '\\' and line.len > 0 and line[0] == '#') {
            break;
        }
    }

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    try appendFmt(&output, allocator, "{d} {d}\n", .{ index_lines, contents_lines });
    try output.appendSlice(allocator, index.items);
    try output.appendSlice(allocator, contents.items);
    try output.appendSlice(allocator, body.items);

    return try output.toOwnedSlice(allocator);
}

pub fn main(init: std.process.Init) !void {
    const use_checked_allocator = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer if (use_checked_allocator) {
        const status = gpa.deinit();
        std.debug.assert(status == .ok);
    };
    const allocator = if (use_checked_allocator) gpa.allocator() else std.heap.page_allocator;

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    // const args = try std.process.argsAlloc(allocator);
    // defer std.process.argsFree(allocator, args);

    const input_path = if (args.len > 1) args[1] else default_input_file;
    const output_path = if (args.len > 2) args[2] else default_output_file;

    const input = std.Io.Dir.cwd().readFileAlloc(
        init.io,
        input_path,
        allocator,
        .unlimited,
    ) catch |err| fatal("{s}: {}\n", .{ input_path, err });
    defer allocator.free(input);

    var diagnostics: std.ArrayList(u8) = .empty;
    defer diagnostics.deinit(allocator);

    const output = buildHelpIndex(allocator, input, &diagnostics) catch |err| {
        fatal("Error processing files: {}\n", .{err});
    };
    defer allocator.free(output);

    if (diagnostics.items.len != 0) {
        std.debug.print("{s}", .{diagnostics.items});
    }

    const output_file = std.Io.Dir.cwd().createFile(init.io, output_path, .{}) catch |err| {
        fatal("{s}: {}\n", .{ output_path, err });
    };
    defer output_file.close(init.io);

    var buf: [4096]u8 = undefined;
    var file_writer = output_file.writer(init.io, &buf);
    defer file_writer.interface.flush() catch {};
    file_writer.interface.writeAll(output) catch |err| {
        fatal("Error processing files: {}\n", .{err});
    };
}

fn appendLine(
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    line: []const u8,
) !void {
    try list.appendSlice(allocator, line);
    try list.append(allocator, '\n');
}

fn appendFmt(
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const rendered = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(rendered);
    try list.appendSlice(allocator, rendered);
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

test "matches a representative help-builder sample" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const input =
        \\+CONTENTS
        \\\ABCD first section
        \\ body line
        \\\%
        \\\EFGH second section
        \\+contents and body
        \\ body only
        \\\#
        \\
    ;
    const expected =
        \\2 2
        \\ABCD        9      22
        \\EFGH       22      50
        \\CONTENTS
        \\contents and body
        \\CONTENTS
        \\body line
        \\\%
        \\contents and body
        \\body only
        \\
    ;

    var diagnostics: std.ArrayList(u8) = .empty;
    defer diagnostics.deinit(allocator);

    const output = try buildHelpIndex(allocator, input, &diagnostics);
    defer allocator.free(output);

    try std.testing.expectEqualStrings("", diagnostics.items);
    try std.testing.expectEqualStrings(expected, output);
}

test "truncates long lines and reports the warning" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const input =
        \\+xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
        \\\#
        \\
    ;
    const expected_output =
        \\0 1
        \\xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
        \\xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
        \\
    ;
    const expected_diagnostics =
        \\Line too long--truncated
        \\xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx>>
        \\
    ;

    var diagnostics: std.ArrayList(u8) = .empty;
    defer diagnostics.deinit(allocator);

    const output = try buildHelpIndex(allocator, input, &diagnostics);
    defer allocator.free(output);

    try std.testing.expectEqualStrings(expected_output, output);
    try std.testing.expectEqualStrings(expected_diagnostics, diagnostics.items);
}
