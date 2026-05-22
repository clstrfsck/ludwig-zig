const std = @import("std");
const code_store = @import("code_store.zig");
const frame_ops = @import("frame.zig");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const interactive_io = @import("../platform/interactive_io.zig");
const state = @import("state.zig");
const text = @import("text.zig");
const types = @import("types.zig");

pub fn spanFind(
    editor: *state.Editor,
    span_name: []const u8,
    ptr: *?*types.SpanObject,
    prev: *?*types.SpanObject,
) !bool {
    prev.* = null;
    ptr.* = editor.first_span;
    if (ptr.* == null) {
        return false;
    }

    while (ptr.* != null and std.mem.order(u8, ptr.*.?.name, span_name) == .lt) {
        prev.* = ptr.*;
        ptr.* = ptr.*.?.f_link;
    }
    if (ptr.* != null and std.mem.eql(u8, ptr.*.?.name, span_name)) {
        if (ptr.*.?.frame) |frame| {
            try mark_ops.markCreate(editor.allocator(), frame.first_group.?.first_line.?, 1, &ptr.*.?.mark_one);
            try mark_ops.markCreate(editor.allocator(), frame.last_group.?.last_line.?, 1, &ptr.*.?.mark_two);
        }
        return true;
    }
    return false;
}

pub fn spanCreate(
    editor: *state.Editor,
    span_name: []const u8,
    first_mark: *types.MarkObject,
    last_mark: *types.MarkObject,
) !bool {
    var found: ?*types.SpanObject = null;
    var prev: ?*types.SpanObject = null;
    var mark_one: ?*types.MarkObject = null;
    var mark_two: ?*types.MarkObject = null;

    if (try spanFind(editor, span_name, &found, &prev)) {
        if (found.?.frame != null) {
            return false;
        }
        if (found.?.code != null) {
            code_store.codeDiscard(editor, &found.?.code);
        }
        mark_one = found.?.mark_one;
        mark_two = found.?.mark_two;
    } else {
        const span = try editor.allocator().create(types.SpanObject);
        span.* = .{
            .name = try editor.allocator().dupe(u8, span_name),
        };
        if (found) |next| {
            span.f_link = next;
            next.b_link = span;
        }
        if (prev) |previous| {
            span.b_link = previous;
            previous.f_link = span;
        } else {
            editor.first_span = span;
        }
        found = span;
    }

    try mark_ops.markCreate(editor.allocator(), first_mark.line, first_mark.col, &mark_one);
    try mark_ops.markCreate(editor.allocator(), last_mark.line, last_mark.col, &mark_two);

    const line_nr_first = line_ops.lineToNumber(mark_one.?.line);
    const line_nr_last = line_ops.lineToNumber(mark_two.?.line);
    found.?.frame = null;
    if (line_nr_first < line_nr_last or (line_nr_first == line_nr_last and mark_one.?.col < mark_two.?.col)) {
        found.?.mark_one = mark_one;
        found.?.mark_two = mark_two;
    } else {
        found.?.mark_one = mark_two;
        found.?.mark_two = mark_one;
    }
    return true;
}

pub fn spanDestroy(
    editor: *state.Editor,
    span_slot: *?*types.SpanObject,
) bool {
    if (span_slot.* == null) {
        return true;
    }
    const span = span_slot.*.?;
    if (span.frame != null) {
        return false;
    }
    if (span.code != null) {
        code_store.codeDiscard(editor, &span.code);
    }
    if (span.b_link) |back| {
        back.f_link = span.f_link;
    } else {
        editor.first_span = span.f_link;
    }
    if (span.f_link) |forward| {
        forward.b_link = span.b_link;
    }
    mark_ops.markDestroy(editor.allocator(), &span.mark_one);
    mark_ops.markDestroy(editor.allocator(), &span.mark_two);
    span_slot.* = null;
    return true;
}

