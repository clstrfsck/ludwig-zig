const std = @import("std");
const code_store = @import("code_store.zig");
const frame_ops = @import("frame.zig");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const interactive_io = @import("../platform/interactive_io.zig");
const state = @import("state.zig");
const text = @import("text.zig");
const types = @import("types.zig");

pub fn SpanFind(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    span_name: []const u8,
    ptr: *?*types.SpanObject,
    prev: *?*types.SpanObject,
) !bool {
    prev.* = null;
    ptr.* = editor.FirstSpan;
    if (ptr.* == null) {
        return false;
    }

    while (ptr.* != null and std.mem.order(u8, ptr.*.?.Name, span_name) == .lt) {
        prev.* = ptr.*;
        ptr.* = ptr.*.?.FLink;
    }
    if (ptr.* != null and std.mem.eql(u8, ptr.*.?.Name, span_name)) {
        if (ptr.*.?.Frame) |frame| {
            try mark_ops.markCreate(allocator, frame.FirstGroup.?.FirstLine.?, 1, &ptr.*.?.MarkOne);
            try mark_ops.markCreate(allocator, frame.LastGroup.?.LastLine.?, 1, &ptr.*.?.MarkTwo);
        }
        return true;
    }
    return false;
}

pub fn SpanCreate(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    span_name: []const u8,
    first_mark: *types.MarkObject,
    last_mark: *types.MarkObject,
) !bool {
    var found: ?*types.SpanObject = null;
    var prev: ?*types.SpanObject = null;
    var mark_one: ?*types.MarkObject = null;
    var mark_two: ?*types.MarkObject = null;

    if (try SpanFind(editor, allocator, span_name, &found, &prev)) {
        if (found.?.Frame != null) {
            return false;
        }
        if (found.?.Code != null) {
            code_store.codeDiscard(editor, &found.?.Code);
        }
        mark_one = found.?.MarkOne;
        mark_two = found.?.MarkTwo;
    } else {
        const span = try allocator.create(types.SpanObject);
        span.* = .{
            .Name = try allocator.dupe(u8, span_name),
        };
        if (found) |next| {
            span.FLink = next;
            next.BLink = span;
        }
        if (prev) |previous| {
            span.BLink = previous;
            previous.FLink = span;
        } else {
            editor.FirstSpan = span;
        }
        found = span;
    }

    try mark_ops.markCreate(allocator, first_mark.Line, first_mark.Col, &mark_one);
    try mark_ops.markCreate(allocator, last_mark.Line, last_mark.Col, &mark_two);

    const line_nr_first = line_ops.lineToNumber(mark_one.?.Line);
    const line_nr_last = line_ops.lineToNumber(mark_two.?.Line);
    found.?.Frame = null;
    if (line_nr_first < line_nr_last or (line_nr_first == line_nr_last and mark_one.?.Col < mark_two.?.Col)) {
        found.?.MarkOne = mark_one;
        found.?.MarkTwo = mark_two;
    } else {
        found.?.MarkOne = mark_two;
        found.?.MarkTwo = mark_one;
    }
    return true;
}

pub fn SpanDestroy(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    span_slot: *?*types.SpanObject,
) bool {
    if (span_slot.* == null) {
        return true;
    }
    const span = span_slot.*.?;
    if (span.Frame != null) {
        return false;
    }
    if (span.Code != null) {
        code_store.codeDiscard(editor, &span.Code);
    }
    if (span.BLink) |back| {
        back.FLink = span.FLink;
    } else {
        editor.FirstSpan = span.FLink;
    }
    if (span.FLink) |forward| {
        forward.BLink = span.BLink;
    }
    mark_ops.markDestroy(allocator, &span.MarkOne);
    mark_ops.markDestroy(allocator, &span.MarkTwo);
    span_slot.* = null;
    return true;
}

fn renderSpanLine(allocator: std.mem.Allocator, span: *types.SpanObject) ![]const u8 {
    const mark_one = span.MarkOne orelse return std.fmt.allocPrint(allocator, "{s} : ", .{span.Name});
    const mark_two = span.MarkTwo orelse return std.fmt.allocPrint(allocator, "{s} : ", .{span.Name});

    var continuation = mark_one.Line != mark_two.Line;
    var preview: []const u8 = "";
    if (mark_one.Col <= mark_one.Line.Used and mark_one.Line.Str != null) {
        if (!continuation) {
            continuation = mark_two.Col - mark_one.Col > types.NameLen;
            const to_copy = @min(mark_two.Col - mark_one.Col, types.NameLen);
            if (to_copy > 0) {
                preview = mark_one.Line.Str.?.slice(mark_one.Col, to_copy);
            }
        } else {
            const to_copy = @min(mark_one.Line.Used + 1 - mark_one.Col, types.NameLen);
            if (to_copy > 0) {
                preview = mark_one.Line.Str.?.slice(mark_one.Col, to_copy);
            }
        }
    }

    return std.fmt.allocPrint(
        allocator,
        "{s} : {s}{s}",
        .{ span.Name, preview, if (continuation) "..." else "" },
    );
}

