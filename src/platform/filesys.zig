const std = @import("std");
const file_ops = @import("../core/file.zig");
const state = @import("../core/state.zig");
const sys_ops = @import("sys.zig");
const types = @import("../core/types.zig");

pub const ParseType = enum {
    ParseCommand,
    ParseInput,
    ParseOutput,
    ParseEdit,
    ParseStdin,
    ParseExecute,
};

pub const ParseResult = struct {
    ok: bool = false,
    show_usage: bool = false,
    message: []const u8 = "",
};

pub const command_usage =
    "usage: ludwig [-c] [-r] [-i value] [-I] [-s value] [-m file] [-M] [-t] [-T] [-b value] [-B value] [-o] [-O] [-u] [-w value] [file [file]]";
pub const file_usage =
    "usage: [-m file] [-t] [-T] [-b value] [-B value] [file [file]]";

fn usageFor(parse_type: ParseType) []const u8 {
    return if (parse_type == .ParseCommand) command_usage else file_usage;
}

fn defaultHomePath(allocator: std.mem.Allocator, suffix: []const u8) ![]const u8 {
    const home = sys_ops.getEnv(allocator, "HOME") orelse ".";
    return std.fs.path.join(allocator, &.{ home, suffix });
}

fn parseIntArg(arg: []const u8) ?isize {
    return std.fmt.parseInt(isize, arg, 10) catch null;
}

fn makeStdinFile(allocator: std.mem.Allocator) !*types.FileObject {
    const input = try allocator.create(types.FileObject);
    input.* = .{
        .Valid = true,
        .OutputFlag = false,
        .Filename = "<stdin>",
    };
    return input;
}

fn openInputFile(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    file_name: []const u8,
) !?*types.FileObject {
    return file_ops.OpenDiskInputFile(editor, allocator, file_name);
}

fn openOutputFile(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    file_name: []const u8,
    related_name: ?[]const u8,
    create: bool,
    memory: []const u8,
    entab: bool,
    purge: bool,
    versions: isize,
) !?*types.FileObject {
    const expanded_memory = if (memory.len > 0)
        (try sys_ops.expandFilename(allocator, memory)) orelse return null
    else
        null;
    const output = (try file_ops.OpenDiskOutputFile(editor, allocator, file_name, .{
        .related_name = related_name,
        .create = create,
        .memory = expanded_memory,
    })) orelse return null;
    output.Memory = if (expanded_memory) |path| path else "";
    output.Entab = entab;
    output.Purge = purge;
    output.Versions = versions;
    output.Create = create;
    return output;
}

fn fail(message: []const u8) ParseResult {
    return .{
        .ok = false,
        .message = message,
    };
}

