const std = @import("std");
const batch_output = @import("../platform/batch_output.zig");
const code_ops = @import("../core/code.zig");
const defaults = @import("../core/defaults.zig");
const file_ops = @import("../core/file.zig");
const frame_ops = @import("../core/frame.zig");
const line_ops = @import("../core/line.zig");
const mark_ops = @import("../core/mark.zig");
const state = @import("../core/state.zig");
const types = @import("../core/types.zig");

const stdin_span_name = "L. Wittgenstein und Sohn.";

pub const Session = struct {
    current_frame: *types.FrameObject,
    special_frames: types.SpecialFrames,
};

fn configureBatchTerminal(editor: *state.Editor) void {
    editor.ludwig_mode = .ludwig_batch;
    editor.terminal_info = .{
        .name = "",
        .width = 80,
        .height = 4,
    };
    editor.screen.msg_row = editor.terminal_info.height + 1;
}

fn makeSpecialFrame(
    editor: *state.Editor,
    name: []const u8,
) !*types.FrameObject {
    const frame = (try frame_ops.frameEdit(editor, null, name)).?;
    frame.options.special_frame = true;
    return frame;
}

fn attachStartupFiles(
    editor: *state.Editor,
    current_frame: *types.FrameObject,
    input: ?*types.FileObject,
    output: ?*types.FileObject,
) void {
    if (input) |input_file| {
        editor.files[1] = input_file;
        editor.files_frames[1] = current_frame;
        current_frame.input_file = 1;
    }
    if (output) |output_file| {
        editor.files[2] = output_file;
        editor.files_frames[2] = current_frame;
        current_frame.output_file = 2;
    }
}

fn executeCommandFrameFile(
    editor: *state.Editor,
    current_frame: *types.FrameObject,
    special_frames: *types.SpecialFrames,
    file_name: []const u8,
) !code_ops.InterpretResult {
    const cmd_frame = special_frames.cmd orelse return error.MissingCommandFrame;
    const cmd_span = cmd_frame.span orelse return error.MissingCommandSpan;
    if (!try file_ops.loadBufferedFileIntoFrameByName(editor, cmd_frame, file_name)) {
        return .{ .frame = current_frame, .ok = false };
    }
    if (!try code_ops.codeCompile(editor, current_frame, cmd_span, true)) {
        return .{ .frame = current_frame, .ok = false };
    }
    return code_ops.codeInterpretFrame(
        editor,
        current_frame,
        special_frames,
        .lead_param_none,
        1,
        cmd_span.code.?,
        true,
    );
}

fn appendSourceLines(
    allocator: std.mem.Allocator,
    source: []const u8,
    lines: *std.ArrayList([]const u8),
) !void {
    var line_start: usize = 0;
    var index: usize = 0;
    while (index < source.len) : (index += 1) {
        const byte = source[index];
        if (byte != '\n' and byte != '\r') {
            continue;
        }

        try lines.append(allocator, source[line_start..index]);
        if (byte == '\r' and index + 1 < source.len and source[index + 1] == '\n') {
            index += 1;
        }
        line_start = index + 1;
    }

    if (line_start < source.len) {
        try lines.append(allocator, source[line_start..]);
    }

    if (lines.items.len == 0) {
        try lines.append(allocator, "");
    }
}

fn makeBatchCommandSpan(
    allocator: std.mem.Allocator,
    source: []const u8,
) !struct {
    fixture: line_ops.FrameFixture,
    span: *types.SpanObject,
} {
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(allocator);
    try appendSourceLines(allocator, source, &lines);

    const fixture = try line_ops.createContentFrame(allocator, lines.items);
    var mark_one: ?*types.MarkObject = null;
    var mark_two: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 1, &mark_one);
    const last = fixture.content_lines[fixture.content_lines.len - 1];
    try mark_ops.markCreate(allocator, last, last.used + 1, &mark_two);

    const span = try allocator.create(types.SpanObject);
    span.* = .{
        .name = stdin_span_name,
        .mark_one = mark_one,
        .mark_two = mark_two,
    };
    return .{
        .fixture = fixture,
        .span = span,
    };
}