fn renderSpanLine(allocator: std.mem.Allocator, span: *types.SpanObject) ![]const u8 {
    const mark_one = span.mark_one orelse return std.fmt.allocPrint(allocator, "{s} : ", .{span.name});
    const mark_two = span.mark_two orelse return std.fmt.allocPrint(allocator, "{s} : ", .{span.name});

    var continuation = mark_one.line != mark_two.line;
    var preview: []const u8 = "";
    if (mark_one.col <= mark_one.line.used and mark_one.line.str != null) {
        if (!continuation) {
            continuation = mark_two.col - mark_one.col > types.name_len;
            const to_copy = @min(mark_two.col - mark_one.col, types.name_len);
            if (to_copy > 0) {
                preview = mark_one.line.str.?.slice(mark_one.col, to_copy);
            }
        } else {
            const to_copy = @min(mark_one.line.used + 1 - mark_one.col, types.name_len);
            if (to_copy > 0) {
                preview = mark_one.line.str.?.slice(mark_one.col, to_copy);
            }
        }
    }

    return std.fmt.allocPrint(
        allocator,
        "{s} : {s}{s}",
        .{ span.name, preview, if (continuation) "..." else "" },
    );
}

fn appendFileLine(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    lines: *std.ArrayList([]const u8),
    label: []const u8,
    file_id: isize,
) !void {
    if (file_id <= 0 or file_id > types.max_files) {
        return;
    }
    const file = editor.files[@intCast(file_id)] orelse return;
    try lines.append(allocator, try std.fmt.allocPrint(allocator, "  {s}: {s}", .{ label, file.filename }));
}

fn replaceReportFrame(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    lines: []const []const u8,
) !bool {
    const span = frame.span orelse return false;
    const mark_one = span.mark_one orelse return false;
    const mark_two = span.mark_two orelse return false;
    if (!try text.textRemove(allocator, mark_one, mark_two)) {
        return false;
    }

    const sentinel = frame.last_group.?.last_line.?;
    if (lines.len > 0) {
        const range = try line_ops.linesCreate(allocator, lines.len);
        try line_ops.linesInject(allocator, range.first, range.last, sentinel);

        var line = range.first;
        for (lines, 0..) |content, index| {
            if (content.len > 0) {
                try line_ops.lineChangeLength(allocator, line, @intCast(content.len));
                try line_ops.setLineContent(line, content);
            } else {
                line.used = 0;
            }
            if (index + 1 < lines.len) {
                line = line.f_link.?;
            }
        }
    }

    const first_line = frame.first_group.?.first_line.?;
    try mark_ops.markCreate(allocator, first_line, 1, &span.mark_one);
    try mark_ops.markCreate(allocator, frame.last_group.?.last_line.?, 1, &span.mark_two);
    try mark_ops.markCreate(allocator, first_line, 1, &frame.dot);
    mark_ops.markDestroy(allocator, &frame.marks[types.mark_equals]);
    mark_ops.markDestroy(allocator, &frame.marks[types.mark_modified]);
    frame.text_modified = false;
    return true;
}

fn printBatchScreenHome(writer: *std.Io.Writer) void {
    writer.print("\n\n", .{}) catch {};
}

