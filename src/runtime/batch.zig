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
    editor.LudwigMode = .LudwigBatch;
    editor.TerminalInfo = .{
        .Name = "",
        .Width = 80,
        .Height = 4,
    };
    editor.Screen.MsgRow = editor.TerminalInfo.Height + 1;
}

fn makeSpecialFrame(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    name: []const u8,
) !*types.FrameObject {
    const frame = (try frame_ops.FrameEdit(editor, allocator, null, name)).?;
    frame.Options.specialFrame = true;
    return frame;
}

fn attachStartupFiles(
    editor: *state.Editor,
    current_frame: *types.FrameObject,
    input: ?*types.FileObject,
    output: ?*types.FileObject,
) void {
    if (input) |input_file| {
        editor.Files[1] = input_file;
        editor.FilesFrames[1] = current_frame;
        current_frame.InputFile = 1;
    }
    if (output) |output_file| {
        editor.Files[2] = output_file;
        editor.FilesFrames[2] = current_frame;
        current_frame.OutputFile = 2;
    }
}

fn executeCommandFrameFile(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    current_frame: *types.FrameObject,
    special_frames: *types.SpecialFrames,
    file_name: []const u8,
) !code_ops.InterpretResult {
    const cmd_frame = special_frames.Cmd orelse return error.MissingCommandFrame;
    const cmd_span = cmd_frame.Span orelse return error.MissingCommandSpan;
    if (!try file_ops.loadBufferedFileIntoFrameByName(editor, allocator, cmd_frame, file_name)) {
        return .{ .frame = current_frame, .ok = false };
    }
    if (!try code_ops.CodeCompile(editor, allocator, current_frame, cmd_span, true)) {
        return .{ .frame = current_frame, .ok = false };
    }
    return code_ops.CodeInterpretFrame(
        editor,
        allocator,
        current_frame,
        special_frames,
        .LeadParamNone,
        1,
        cmd_span.Code.?,
        true,
    );
}

fn appendSourceLines(
    allocator: std.mem.Allocator,
    source: []const u8,
    lines: *std.ArrayListUnmanaged([]const u8),
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
    var lines: std.ArrayListUnmanaged([]const u8) = .{};
    defer lines.deinit(allocator);
    try appendSourceLines(allocator, source, &lines);

    const fixture = try line_ops.createContentFrame(allocator, lines.items);
    var mark_one: ?*types.MarkObject = null;
    var mark_two: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 1, &mark_one);
    const last = fixture.content_lines[fixture.content_lines.len - 1];
    try mark_ops.markCreate(allocator, last, last.Used + 1, &mark_two);

    const span = try allocator.create(types.SpanObject);
    span.* = .{
        .Name = stdin_span_name,
        .MarkOne = mark_one,
        .MarkTwo = mark_two,
    };
    return .{
        .fixture = fixture,
        .span = span,
    };
}

pub fn startUp(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    input: ?*types.FileObject,
    output: ?*types.FileObject,
) !Session {
    defaults.setRegularTabStops(editor, editor.FileData.TabWidth);
    configureBatchTerminal(editor);

    var special_frames: types.SpecialFrames = .{};
    special_frames.Oops = try makeSpecialFrame(editor, allocator, "OOPS");
    special_frames.Oops.?.SpaceLimit = types.MaxSpace;
    special_frames.Oops.?.SpaceLeft = types.MaxSpace - 50;
    special_frames.Cmd = try makeSpecialFrame(editor, allocator, "COMMAND");
    special_frames.Heap = try makeSpecialFrame(editor, allocator, "HEAP");

    var current_frame = (try frame_ops.FrameEdit(editor, allocator, null, types.DefaultFrameName)).?;
    attachStartupFiles(editor, current_frame, input, output);

    if (current_frame.InputFile != 0 and !try file_ops.filePage(editor, allocator, current_frame)) {
        return error.BatchStartupFailed;
    }

    if (editor.FileData.Initial.len > 0) {
        const init_outcome = try executeCommandFrameFile(
            editor,
            allocator,
            current_frame,
            &special_frames,
            editor.FileData.Initial,
        );
        current_frame = init_outcome.frame;
        if (!init_outcome.ok and editor.LudwigMode == .LudwigBatch and editor.BatchOutputEnabled) {
            batch_output.printMessage("COMMAND FAILED");
        }
        editor.ExitAbort = false;
    }

    return .{
        .current_frame = current_frame,
        .special_frames = special_frames,
    };
}

pub fn readStdinAlloc(allocator: std.mem.Allocator) ![]u8 {
    return std.fs.File.stdin().readToEndAlloc(allocator, types.MaxSpace);
}

pub fn runBatchCommands(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    session: *Session,
    source: []const u8,
) !bool {
    var ok = true;

    if (source.len > 0) {
        const command_span = try makeBatchCommandSpan(allocator, source);
        if (!try code_ops.CodeCompile(editor, allocator, session.current_frame, command_span.span, true)) {
            ok = false;
            if (editor.LudwigMode == .LudwigBatch and editor.BatchOutputEnabled) {
                batch_output.printMessage("Syntax error.");
            }
        } else {
            const outcome = try code_ops.CodeInterpretFrame(
                editor,
                allocator,
                session.current_frame,
                &session.special_frames,
                .LeadParamNone,
                1,
                command_span.span.Code.?,
                true,
            );
            session.current_frame = outcome.frame;
            ok = outcome.ok;
            if (!ok and editor.LudwigMode == .LudwigBatch and editor.BatchOutputEnabled) {
                batch_output.printMessage("COMMAND FAILED");
            }
        }
        editor.ExitAbort = false;
        editor.TtControlC = false;
    }

    if (!editor.QuitRequested) {
        _ = try file_ops.quitCloseFiles(editor, allocator);
    } else {
        editor.QuitRequested = false;
    }
    return ok;
}

fn tmpPath(allocator: std.mem.Allocator, tmp_dir: *std.testing.TmpDir, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/{s}", .{ tmp_dir.sub_path, name });
}

test "batch runtime can edit a file from stdin commands" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file_path = try tmpPath(allocator, &tmp_dir, "test_file");
    try tmp_dir.dir.writeFile(.{ .sub_path = "test_file", .data = "abc\n" });

    const filesys = @import("../platform/filesys.zig");
    const sys_ops = @import("../platform/sys.zig");

    var input: ?*types.FileObject = null;
    var output: ?*types.FileObject = null;
    const argv = [_][]const u8{ "-M", "-I", file_path };
    const parse = try filesys.fileCreateOpen(&editor, allocator, &argv, .ParseCommand, &input, &output);
    try std.testing.expect(parse.ok);
    editor.BatchOutputEnabled = false;

    var session = try startUp(&editor, allocator, input, output);
    try std.testing.expect(try runBatchCommands(&editor, allocator, &session, "i/x/"));

    const after = try sys_ops.readFileAlloc(allocator, file_path, types.MaxSpace);
    try std.testing.expectEqualStrings("xabc\n", after);

    const backup = try tmpPath(allocator, &tmp_dir, "test_file~1");
    const backup_bytes = try sys_ops.readFileAlloc(allocator, backup, types.MaxSpace);
    try std.testing.expectEqualStrings("abc\n", backup_bytes);
}