fn appendFileLine(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    lines: *std.ArrayListUnmanaged([]const u8),
    label: []const u8,
    file_id: isize,
) !void {
    if (file_id <= 0 or file_id > types.MaxFiles) {
        return;
    }
    const file = editor.Files[@intCast(file_id)] orelse return;
    try lines.append(allocator, try std.fmt.allocPrint(allocator, "  {s}: {s}", .{ label, file.Filename }));
}

fn replaceReportFrame(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    lines: []const []const u8,
) !bool {
    const span = frame.Span orelse return false;
    const mark_one = span.MarkOne orelse return false;
    const mark_two = span.MarkTwo orelse return false;
    if (!try text.TextRemove(allocator, mark_one, mark_two)) {
        return false;
    }

    const sentinel = frame.LastGroup.?.LastLine.?;
    if (lines.len > 0) {
        const range = try line_ops.linesCreate(allocator, lines.len);
        try line_ops.linesInject(allocator, range.first, range.last, sentinel);

        var line = range.first;
        for (lines, 0..) |content, index| {
            if (content.len > 0) {
                try line_ops.lineChangeLength(allocator, line, @intCast(content.len));
                try line_ops.setLineContent(line, content);
            } else {
                line.Used = 0;
            }
            if (index + 1 < lines.len) {
                line = line.FLink.?;
            }
        }
    }

    const first_line = frame.FirstGroup.?.FirstLine.?;
    try mark_ops.markCreate(allocator, first_line, 1, &span.MarkOne);
    try mark_ops.markCreate(allocator, frame.LastGroup.?.LastLine.?, 1, &span.MarkTwo);
    try mark_ops.markCreate(allocator, first_line, 1, &frame.Dot);
    mark_ops.markDestroy(allocator, &frame.Marks[types.MarkEquals]);
    mark_ops.markDestroy(allocator, &frame.Marks[types.MarkModified]);
    frame.TextModified = false;
    return true;
}

fn printBatchScreenHome() void {
    std.fs.File.stdout().deprecatedWriter().print("\n\n", .{}) catch {};
}