fn printBatchSpanIndex(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
) !void {
    var stdout_buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writerStreaming(editor.io, &stdout_buf);
    var writer = &file_writer.interface;
    defer writer.flush() catch {};

    const page_height = @max(@as(isize, 1), editor.terminal_info.height);

    printBatchScreenHome(writer);
    try writer.print("\nSpans\n=====\n", .{});

    var line_count: isize = 3;
    var have_spans = false;
    var span = editor.first_span;
    while (span) |this_span| : (span = this_span.f_link) {
        if (this_span.frame == null) {
            have_spans = true;
            if (line_count > page_height - 2) {
                printBatchScreenHome(writer);
                try writer.print("\nSpans\n=====\n", .{});
                line_count = 3;
            }
            try writer.print("{s}\n", .{try renderSpanLine(allocator, this_span)});
            line_count += 1;
        }
    }
    if (!have_spans) {
        try writer.print("          <none>\n", .{});
        line_count += 1;
    }

    var first_time = true;
    const old_count = line_count;
    line_count = page_height;
    span = editor.first_span;
    while (span) |this_span| : (span = this_span.f_link) {
        if (this_span.frame) |frame| {
            if (line_count > page_height - 2) {
                if (!first_time) {
                    printBatchScreenHome(writer);
                }
                try writer.print("\nFrames\n======\n", .{});
                if (first_time) {
                    line_count = old_count + 3;
                    first_time = false;
                } else {
                    line_count = 3;
                }
            }

            try writer.print("{s}\n", .{this_span.name});
            line_count += 1;
            if (frame.input_file != 0 and editor.files[@intCast(frame.input_file)] != null) {
                try writer.print("  Input:  {s}\n", .{editor.files[@intCast(frame.input_file)].?.filename});
                line_count += 1;
            }
            if (frame.output_file != 0 and editor.files[@intCast(frame.output_file)] != null) {
                try writer.print("  Output: {s}\n", .{editor.files[@intCast(frame.output_file)].?.filename});
                line_count += 1;
            }
        }
    }
}

fn flushInteractiveSpanPage(
    allocator: std.mem.Allocator,
    page_lines: *std.ArrayList([]const u8),
) !void {
    if (page_lines.items.len == 0) {
        return;
    }
    try interactive_io.showTemporaryReport(allocator, page_lines.items);
    page_lines.clearRetainingCapacity();
}

fn startInteractiveSpanSection(
    allocator: std.mem.Allocator,
    page_lines: *std.ArrayList([]const u8),
    page_height: usize,
    header_lines: []const []const u8,
) !void {
    if (page_lines.items.len > 0 and page_lines.items.len + header_lines.len > page_height) {
        try flushInteractiveSpanPage(allocator, page_lines);
    }
    for (header_lines) |line| {
        try page_lines.append(allocator, line);
    }
}

fn ensureInteractiveSpanItemSpace(
    allocator: std.mem.Allocator,
    page_lines: *std.ArrayList([]const u8),
    page_height: usize,
    item_lines: usize,
    header_lines: []const []const u8,
) !void {
    if (page_lines.items.len > 0 and page_lines.items.len + item_lines > page_height) {
        try flushInteractiveSpanPage(allocator, page_lines);
        for (header_lines) |line| {
            try page_lines.append(allocator, line);
        }
    }
}

fn showInteractiveSpanIndex(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
) !void {
    const page_height: usize = @intCast(@max(@as(isize, 1), editor.terminal_info.height - 1));
    const spans_header = [_][]const u8{ "Spans", "=====" };
    const frames_header = [_][]const u8{ "", "Frames", "======" };

    var page_lines: std.ArrayList([]const u8) = .empty;
    defer page_lines.deinit(allocator);

    try startInteractiveSpanSection(allocator, &page_lines, page_height, &spans_header);

    var have_spans = false;
    var span = editor.first_span;
    while (span) |this_span| : (span = this_span.f_link) {
        if (this_span.frame == null) {
            have_spans = true;
            try ensureInteractiveSpanItemSpace(allocator, &page_lines, page_height, 1, &spans_header);
            try page_lines.append(allocator, try renderSpanLine(allocator, this_span));
        }
    }
    if (!have_spans) {
        try ensureInteractiveSpanItemSpace(allocator, &page_lines, page_height, 1, &spans_header);
        try page_lines.append(allocator, "          <none>");
    }

    var have_frames = false;
    span = editor.first_span;
    while (span) |this_span| : (span = this_span.f_link) {
        if (this_span.frame) |frame| {
            const file_lines: usize =
                (if (frame.input_file != 0 and editor.files[@intCast(frame.input_file)] != null) @as(usize, 1) else 0) +
                (if (frame.output_file != 0 and editor.files[@intCast(frame.output_file)] != null) @as(usize, 1) else 0);
            const item_lines = 1 + file_lines;
            if (!have_frames) {
                try startInteractiveSpanSection(allocator, &page_lines, page_height, &frames_header);
                have_frames = true;
            }
            try ensureInteractiveSpanItemSpace(allocator, &page_lines, page_height, item_lines, &frames_header);
            try page_lines.append(allocator, this_span.name);
            try appendFileLine(editor, allocator, &page_lines, "Input", frame.input_file);
            try appendFileLine(editor, allocator, &page_lines, "Output", frame.output_file);
        }
    }

    try flushInteractiveSpanPage(allocator, &page_lines);
}