pub fn FileCreateOpen(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    parse_type: ParseType,
    input_out: *?*types.FileObject,
    output_out: *?*types.FileObject,
) !ParseResult {
    input_out.* = null;
    output_out.* = null;

    if (parse_type == .ParseStdin) {
        input_out.* = try makeStdinFile(allocator);
        return .{ .ok = true };
    }

    var entab = editor.FileData.Entab;
    var highlighting = editor.FileData.Highlighting;
    var space = editor.FileData.Space;
    var purge = editor.FileData.Purge;
    var versions = editor.FileData.Versions;
    var tab_width = editor.FileData.TabWidth;

    var create_flag = false;
    var read_only_flag = false;
    var space_flag = false;
    var usage_flag = false;
    var version_flag = false;
    var errors: usize = 0;
    var check_input = false;

    var initialize: []const u8 = "";
    var memory: []const u8 = "";
    if (parse_type == .ParseCommand) {
        initialize = try defaultHomePath(allocator, ".ludwigrc");
        memory = try defaultHomePath(allocator, ".lud_memory");
    }

    var optind: usize = 0;
    while (optind < argv.len) {
        const arg = argv[optind];
        if (!std.mem.startsWith(u8, arg, "-") or arg.len <= 1) {
            break;
        }
        optind += 1;

        for (arg[1..]) |ch| {
            const optarg = if (optind < argv.len and !std.mem.startsWith(u8, argv[optind], "-"))
                argv[optind]
            else
                "";
            switch (ch) {
                'b' => {
                    const value = parseIntArg(optarg) orelse {
                        errors += 1;
                        continue;
                    };
                    versions = value;
                    purge = false;
                    optind += 1;
                },
                'B' => {
                    const value = parseIntArg(optarg) orelse {
                        errors += 1;
                        continue;
                    };
                    versions = value;
                    purge = true;
                    optind += 1;
                },
                'c' => {
                    if (read_only_flag) {
                        errors += 1;
                    } else {
                        create_flag = true;
                    }
                },
                'h' => highlighting = true,
                'H' => highlighting = false,
                'i' => {
                    initialize = optarg;
                    optind += 1;
                },
                'I' => initialize = "",
                'm' => {
                    memory = optarg;
                    optind += 1;
                },
                'M' => memory = "",
                'o' => {
                    version_flag = true;
                    editor.FileData.OldCmds = true;
                },
                'O' => {
                    version_flag = true;
                    editor.FileData.OldCmds = false;
                },
                'r' => {
                    if (create_flag) {
                        errors += 1;
                    } else {
                        read_only_flag = true;
                    }
                },
                's' => {
                    const value = parseIntArg(optarg) orelse {
                        errors += 1;
                        continue;
                    };
                    space = value;
                    space_flag = true;
                    optind += 1;
                },
                't' => entab = true,
                'T' => entab = false,
                'u', '?' => usage_flag = true,
                'w' => {
                    const value = parseIntArg(optarg) orelse {
                        errors += 1;
                        continue;
                    };
                    if (value < 2 or value > 8) {
                        errors += 1;
                    } else {
                        tab_width = value;
                        optind += 1;
                    }
                },
                else => errors += 1,
            }
        }
    }

    if (usage_flag or errors > 0) {
        return .{
            .ok = false,
            .show_usage = true,
            .message = usageFor(parse_type),
        };
    }

    if (parse_type == .ParseCommand) {
        editor.FileData.Highlighting = highlighting;
        editor.FileData.Entab = entab;
        editor.FileData.Space = space;
        editor.FileData.Initial = initialize;
        editor.FileData.Purge = purge;
        editor.FileData.Versions = versions;
        editor.FileData.TabWidth = tab_width;
        editor.loadCommandTable(editor.FileData.OldCmds);
    } else if (create_flag or read_only_flag or initialize.len != 0 or space_flag or version_flag) {
        return .{
            .ok = false,
            .show_usage = true,
            .message = usageFor(parse_type),
        };
    }

    var files: [2][]const u8 = .{ "", "" };
    var file_count: usize = 0;
    while (optind < argv.len) : (optind += 1) {
        if (file_count >= files.len) {
            return fail("More than two files specified");
        }
        files[file_count] = argv[optind];
        file_count += 1;
    }

    if (file_count == 2) {
        check_input = true;
        if (parse_type == .ParseInput or parse_type == .ParseOutput or parse_type == .ParseExecute or create_flag or read_only_flag) {
            return fail("Only one file name can be specified");
        }
    }

    switch (parse_type) {
        .ParseCommand, .ParseEdit => {
            var input_name: []const u8 = "";
            if (file_count > 0) {
                input_name = files[0];
            } else if (memory.len > 0) {
                if (try sys_ops.readFilename(allocator, memory)) |remembered| {
                    if (sys_ops.fileExists(remembered)) {
                        input_name = remembered;
                        check_input = true;
                    } else if (parse_type == .ParseEdit) {
                        return fail(try std.fmt.allocPrint(allocator, "Error opening memory file ({s})", .{memory}));
                    }
                } else if (parse_type == .ParseEdit) {
                    return fail(try std.fmt.allocPrint(allocator, "Error opening memory file ({s})", .{memory}));
                }
            }

            if (input_name.len == 0) {
                if (parse_type == .ParseCommand) {
                    return .{ .ok = true };
                }
                return fail("No input file specified");
            }

            const output_name = if (file_count > 1) files[1] else input_name;
            if (read_only_flag) {
                input_out.* = (try openInputFile(editor, allocator, input_name)) orelse
                    return fail(try std.fmt.allocPrint(allocator, "Error opening ({s}) as input", .{input_name}));
            } else if (create_flag) {
                output_out.* = (try openOutputFile(editor, allocator, output_name, null, true, memory, entab, purge, versions)) orelse
                    return fail(try std.fmt.allocPrint(allocator, "Error opening ({s}) as output", .{output_name}));
            } else {
                input_out.* = try openInputFile(editor, allocator, input_name);
                if (input_out.* == null and (check_input or parse_type == .ParseEdit)) {
                    return fail(try std.fmt.allocPrint(allocator, "Error opening ({s}) as input", .{input_name}));
                }
                const related_name = if (input_out.*) |input| input.Filename else input_name;
                output_out.* = (try openOutputFile(editor, allocator, output_name, related_name, false, memory, entab, purge, versions)) orelse
                    return fail(try std.fmt.allocPrint(allocator, "Error opening ({s}) as output", .{output_name}));
            }
        },
        .ParseInput => {
            const input_name = if (file_count == 1)
                files[0]
            else if (memory.len > 0)
                (try sys_ops.readFilename(allocator, memory)) orelse
                    return fail(try std.fmt.allocPrint(allocator, "Error opening ({s}) as input", .{memory}))
            else
                return fail("No input file specified");
            input_out.* = (try openInputFile(editor, allocator, input_name)) orelse
                return fail(try std.fmt.allocPrint(allocator, "Error opening ({s}) as input", .{input_name}));
        },
        .ParseExecute => {
            if (file_count != 1) {
                return fail("No input file specified");
            }
            input_out.* = (try openInputFile(editor, allocator, files[0])) orelse
                return fail(try std.fmt.allocPrint(allocator, "Error opening ({s}) as input", .{files[0]}));
        },
        .ParseOutput => {
            const output_name = if (file_count == 1)
                files[0]
            else if (input_out.*) |input|
                input.Filename
            else
                "";
            if (output_name.len == 0) {
                return fail("No output file specified");
            }
            const related_name = if (input_out.*) |input| input.Filename else null;
            output_out.* = (try openOutputFile(editor, allocator, output_name, related_name, false, memory, entab, purge, versions)) orelse
                return fail(try std.fmt.allocPrint(allocator, "Error opening ({s}) as output", .{output_name}));
        },
        .ParseStdin => unreachable,
    }

    return .{ .ok = true };
}

