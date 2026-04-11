const std = @import("std");
const help_assets = @import("help_assets.zig");
const interactive_io = @import("interactive_io.zig");
const line_ops = @import("../core/line.zig");
const mark_ops = @import("../core/mark.zig");
const state = @import("../core/state.zig");
const types = @import("../core/types.zig");

const help_index_topic = "0";
const help_more_prompt = "<space> for more, <return> to exit : ";
const help_topic_prompt = "Command or Section or <return> to exit : ";
const help_missing_topic = "Can't find Command or Section in HELP";

const Entry = struct {
    start: usize,
    end: usize,
};

const Header = struct {
    index_count: usize,
    contents_count: usize,
    cursor: usize,
};

const LineRead = struct {
    text: []const u8,
    next: usize,
};

fn readLine(data: []const u8, offset: usize) !LineRead {
    if (offset > data.len) {
        return error.InvalidHelpIndex;
    }
    const line_end = std.mem.indexOfScalarPos(u8, data, offset, '\n') orelse data.len;
    return .{
        .text = data[offset..line_end],
        .next = if (line_end < data.len) line_end + 1 else data.len,
    };
}

fn parseHeader(data: []const u8) !Header {
    const line = try readLine(data, 0);
    var fields = std.mem.tokenizeAny(u8, line.text, " \t");
    const index_count = std.fmt.parseInt(usize, fields.next() orelse return error.InvalidHelpIndex, 10) catch {
        return error.InvalidHelpIndex;
    };
    const contents_count = std.fmt.parseInt(usize, fields.next() orelse return error.InvalidHelpIndex, 10) catch {
        return error.InvalidHelpIndex;
    };
    if (fields.next() != null) {
        return error.InvalidHelpIndex;
    }
    return .{
        .index_count = index_count,
        .contents_count = contents_count,
        .cursor = line.next,
    };
}

fn skipLines(data: []const u8, start: usize, count: usize) !usize {
    var cursor = start;
    var remaining: usize = 0;
    while (remaining < count) : (remaining += 1) {
        cursor = (try readLine(data, cursor)).next;
    }
    return cursor;
}

fn findEntry(data: []const u8, topic: []const u8) !?Entry {
    const header = try parseHeader(data);
    var cursor = header.cursor;
    var relative_entry: ?Entry = null;

    var index_nr: usize = 0;
    while (index_nr < header.index_count) : (index_nr += 1) {
        const line = try readLine(data, cursor);
        cursor = line.next;

        var fields = std.mem.tokenizeAny(u8, line.text, " \t");
        const key = fields.next() orelse return error.InvalidHelpIndex;
        const start_text = fields.next() orelse return error.InvalidHelpIndex;
        const end_text = fields.next() orelse return error.InvalidHelpIndex;
        if (fields.next() != null) {
            return error.InvalidHelpIndex;
        }

        if (std.mem.eql(u8, key, topic)) {
            relative_entry = .{
                .start = std.fmt.parseInt(usize, start_text, 10) catch return error.InvalidHelpIndex,
                .end = std.fmt.parseInt(usize, end_text, 10) catch return error.InvalidHelpIndex,
            };
        }
    }

    const contents_start = cursor;
    const body_start = try skipLines(data, cursor, header.contents_count);

    if (std.mem.eql(u8, topic, "0")) {
        return .{
            .start = contents_start,
            .end = body_start,
        };
    }

    const entry = relative_entry orelse return null;
    const start = body_start + entry.start;
    const end = body_start + entry.end;
    if (start > end or end > data.len) {
        return error.InvalidHelpIndex;
    }
    return .{
        .start = start,
        .end = end,
    };
}

fn normalizeTopic(allocator: std.mem.Allocator, selection: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, selection, " \t");
    const source = if (trimmed.len == 0) help_index_topic else trimmed;
    const topic = try allocator.alloc(u8, source.len);
    for (source, 0..) |ch, idx| {
        topic[idx] = std.ascii.toUpper(ch);
    }
    return topic;
}

fn promptUpperLine(allocator: std.mem.Allocator, prompt: []const u8) ![]u8 {
    const reply = try interactive_io.readPromptLineWithOptions(allocator, prompt, .{
        .max_len = types.KeyLen,
        .terminate_on_space = true,
    });
    for (reply) |*ch| {
        ch.* = std.ascii.toUpper(ch.*);
    }
    return reply;
}