pub fn startUp(
    editor: *state.Editor,
    input: ?*types.FileObject,
    output: ?*types.FileObject,
) !Session {
    defaults.setRegularTabStops(editor, editor.file_data.tab_width);
    configureBatchTerminal(editor);

    var special_frames: types.SpecialFrames = .{};
    special_frames.oops = try makeSpecialFrame(editor, "OOPS");
    special_frames.oops.?.space_limit = types.max_space;
    special_frames.oops.?.space_left = types.max_space - 50;
    special_frames.cmd = try makeSpecialFrame(editor, "COMMAND");
    special_frames.heap = try makeSpecialFrame(editor, "HEAP");

    var current_frame = (try frame_ops.frameEdit(editor, null, types.default_frame_name)).?;
    attachStartupFiles(editor, current_frame, input, output);

    if (current_frame.input_file != 0 and !try file_ops.filePage(editor, current_frame)) {
        return error.BatchStartupFailed;
    }

    if (editor.file_data.initial.len > 0) {
        const init_outcome = try executeCommandFrameFile(
            editor,
            current_frame,
            &special_frames,
            editor.file_data.initial,
        );
        current_frame = init_outcome.frame;
        if (!init_outcome.ok and editor.ludwig_mode == .ludwig_batch and editor.batch_output_enabled) {
            batch_output.printMessage(editor.io, "COMMAND FAILED");
        }
        editor.exit_abort = false;
    }

    return .{
        .current_frame = current_frame,
        .special_frames = special_frames,
    };
}

pub fn readStdinAlloc(io: std.Io, allocator: std.mem.Allocator) ![]u8 {
    var buf: [4096]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(io, &buf);
    return reader.interface.allocRemaining(
        allocator,
        .limited(types.max_space),
    ) catch |err| switch (err) {
        // Preserve the old readToEndAlloc behavior.
        error.StreamTooLong => error.FileTooBig,
        else => |e| e,
    };
}

pub fn runBatchCommands(
    editor: *state.Editor,
    session: *Session,
    source: []const u8,
) !bool {
    var ok = true;

    if (source.len > 0) {
        const command_span = try makeBatchCommandSpan(editor.allocator(), source);
        if (!try code_ops.codeCompile(editor, session.current_frame, command_span.span, true)) {
            ok = false;
            if (editor.ludwig_mode == .ludwig_batch and editor.batch_output_enabled) {
                batch_output.printMessage(editor.io, "Syntax error.");
            }
        } else {
            const outcome = try code_ops.codeInterpretFrame(
                editor,
                session.current_frame,
                &session.special_frames,
                .lead_param_none,
                1,
                command_span.span.code.?,
                true,
            );
            session.current_frame = outcome.frame;
            ok = outcome.ok;
            if (!ok and editor.ludwig_mode == .ludwig_batch and editor.batch_output_enabled) {
                batch_output.printMessage(editor.io, "COMMAND FAILED");
            }
        }
        editor.exit_abort = false;
        editor.tt_control_c = false;
    }

    if (!editor.quit_requested) {
        _ = try file_ops.quitCloseFiles(editor);
    } else {
        editor.quit_requested = false;
    }
    return ok;
}

fn tmpPath(allocator: std.mem.Allocator, tmp_dir: *std.testing.TmpDir, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/{s}", .{ tmp_dir.sub_path, name });
}

test "batch runtime can edit a file from stdin commands" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();
    const io = std.testing.io;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file_path = try tmpPath(allocator, &tmp_dir, "test_file");
    try tmp_dir.dir.writeFile(io, .{ .sub_path = "test_file", .data = "abc\n" });

    const filesys = @import("../platform/filesys.zig");
    const sys_ops = @import("../platform/sys.zig");

    var input: ?*types.FileObject = null;
    var output: ?*types.FileObject = null;
    const argv = [_][]const u8{ "-M", "-I", file_path };
    const parse = try filesys.fileCreateOpen(&editor, &argv, .parse_command, &input, &output);
    try std.testing.expect(parse.ok);
    editor.batch_output_enabled = false;

    var session = try startUp(&editor, input, output);
    try std.testing.expect(try runBatchCommands(&editor, &session, "i/x/"));

    const after = try sys_ops.readFileAlloc(io, allocator, file_path, types.max_space);
    try std.testing.expectEqualStrings("xabc\n", after);

    const backup = try tmpPath(allocator, &tmp_dir, "test_file~1");
    const backup_bytes = try sys_ops.readFileAlloc(io, allocator, backup, types.max_space);
    try std.testing.expectEqualStrings("abc\n", backup_bytes);
}