fn printBatchSpanIndex(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
) !void {
    const writer = std.fs.File.stdout().deprecatedWriter();
    const page_height = @max(@as(isize, 1), editor.TerminalInfo.Height);

    printBatchScreenHome();
    try writer.print("\nSpans\n=====\n", .{});

    var line_count: isize = 3;
    var have_spans = false;
    var span = editor.FirstSpan;
    while (span) |this_span| : (span = this_span.FLink) {
        if (this_span.Frame == null) {
            have_spans = true;
            if (line_count > page_height - 2) {
                printBatchScreenHome();
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
    span = editor.FirstSpan;
    while (span) |this_span| : (span = this_span.FLink) {
        if (this_span.Frame) |frame| {
            if (line_count > page_height - 2) {
                if (!first_time) {
                    printBatchScreenHome();
                }
                try writer.print("\nFrames\n======\n", .{});
                if (first_time) {
                    line_count = old_count + 3;
                    first_time = false;
                } else {
                    line_count = 3;
                }
            }

            try writer.print("{s}\n", .{this_span.Name});
            line_count += 1;
            if (frame.InputFile != 0 and editor.Files[@intCast(frame.InputFile)] != null) {
                try writer.print("  Input:  {s}\n", .{editor.Files[@intCast(frame.InputFile)].?.Filename});
                line_count += 1;
            }
            if (frame.OutputFile != 0 and editor.Files[@intCast(frame.OutputFile)] != null) {
                try writer.print("  Output: {s}\n", .{editor.Files[@intCast(frame.OutputFile)].?.Filename});
                line_count += 1;
            }
        }
    }
}

fn flushInteractiveSpanPage(
    allocator: std.mem.Allocator,
    page_lines: *std.ArrayListUnmanaged([]const u8),
) !void {
    if (page_lines.items.len == 0) {
        return;
    }
    try interactive_io.showTemporaryReport(allocator, page_lines.items);
    page_lines.clearRetainingCapacity();
}

fn startInteractiveSpanSection(
    allocator: std.mem.Allocator,
    page_lines: *std.ArrayListUnmanaged([]const u8),
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
    page_lines: *std.ArrayListUnmanaged([]const u8),
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
    const page_height: usize = @intCast(@max(@as(isize, 1), editor.TerminalInfo.Height - 1));
    const spans_header = [_][]const u8{ "Spans", "=====" };
    const frames_header = [_][]const u8{ "", "Frames", "======" };

    var page_lines: std.ArrayListUnmanaged([]const u8) = .{};
    defer page_lines.deinit(allocator);

    try startInteractiveSpanSection(allocator, &page_lines, page_height, &spans_header);

    var have_spans = false;
    var span = editor.FirstSpan;
    while (span) |this_span| : (span = this_span.FLink) {
        if (this_span.Frame == null) {
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
    span = editor.FirstSpan;
    while (span) |this_span| : (span = this_span.FLink) {
        if (this_span.Frame) |frame| {
            const file_lines: usize =
                (if (frame.InputFile != 0 and editor.Files[@intCast(frame.InputFile)] != null) @as(usize, 1) else 0) +
                (if (frame.OutputFile != 0 and editor.Files[@intCast(frame.OutputFile)] != null) @as(usize, 1) else 0);
            const item_lines = 1 + file_lines;
            if (!have_frames) {
                try startInteractiveSpanSection(allocator, &page_lines, page_height, &frames_header);
                have_frames = true;
            }
            try ensureInteractiveSpanItemSpace(allocator, &page_lines, page_height, item_lines, &frames_header);
            try page_lines.append(allocator, this_span.Name);
            try appendFileLine(editor, allocator, &page_lines, "Input", frame.InputFile);
            try appendFileLine(editor, allocator, &page_lines, "Output", frame.OutputFile);
        }
    }

    try flushInteractiveSpanPage(allocator, &page_lines);
}

pub fn SpanIndex(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    report_frame: *types.FrameObject,
) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();

    var lines: std.ArrayListUnmanaged([]const u8) = .{};
    try lines.append(temp_allocator, "Spans");
    try lines.append(temp_allocator, "=====");

    var have_spans = false;
    var span = editor.FirstSpan;
    while (span) |this_span| : (span = this_span.FLink) {
        if (this_span.Frame == null) {
            have_spans = true;
            try lines.append(temp_allocator, try renderSpanLine(temp_allocator, this_span));
        }
    }
    if (!have_spans) {
        try lines.append(temp_allocator, "          <none>");
    }

    var have_frames = false;
    span = editor.FirstSpan;
    while (span) |this_span| : (span = this_span.FLink) {
        if (this_span.Frame) |frame| {
            if (!have_frames) {
                have_frames = true;
                try lines.append(temp_allocator, "");
                try lines.append(temp_allocator, "Frames");
                try lines.append(temp_allocator, "======");
            }
            try lines.append(temp_allocator, this_span.Name);
            try appendFileLine(editor, temp_allocator, &lines, "Input", frame.InputFile);
            try appendFileLine(editor, temp_allocator, &lines, "Output", frame.OutputFile);
        }
    }

    const ok = try replaceReportFrame(allocator, report_frame, lines.items);
    if (!ok) {
        return false;
    }

    switch (editor.LudwigMode) {
        .LudwigScreen => try showInteractiveSpanIndex(editor, temp_allocator),
        .LudwigBatch, .LudwigHardcopy => if (editor.BatchOutputEnabled) {
            try printBatchSpanIndex(editor, temp_allocator);
        },
    }
    return true;
}

fn expectFrameLines(frame: *types.FrameObject, expected: []const []const u8) !void {
    const sentinel = frame.LastGroup.?.LastLine.?;
    var line = frame.FirstGroup.?.FirstLine.?;
    for (expected) |content| {
        try std.testing.expect(line != sentinel);
        try std.testing.expectEqualStrings(content, line_ops.getLineContent(line));
        line = line.FLink.?;
    }
    try std.testing.expect(line == sentinel);
}

test "span create find and destroy maintain ordering" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.setupLinkedLines(allocator, 3);
    var first_mark: ?*types.MarkObject = null;
    var last_mark: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 1, &first_mark);
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 10, &last_mark);

    try std.testing.expect(try SpanCreate(&editor, allocator, "charlie", first_mark.?, last_mark.?));
    try std.testing.expect(try SpanCreate(&editor, allocator, "alpha", first_mark.?, last_mark.?));
    try std.testing.expect(try SpanCreate(&editor, allocator, "bravo", first_mark.?, last_mark.?));
    try std.testing.expectEqualStrings("alpha", editor.FirstSpan.?.Name);
    try std.testing.expectEqualStrings("bravo", editor.FirstSpan.?.FLink.?.Name);
    try std.testing.expectEqualStrings("charlie", editor.FirstSpan.?.FLink.?.FLink.?.Name);

    var found: ?*types.SpanObject = null;
    var prev: ?*types.SpanObject = null;
    try std.testing.expect(try SpanFind(&editor, allocator, "bravo", &found, &prev));
    try std.testing.expect(found == editor.FirstSpan.?.FLink);
    try std.testing.expect(prev == editor.FirstSpan);

    try std.testing.expect(SpanDestroy(&editor, allocator, &found));
    try std.testing.expect(editor.FirstSpan.?.FLink != null);
    try std.testing.expectEqualStrings("charlie", editor.FirstSpan.?.FLink.?.Name);
}

test "span create normalizes reversed marks and supports redefine" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.setupLinkedLines(allocator, 2);
    var mark1: ?*types.MarkObject = null;
    var mark2: ?*types.MarkObject = null;
    var mark3: ?*types.MarkObject = null;
    var mark4: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 15, &mark1);
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 5, &mark2);
    try std.testing.expect(try SpanCreate(&editor, allocator, "ordered", mark1.?, mark2.?));
    try std.testing.expectEqual(@as(isize, 5), editor.FirstSpan.?.MarkOne.?.Col);
    try std.testing.expectEqual(@as(isize, 15), editor.FirstSpan.?.MarkTwo.?.Col);

    try mark_ops.markCreate(allocator, fixture.content_lines[0], 7, &mark3);
    try mark_ops.markCreate(allocator, fixture.content_lines[1], 2, &mark4);
    try std.testing.expect(try SpanCreate(&editor, allocator, "ordered", mark3.?, mark4.?));
    try std.testing.expect(editor.FirstSpan.?.MarkOne.?.Line == fixture.content_lines[0]);
    try std.testing.expect(editor.FirstSpan.?.MarkTwo.?.Line == fixture.content_lines[1]);
}