fn promptNextTopic(allocator: std.mem.Allocator) ![]u8 {
    const reply = try promptUpperLine(allocator, help_topic_prompt);
    if (reply.len == 0) {
        return reply;
    }
    if (reply[0] == ' ') {
        allocator.free(reply);
        return allocator.dupe(u8, help_index_topic);
    }

    const topic = try normalizeTopic(allocator, reply);
    allocator.free(reply);
    return topic;
}

fn selectedIndexData(editor: *const state.Editor) []const u8 {
    return if (editor.FileData.OldCmds)
        help_assets.old_help_index
    else
        help_assets.new_help_index;
}

fn readEntryLines(
    allocator: std.mem.Allocator,
    data: []const u8,
    entry: Entry,
) !std.ArrayListUnmanaged([]const u8) {
    var lines: std.ArrayListUnmanaged([]const u8) = .{};
    var cursor = entry.start;
    while (cursor < entry.end) {
        const line = try readLine(data, cursor);
        cursor = line.next;
        if (line.text.len >= 2 and line.text[0] == '\\' and line.text[1] == '%') {
            continue;
        }
        try lines.append(allocator, line.text);
    }
    return lines;
}

fn refreshFrameSpanMarks(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !void {
    if (frame.Span) |span| {
        try mark_ops.markCreate(allocator, frame.FirstGroup.?.FirstLine.?, 1, &span.MarkOne);
        try mark_ops.markCreate(allocator, frame.LastGroup.?.LastLine.?, 1, &span.MarkTwo);
    }
}

fn clearFrameText(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !void {
    const sentinel = frame.LastGroup.?.LastLine.?;
    const last_content = sentinel.BLink;
    if (last_content == null) {
        try mark_ops.markCreate(allocator, sentinel, 1, &frame.Dot);
        try refreshFrameSpanMarks(allocator, frame);
        return;
    }

    const first_content = frame.FirstGroup.?.FirstLine.?;
    try mark_ops.marksSqueeze(allocator, first_content, 1, sentinel, 1);
    first_content.BLink = null;
    last_content.?.FLink = null;
    sentinel.BLink = null;
    sentinel.OffsetNr = 0;

    const empty_group = sentinel.Group.?;
    frame.FirstGroup = empty_group;
    frame.LastGroup = empty_group;
    empty_group.BLink = null;
    empty_group.FLink = null;
    empty_group.FirstLine = sentinel;
    empty_group.LastLine = sentinel;
    empty_group.FirstLineNr = 1;
    empty_group.NrLines = 0;

    try line_ops.lineChangeLength(allocator, sentinel, 0);
    try mark_ops.markCreate(allocator, sentinel, 1, &frame.Dot);
    try refreshFrameSpanMarks(allocator, frame);
}

fn replaceReportFrame(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    lines: []const []const u8,
) !bool {
    try clearFrameText(allocator, frame);
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

    try refreshFrameSpanMarks(allocator, frame);
    const first_line = frame.FirstGroup.?.FirstLine.?;
    try mark_ops.markCreate(allocator, first_line, 1, &frame.Dot);
    mark_ops.markDestroy(allocator, &frame.Marks[types.MarkEquals]);
    mark_ops.markDestroy(allocator, &frame.Marks[types.MarkModified]);
    frame.TextModified = false;
    return true;
}

pub fn HelpCommandForData(
    allocator: std.mem.Allocator,
    report_frame: *types.FrameObject,
    index_data: []const u8,
    selection: []const u8,
) !bool {
    const topic = try normalizeTopic(allocator, selection);
    defer allocator.free(topic);

    const entry = (try findEntry(index_data, topic)) orelse return false;
    var lines = try readEntryLines(allocator, index_data, entry);
    defer lines.deinit(allocator);
    return replaceReportFrame(allocator, report_frame, lines.items);
}

pub fn HelpCommand(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    report_frame: *types.FrameObject,
    selection: []const u8,
) !bool {
    const index_data = selectedIndexData(editor);
    return HelpCommandForData(allocator, report_frame, index_data, selection);
}

pub fn HelpInteractiveForData(
    allocator: std.mem.Allocator,
    index_data: []const u8,
    selection: []const u8,
) !bool {
    var topic = try normalizeTopic(allocator, selection);
    defer allocator.free(topic);

    while (topic.len != 0) {
        const entry = (try findEntry(index_data, topic)) orelse {
            interactive_io.showTemporaryLines(&[_][]const u8{help_missing_topic});
            const next = try promptNextTopic(allocator);
            allocator.free(topic);
            topic = next;
            continue;
        };

        var page_lines: std.ArrayListUnmanaged([]const u8) = .{};
        defer page_lines.deinit(allocator);

        var cursor = entry.start;
        while (cursor < entry.end) {
            const line = try readLine(index_data, cursor);
            cursor = line.next;

            if (line.text.len >= 2 and line.text[0] == '\\' and line.text[1] == '%') {
                interactive_io.showTemporaryLines(page_lines.items);
                const reply = try promptUpperLine(allocator, help_more_prompt);
                if (reply.len > 0 and reply[0] == ' ') {
                    allocator.free(reply);
                    page_lines.clearRetainingCapacity();
                    continue;
                }
                if (reply.len == 0) {
                    allocator.free(reply);
                    const next = try promptNextTopic(allocator);
                    allocator.free(topic);
                    topic = next;
                    break;
                }

                const next = try normalizeTopic(allocator, reply);
                allocator.free(reply);
                allocator.free(topic);
                topic = next;
                break;
            }

            try page_lines.append(allocator, line.text);
        }

        if (cursor >= entry.end) {
            interactive_io.showTemporaryLines(page_lines.items);
            const next = try promptNextTopic(allocator);
            allocator.free(topic);
            topic = next;
        }
    }

    return true;
}

pub fn HelpInteractive(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    selection: []const u8,
) !bool {
    return HelpInteractiveForData(allocator, selectedIndexData(editor), selection);
}

fn makeReportFrame(allocator: std.mem.Allocator, name: []const u8) !line_ops.FrameFixture {
    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{""});
    const span = try allocator.create(types.SpanObject);
    span.* = .{
        .Name = name,
        .Frame = fixture.frame,
    };
    fixture.frame.Span = span;
    try mark_ops.markCreate(allocator, fixture.frame.FirstGroup.?.FirstLine.?, 1, &span.MarkOne);
    try mark_ops.markCreate(allocator, fixture.frame.LastGroup.?.LastLine.?, 1, &span.MarkTwo);
    return fixture;
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

test "help command can render synthetic contents page" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const help_builder = @import("../help_builder.zig");
    const input =
        \\+Main Help
        \\\ABCD
        \\ first line
        \\\%
        \\ second line
        \\\#
        \\
    ;

    var diagnostics: std.ArrayListUnmanaged(u8) = .{};
    const index_data = try help_builder.buildHelpIndex(allocator, input, &diagnostics);

    const report = try makeReportFrame(allocator, "OOPS");
    try std.testing.expect(try HelpCommandForData(allocator, report.frame, index_data, ""));
    try expectFrameLines(report.frame, &[_][]const u8{"Main Help"});
}

test "help command skips pagination markers and normalizes topic case" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const help_builder = @import("../help_builder.zig");
    const input =
        \\+Main Help
        \\\ABCD
        \\ first line
        \\\%
        \\ second line
        \\\#
        \\
    ;

    var diagnostics: std.ArrayListUnmanaged(u8) = .{};
    const index_data = try help_builder.buildHelpIndex(allocator, input, &diagnostics);

    const report = try makeReportFrame(allocator, "OOPS");
    try std.testing.expect(try HelpCommandForData(allocator, report.frame, index_data, "abcd"));
    try expectFrameLines(report.frame, &[_][]const u8{
        "first line",
        "second line",
    });
}

test "help command returns false for unknown topic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const help_builder = @import("../help_builder.zig");
    const input =
        \\+Main Help
        \\\ABCD
        \\ first line
        \\\#
        \\
    ;

    var diagnostics: std.ArrayListUnmanaged(u8) = .{};
    const index_data = try help_builder.buildHelpIndex(allocator, input, &diagnostics);

    const report = try makeReportFrame(allocator, "OOPS");
    try std.testing.expect(!(try HelpCommandForData(allocator, report.frame, index_data, "ZZZZ")));
}

test "interactive help can paginate and exit through prompts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const help_builder = @import("../help_builder.zig");
    const input =
        \\+Main Help
        \\\ABCD
        \\ first line
        \\\%
        \\ second line
        \\\#
        \\
    ;

    var diagnostics: std.ArrayListUnmanaged(u8) = .{};
    const index_data = try help_builder.buildHelpIndex(allocator, input, &diagnostics);

    interactive_io.testing.installInput(" \r\r");
    defer interactive_io.testing.clearInput();

    try std.testing.expect(try HelpInteractiveForData(allocator, index_data, "abcd"));
}