pub fn spanIndex(
    editor: *state.Editor,
    report_frame: *types.FrameObject,
) !bool {
    var arena = std.heap.ArenaAllocator.init(editor.allocator());
    defer arena.deinit();
    const temp_allocator = arena.allocator();

    var lines: std.ArrayList([]const u8) = .empty;
    try lines.append(temp_allocator, "Spans");
    try lines.append(temp_allocator, "=====");

    var have_spans = false;
    var span = editor.first_span;
    while (span) |this_span| : (span = this_span.f_link) {
        if (this_span.frame == null) {
            have_spans = true;
            try lines.append(temp_allocator, try renderSpanLine(temp_allocator, this_span));
        }
    }
    if (!have_spans) {
        try lines.append(temp_allocator, "          <none>");
    }

    var have_frames = false;
    span = editor.first_span;
    while (span) |this_span| : (span = this_span.f_link) {
        if (this_span.frame) |frame| {
            if (!have_frames) {
                have_frames = true;
                try lines.append(temp_allocator, "");
                try lines.append(temp_allocator, "Frames");
                try lines.append(temp_allocator, "======");
            }
            try lines.append(temp_allocator, this_span.name);
            try appendFileLine(editor, temp_allocator, &lines, "Input", frame.input_file);
            try appendFileLine(editor, temp_allocator, &lines, "Output", frame.output_file);
        }
    }

    const ok = try replaceReportFrame(editor.allocator(), report_frame, lines.items);
    if (!ok) {
        return false;
    }

    switch (editor.ludwig_mode) {
        .ludwig_screen => try showInteractiveSpanIndex(editor, temp_allocator),
        .ludwig_batch, .ludwig_hardcopy => if (editor.batch_output_enabled) {
            try printBatchSpanIndex(editor, temp_allocator);
        },
    }
    return true;
}

fn expectFrameLines(frame: *types.FrameObject, expected: []const []const u8) !void {
    const sentinel = frame.last_group.?.last_line.?;
    var line = frame.first_group.?.first_line.?;
    for (expected) |content| {
        try std.testing.expect(line != sentinel);
        try std.testing.expectEqualStrings(content, line_ops.getLineContent(line));
        line = line.f_link.?;
    }
    try std.testing.expect(line == sentinel);
}

test "span create find and destroy maintain ordering" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();

    const fixture = try line_ops.setupLinkedLines(allocator, 3);
    var first_mark: ?*types.MarkObject = null;
    var last_mark: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 1, &first_mark);
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 10, &last_mark);

    try std.testing.expect(try spanCreate(&editor, "charlie", first_mark.?, last_mark.?));
    try std.testing.expect(try spanCreate(&editor, "alpha", first_mark.?, last_mark.?));
    try std.testing.expect(try spanCreate(&editor, "bravo", first_mark.?, last_mark.?));
    try std.testing.expectEqualStrings("alpha", editor.first_span.?.name);
    try std.testing.expectEqualStrings("bravo", editor.first_span.?.f_link.?.name);
    try std.testing.expectEqualStrings("charlie", editor.first_span.?.f_link.?.f_link.?.name);

    var found: ?*types.SpanObject = null;
    var prev: ?*types.SpanObject = null;
    try std.testing.expect(try spanFind(&editor, "bravo", &found, &prev));
    try std.testing.expect(found == editor.first_span.?.f_link);
    try std.testing.expect(prev == editor.first_span);

    try std.testing.expect(spanDestroy(&editor, &found));
    try std.testing.expect(editor.first_span.?.f_link != null);
    try std.testing.expectEqualStrings("charlie", editor.first_span.?.f_link.?.name);
}