fn tmpPath(allocator: std.mem.Allocator, tmp_dir: *std.testing.TmpDir, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/{s}", .{ tmp_dir.sub_path, name });
}

test "filesys parser applies command flags and opens command/edit files" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const input_path = try tmpPath(allocator, &tmp_dir, "input.txt");
    const output_path = try tmpPath(allocator, &tmp_dir, "output.txt");
    try tmp_dir.dir.writeFile(.{ .sub_path = "input.txt", .data = "alpha\n" });

    var input: ?*types.FileObject = null;
    var output: ?*types.FileObject = null;
    const argv = [_][]const u8{ "-B", "3", "-t", "-w", "4", "-O", input_path, output_path };
    const result = try FileCreateOpen(&editor, allocator, &argv, .ParseCommand, &input, &output);
    try std.testing.expect(result.ok);
    try std.testing.expect(!editor.FileData.OldCmds);
    try std.testing.expect(editor.FileData.Entab);
    try std.testing.expect(editor.FileData.Purge);
    try std.testing.expectEqual(@as(isize, 3), editor.FileData.Versions);
    try std.testing.expectEqual(@as(isize, 4), editor.FileData.TabWidth);
    try std.testing.expect(input != null);
    try std.testing.expect(output != null);
}

test "filesys parser can use a memory file for command input" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const input_path = try tmpPath(allocator, &tmp_dir, "input.txt");
    const memory_path = try tmpPath(allocator, &tmp_dir, "memory.txt");
    try tmp_dir.dir.writeFile(.{ .sub_path = "input.txt", .data = "alpha\n" });
    try std.testing.expect(try sys_ops.writeFilename(memory_path, input_path));

    var input: ?*types.FileObject = null;
    var output: ?*types.FileObject = null;
    const argv = [_][]const u8{ "-m", memory_path };
    const result = try FileCreateOpen(&editor, allocator, &argv, .ParseCommand, &input, &output);
    try std.testing.expect(result.ok);
    try std.testing.expect(input != null);
    try std.testing.expect(output != null);
}

test "filesys parser reports usage for conflicting create and readonly flags" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var input: ?*types.FileObject = null;
    var output: ?*types.FileObject = null;
    const argv = [_][]const u8{ "-c", "-r" };
    const result = try FileCreateOpen(&editor, allocator, &argv, .ParseCommand, &input, &output);
    try std.testing.expect(!result.ok);
    try std.testing.expect(result.show_usage);
}