test "span find refreshes frame-backed spans" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.setupLinkedLines(allocator, 2);
    const frame_span = try allocator.create(types.SpanObject);
    frame_span.* = .{
        .Name = "frame",
        .Frame = fixture.frame,
    };
    editor.FirstSpan = frame_span;

    var found: ?*types.SpanObject = null;
    var prev: ?*types.SpanObject = null;
    try std.testing.expect(try SpanFind(&editor, allocator, "frame", &found, &prev));
    try std.testing.expect(found.?.MarkOne != null);
    try std.testing.expect(found.?.MarkTwo != null);
    try std.testing.expect(found.?.MarkOne.?.Line == fixture.frame.FirstGroup.?.FirstLine.?);
    try std.testing.expect(found.?.MarkTwo.?.Line == fixture.frame.LastGroup.?.LastLine.?);
}

test "span index writes a non-interactive report into the target frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const source = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "abcdefghijklmnopqrstuvwxyz0123456789",
        "omega",
    });
    var mark_one: ?*types.MarkObject = null;
    var mark_two: ?*types.MarkObject = null;
    try mark_ops.markCreate(allocator, source.content_lines[0], 2, &mark_one);
    try mark_ops.markCreate(allocator, source.content_lines[1], 2, &mark_two);
    try std.testing.expect(try SpanCreate(&editor, allocator, "NOTE", mark_one.?, mark_two.?));

    const command = (try frame_ops.FrameEdit(&editor, allocator, source.frame, "COMMAND")).?;
    _ = (try frame_ops.FrameEdit(&editor, allocator, source.frame, "HEAP")).?;
    const oops = (try frame_ops.FrameEdit(&editor, allocator, source.frame, "OOPS")).?;

    const input_file = try allocator.create(types.FileObject);
    input_file.* = .{ .Filename = "input.txt" };
    editor.Files[1] = input_file;
    command.InputFile = 1;

    const output_file = try allocator.create(types.FileObject);
    output_file.* = .{ .Filename = "output.txt" };
    editor.Files[2] = output_file;
    command.OutputFile = 2;

    try std.testing.expect(try SpanIndex(&editor, allocator, oops));
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
    try std.testing.expect(oops.Dot.?.Line == oops.FirstGroup.?.FirstLine.?);
    try std.testing.expect(oops.Span.?.MarkOne.?.Line == oops.FirstGroup.?.FirstLine.?);
    try std.testing.expect(oops.Span.?.MarkTwo.?.Line == oops.LastGroup.?.LastLine.?);
}