test "span create normalizes reversed marks and supports redefine" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();

    const fixture = try line_ops.setupLinkedLines(allocator, 2);
    var mark1: ?*types.MarkObject = null;
    var mark2: ?*types.MarkObject = null;
    var mark3: ?*types.MarkObject = null;
    var mark4: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 15, &mark1);
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 5, &mark2);
    try std.testing.expect(try spanCreate(&editor, "ordered", mark1.?, mark2.?));
    try std.testing.expectEqual(@as(isize, 5), editor.first_span.?.mark_one.?.col);
    try std.testing.expectEqual(@as(isize, 15), editor.first_span.?.mark_two.?.col);

    try mark_ops.markCreate(allocator, fixture.content_lines[0], 7, &mark3);
    try mark_ops.markCreate(allocator, fixture.content_lines[1], 2, &mark4);
    try std.testing.expect(try spanCreate(&editor, "ordered", mark3.?, mark4.?));
    try std.testing.expect(editor.first_span.?.mark_one.?.line == fixture.content_lines[0]);
    try std.testing.expect(editor.first_span.?.mark_two.?.line == fixture.content_lines[1]);
}

test "span find refreshes frame-backed spans" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();

    const fixture = try line_ops.setupLinkedLines(allocator, 2);
    const frame_span = try allocator.create(types.SpanObject);
    frame_span.* = .{
        .name = "frame",
        .frame = fixture.frame,
    };
    editor.first_span = frame_span;

    var found: ?*types.SpanObject = null;
    var prev: ?*types.SpanObject = null;
    try std.testing.expect(try spanFind(&editor, "frame", &found, &prev));
    try std.testing.expect(found.?.mark_one != null);
    try std.testing.expect(found.?.mark_two != null);
    try std.testing.expect(found.?.mark_one.?.line == fixture.frame.first_group.?.first_line.?);
    try std.testing.expect(found.?.mark_two.?.line == fixture.frame.last_group.?.last_line.?);
}

test "span index writes a non-interactive report into the target frame" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();

    const source = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "abcdefghijklmnopqrstuvwxyz0123456789",
        "omega",
    });
    var mark_one: ?*types.MarkObject = null;
    var mark_two: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, source.content_lines[0], 2, &mark_one);
    try mark_ops.markCreate(allocator, source.content_lines[1], 2, &mark_two);
    try std.testing.expect(try spanCreate(&editor, "NOTE", mark_one.?, mark_two.?));

    const command = (try frame_ops.frameEdit(&editor, source.frame, "COMMAND")).?;
    _ = (try frame_ops.frameEdit(&editor, source.frame, "HEAP")).?;
    const oops = (try frame_ops.frameEdit(&editor, source.frame, "OOPS")).?;

    const input_file = try allocator.create(types.FileObject);
    input_file.* = .{ .filename = "input.txt" };
    editor.files[1] = input_file;
    command.input_file = 1;

    const output_file = try allocator.create(types.FileObject);
    output_file.* = .{ .filename = "output.txt" };
    editor.files[2] = output_file;
    command.output_file = 2;

    try std.testing.expect(try spanIndex(&editor, oops));
    try expectFrameLines(oops, &[_][]const u8{
        "Spans",
        "=====",
        "NOTE : bcdefghijklmnopqrstuvwxyz012345...",
        "",
        "Frames",
        "======",
        "COMMAND",
        "  Input: input.txt",
        "  Output: output.txt",
        "HEAP",
        "OOPS",
    });
    try std.testing.expect(oops.dot.?.line == oops.first_group.?.first_line.?);
    try std.testing.expect(oops.span.?.mark_one.?.line == oops.first_group.?.first_line.?);
    try std.testing.expect(oops.span.?.mark_two.?.line == oops.last_group.?.last_line.?);
}
