const std = @import("std");
const batch_output = @import("../platform/batch_output.zig");
const interactive_io = @import("../platform/interactive_io.zig");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const sys_ops = @import("../platform/sys.zig");
const state = @import("state.zig");
const text = @import("text.zig");
const types = @import("types.zig");

const no_file_open_message = "No file open.";
const loading_file_message = "Loading File.";

fn fileNameForWidth(allocator: std.mem.Allocator, file: *const types.FileObject, max_len_raw: usize) ![]const u8 {
    const max_len = @max(max_len_raw, 5);
    if (file.Filename.len <= max_len) {
        return allocator.dupe(u8, file.Filename);
    }

    const tail_len = @divFloor(max_len - 3, 2);
    const head_len = max_len - 3 - tail_len;
    return std.fmt.allocPrint(
        allocator,
        "{s}---{s}",
        .{
            file.Filename[0..head_len],
            file.Filename[file.Filename.len - tail_len ..],
        },
    );
}

fn padRight(allocator: std.mem.Allocator, text_in: []const u8, width: usize) ![]const u8 {
    const padded = if (text_in.len >= width) text_in else blk: {
        const out = try allocator.alloc(u8, width);
        @memcpy(out[0..text_in.len], text_in);
        @memset(out[text_in.len..], ' ');
        break :blk out;
    };
    if (padded.ptr == text_in.ptr and padded.len == text_in.len) {
        return allocator.dupe(u8, padded);
    }
    return padded;
}

fn usageLabel(editor: *const state.Editor, slot: usize, file: *const types.FileObject) []const u8 {
    if (editor.FilesFrames[slot] != null) {
        return if (file.OutputFlag) "FO" else "FI";
    }
    if (slot == @as(usize, @intCast(editor.FgiFile))) {
        return "FGI";
    }
    if (slot == @as(usize, @intCast(editor.FgoFile))) {
        return "FGO";
    }
    return if (file.OutputFlag) "FFO" else "FFI";
}

fn reportNameWidth(editor: *const state.Editor) usize {
    if (editor.LudwigMode == .LudwigScreen and editor.TerminalInfo.Width > 19) {
        return @intCast(@max(editor.TerminalInfo.Width - 19, 5));
    }
    return types.FileNameLen;
}

fn renderFileLine(editor: *const state.Editor, allocator: std.mem.Allocator, slot: usize, file: *const types.FileObject) ![]const u8 {
    const frame = editor.FilesFrames[slot];
    const usage = try padRight(allocator, usageLabel(editor, slot, file), 3);
    const eof_status: []const u8 = if (file.Eof) "EOF" else "   ";
    const mod_status: []const u8 = if (frame != null and frame.?.TextModified) " * " else "   ";
    const frame_name = try padRight(allocator, if (frame != null and frame.?.Span != null) frame.?.Span.?.Name else "", 6);
    const filename = try fileNameForWidth(allocator, file, reportNameWidth(editor));
    return std.fmt.allocPrint(allocator, "{s} {s} {s}{s} {s}", .{
        usage,
        eof_status,
        mod_status,
        frame_name,
        filename,
    });
}

fn renderBatchFileLine(editor: *const state.Editor, allocator: std.mem.Allocator, slot: usize, file: *const types.FileObject) ![]const u8 {
    const frame = editor.FilesFrames[slot];
    const usage = try padRight(allocator, usageLabel(editor, slot, file), 3);
    const eof_status: []const u8 = if (file.Eof) "EOF" else "   ";
    const mod_status: []const u8 = if (frame != null and frame.?.TextModified) " * " else "   ";
    const frame_name = try padRight(allocator, if (frame != null and frame.?.Span != null) frame.?.Span.?.Name else "", 6);
    const filename = try fileNameForWidth(allocator, file, reportNameWidth(editor));
    return std.fmt.allocPrint(allocator, "{s} {s} {s} {s} {s}", .{
        usage,
        eof_status,
        mod_status,
        frame_name,
        filename,
    });
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
        const range = try line_ops.LinesCreate(allocator, lines.len);
        try line_ops.linesInject(allocator, range.first, range.last, sentinel);

        var line = range.first;
        for (lines, 0..) |content, index| {
            if (content.len > 0) {
                try line_ops.LineChangeLength(allocator, line, @intCast(content.len));
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
    try mark_ops.MarkCreate(allocator, first_line, 1, &span.MarkOne);
    try mark_ops.MarkCreate(allocator, frame.LastGroup.?.LastLine.?, 1, &span.MarkTwo);
    try mark_ops.MarkCreate(allocator, first_line, 1, &frame.Dot);
    mark_ops.MarkDestroy(allocator, &frame.Marks[types.MarkEquals]);
    mark_ops.MarkDestroy(allocator, &frame.Marks[types.MarkModified]);
    frame.TextModified = false;
    return true;
}

pub fn fileTable(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    report_frame: *types.FrameObject,
) !bool {
    var lines: std.ArrayListUnmanaged([]const u8) = .{};
    try lines.append(allocator, "Usage   Mod Frame  Filename");
    try lines.append(allocator, "------- --- ------ --------");
    try lines.append(allocator, "");

    var have_files = false;
    var slot: usize = 1;
    while (slot <= types.MaxFiles) : (slot += 1) {
        const file = editor.Files[slot] orelse continue;
        have_files = true;
        try lines.append(allocator, try renderFileLine(editor, allocator, slot, file));
    }
    if (!have_files) {
        try lines.append(allocator, "<none>");
    }

    const ok = try replaceReportFrame(allocator, report_frame, lines.items);
    if (ok) {
        switch (editor.LudwigMode) {
            .LudwigScreen => try interactive_io.showTemporaryReport(allocator, lines.items),
            .LudwigBatch, .LudwigHardcopy => if (editor.BatchOutputEnabled) {
                var batch_lines: std.ArrayListUnmanaged([]const u8) = .{};
                try batch_lines.append(allocator, "Usage   Mod Frame  Filename");
                try batch_lines.append(allocator, "------- --- ------ --------");
                try batch_lines.append(allocator, "");

                if (have_files) {
                    slot = 1;
                    while (slot <= types.MaxFiles) : (slot += 1) {
                        const file = editor.Files[slot] orelse continue;
                        try batch_lines.append(allocator, try renderBatchFileLine(editor, allocator, slot, file));
                    }
                } else {
                    try batch_lines.append(allocator, "<none>");
                }
                batch_output.printLines(batch_lines.items, 2);
            },
        }
    }
    return ok;
}

const LineSelection = struct {
    first: ?*types.LineHdrObject = null,
    last: ?*types.LineHdrObject = null,
};

const ReadResult = struct {
    first: ?*types.LineHdrObject = null,
    last: ?*types.LineHdrObject = null,
    count: isize = 0,
};

fn countRange(first: *const types.LineHdrObject, last: *const types.LineHdrObject) ?usize {
    var count: usize = 1;
    var line = first;
    while (line != last) : (count += 1) {
        line = line.FLink orelse return null;
    }
    return count;
}

fn cloneLineRange(
    allocator: std.mem.Allocator,
    first: *const types.LineHdrObject,
    last: *const types.LineHdrObject,
) !line_ops.LineRange {
    const line_count = countRange(first, last) orelse return error.InvalidLineRange;
    const range = try line_ops.LinesCreate(allocator, line_count);

    var src = first;
    var dst = range.first;
    while (true) {
        if (src.Used > 0) {
            try line_ops.LineChangeLength(allocator, dst, src.Used);
            try line_ops.setLineContent(dst, src.Str.?.Slice(1, src.Used));
        } else {
            dst.Used = 0;
        }
        if (src == last) {
            break;
        }
        src = src.FLink.?;
        dst = dst.FLink.?;
    }
    return range;
}

fn setFileQueue(
    file: *types.FileObject,
    first: ?*types.LineHdrObject,
    last: ?*types.LineHdrObject,
    line_count: isize,
) void {
    file.FirstLine = first;
    file.LastLine = last;
    file.LineCount = line_count;
}

fn buildLineRangeFromContents(
    allocator: std.mem.Allocator,
    contents: []const []const u8,
) !?line_ops.LineRange {
    if (contents.len == 0) {
        return null;
    }

    const range = try line_ops.LinesCreate(allocator, contents.len);
    var line = range.first;
    for (contents, 0..) |content, index| {
        if (content.len > 0) {
            try line_ops.LineChangeLength(allocator, line, @intCast(content.len));
            try line_ops.setLineContent(line, content);
        } else {
            line.Used = 0;
        }
        if (index + 1 < contents.len) {
            line = line.FLink.?;
        }
    }
    return range;
}

fn loadFileQueueFromSnapshot(
    allocator: std.mem.Allocator,
    file: *types.FileObject,
) !bool {
    setFileQueue(file, null, null, 0);
    file.LCounter = 0;
    if (file.RewindFirstLine == null or file.RewindLastLine == null or file.RewindLineCount == 0) {
        file.Eof = true;
        return true;
    }

    const cloned = try cloneLineRange(allocator, file.RewindFirstLine.?, file.RewindLastLine.?);
    setFileQueue(file, cloned.first, cloned.last, file.RewindLineCount);
    file.Eof = false;
    return true;
}

fn appendToFile(file: *types.FileObject, first: *types.LineHdrObject, last: *types.LineHdrObject) !void {
    const appended = countRange(first, last) orelse return error.InvalidLineRange;
    if (file.LastLine) |tail| {
        tail.FLink = first;
        first.BLink = tail;
    } else {
        file.FirstLine = first;
        first.BLink = null;
    }
    file.LastLine = last;
    file.LineCount += @intCast(appended);
    file.LCounter += @intCast(appended);
}

fn linePlural(count: isize) []const u8 {
    return if (count == 1) "" else "s";
}

fn emitStatusMessage(editor: *const state.Editor, message: []const u8) void {
    switch (editor.LudwigMode) {
        .LudwigScreen => interactive_io.queueStatusMessage(message),
        .LudwigBatch, .LudwigHardcopy => if (editor.BatchOutputEnabled) {
            batch_output.printMessage(message);
        },
    }
}

fn emitNoFileOpenMessage(editor: *const state.Editor) void {
    emitStatusMessage(editor, no_file_open_message);
}

fn pageFileWithLoadingMessage(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !bool {
    if (editor.LudwigMode == .LudwigScreen) {
        interactive_io.queueStatusMessage(loading_file_message);
    }
    defer interactive_io.clearStatusMessage();
    return filePage(editor, allocator, frame);
}

fn emitInputClosedMessage(editor: *const state.Editor, file: *const types.FileObject) void {
    var buffer: [4096]u8 = undefined;
    const message = std.fmt.bufPrint(
        &buffer,
        "File {s} closed ({d} line{s} read).",
        .{ file.Filename, file.LCounter, linePlural(file.LCounter) },
    ) catch return;
    emitStatusMessage(editor, message);
}

fn emitOutputCreatedMessage(editor: *const state.Editor, file: *const types.FileObject) void {
    var buffer: [4096]u8 = undefined;
    const message = std.fmt.bufPrint(
        &buffer,
        "File {s} created ({d} line{s} written).",
        .{ file.Filename, file.LCounter, linePlural(file.LCounter) },
    ) catch return;
    emitStatusMessage(editor, message);
}

fn emitOutputDeletedMessage(editor: *const state.Editor, file: *const types.FileObject) void {
    const display_name = if (file.Tnm.len > 0) file.Tnm else file.Filename;
    var buffer: [4096]u8 = undefined;
    const message = std.fmt.bufPrint(
        &buffer,
        "Output file {s} deleted.",
        .{display_name},
    ) catch return;
    emitStatusMessage(editor, message);
}

fn createFileObject(allocator: std.mem.Allocator, output_flag: bool) !*types.FileObject {
    const file = try allocator.create(types.FileObject);
    file.* = .{
        .Valid = true,
        .OutputFlag = output_flag,
    };
    return file;
}

pub const DiskOutputOptions = struct {
    related_name: ?[]const u8 = null,
    create: bool = false,
    memory: ?[]const u8 = null,
};

fn appendRangeCloneToFile(
    allocator: std.mem.Allocator,
    file: *types.FileObject,
    first: *const types.LineHdrObject,
    last: *const types.LineHdrObject,
) !void {
    const cloned = try cloneLineRange(allocator, first, last);
    try appendToFile(file, cloned.first, cloned.last);
}

fn appendLineBytesToFile(
    allocator: std.mem.Allocator,
    file: *types.FileObject,
    content: []const u8,
) !void {
    const range = try line_ops.LinesCreate(allocator, 1);
    if (content.len > 0) {
        try line_ops.LineChangeLength(allocator, range.first, @intCast(content.len));
        try line_ops.setLineContent(range.first, content);
    } else {
        range.first.Used = 0;
    }
    try appendToFile(file, range.first, range.last);
}

fn setSnapshotFromQueue(
    allocator: std.mem.Allocator,
    file: *types.FileObject,
) !void {
    file.RewindFirstLine = null;
    file.RewindLastLine = null;
    file.RewindLineCount = 0;
    if (file.FirstLine == null or file.LastLine == null or file.LineCount == 0) {
        return;
    }

    const cloned = try cloneLineRange(allocator, file.FirstLine.?, file.LastLine.?);
    file.RewindFirstLine = cloned.first;
    file.RewindLastLine = cloned.last;
    file.RewindLineCount = file.LineCount;
}

fn clampTabWidth(editor: *const state.Editor) usize {
    return @intCast(@min(@as(isize, 8), @max(@as(isize, 2), editor.FileData.TabWidth)));
}

fn isLineTerminator(byte: u8) bool {
    return switch (byte) {
        '\n', '\r', 0x0b, 0x0c => true,
        else => false,
    };
}

fn isPrintableFileByte(byte: u8) bool {
    return byte >= 0x20 and byte != 0x7f;
}

fn makeDiskInputFile(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    file_name: []const u8,
) !?*types.FileObject {
    const owned_name = (try sys_ops.expandFilename(allocator, file_name)) orelse return null;
    const status = sys_ops.fileStatus(owned_name);
    if (!status.Valid or status.IsDir) {
        return null;
    }
    const data = sys_ops.readFileAlloc(allocator, owned_name, std.math.maxInt(usize)) catch return null;
    const file = try createFileObject(allocator, false);
    file.Filename = owned_name;
    file.Mode = status.Mode;
    file.PreviousFileId = @intCast(status.Mtime);

    var line_buffer: std.ArrayListUnmanaged(u8) = .{};
    defer line_buffer.deinit(allocator);

    const tab_width = clampTabWidth(editor);
    for (data) |byte| {
        if (isLineTerminator(byte)) {
            try appendLineBytesToFile(allocator, file, line_buffer.items);
            line_buffer.clearRetainingCapacity();
            continue;
        }

        if (byte == '\t') {
            var spaces = tab_width - (line_buffer.items.len % tab_width);
            while (spaces > 0) : (spaces -= 1) {
                if (line_buffer.items.len == types.MaxStrLen) {
                    try appendLineBytesToFile(allocator, file, line_buffer.items);
                    line_buffer.clearRetainingCapacity();
                }
                try line_buffer.append(allocator, ' ');
            }
            continue;
        }

        if (!isPrintableFileByte(byte)) {
            continue;
        }

        if (line_buffer.items.len == types.MaxStrLen) {
            try appendLineBytesToFile(allocator, file, line_buffer.items);
            line_buffer.clearRetainingCapacity();
        }
        try line_buffer.append(allocator, byte);
    }

    if (line_buffer.items.len > 0 or (data.len > 0 and !isLineTerminator(data[data.len - 1]))) {
        try appendLineBytesToFile(allocator, file, line_buffer.items);
    }

    file.LCounter = 0;
    file.Eof = file.LineCount == 0;
    if (file.LineCount > 0) {
        file.Eof = false;
    }
    try setSnapshotFromQueue(allocator, file);
    return file;
}

fn makeDiskOutputFile(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    file_name: []const u8,
    options: DiskOutputOptions,
) !?*types.FileObject {
    const resolved_name = if (file_name.len > 0)
        file_name
    else if (options.related_name != null and options.related_name.?.len > 0)
        options.related_name.?
    else
        return null;

    var owned_name = (try sys_ops.expandFilename(allocator, resolved_name)) orelse return null;
    var status = sys_ops.fileStatus(owned_name);
    if (status.Valid and status.IsDir) {
        const related_name = options.related_name orelse return null;
        owned_name = try sys_ops.copyFilename(allocator, related_name, owned_name);
        status = sys_ops.fileStatus(owned_name);
    }
    if (status.Valid) {
        if (options.create or status.IsDir or !sys_ops.fileWritable(owned_name)) {
            return null;
        }
    }

    const file = try createFileObject(allocator, true);
    file.Filename = owned_name;
    file.Memory = if (options.memory) |memory| memory else "";
    file.Tnm = try buildTempOutputName(allocator, owned_name);
    file.Entab = editor.FileData.Entab;
    file.Create = options.create;
    file.Mode = if (status.Valid) status.Mode else sys_ops.fileMask();
    file.PreviousFileId = if (status.Valid) @intCast(status.Mtime) else 0;
    file.Purge = editor.FileData.Purge;
    file.Versions = editor.FileData.Versions;
    file.Eof = false;
    return file;
}

pub fn openDiskInputFile(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    file_name: []const u8,
) !?*types.FileObject {
    return makeDiskInputFile(editor, allocator, file_name);
}

pub fn openDiskOutputFile(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    file_name: []const u8,
    options: DiskOutputOptions,
) !?*types.FileObject {
    return makeDiskOutputFile(editor, allocator, file_name, options);
}

fn appendEncodedLine(
    allocator: std.mem.Allocator,
    buffer: *std.ArrayListUnmanaged(u8),
    line: []const u8,
    entab: bool,
    tab_width: usize,
) !void {
    if (entab and tab_width > 0) {
        var spaces: usize = 0;
        while (spaces < line.len and line[spaces] == ' ') : (spaces += 1) {}
        const tabs = spaces / tab_width;
        var index: usize = 0;
        while (index < tabs) : (index += 1) {
            try buffer.append(allocator, '\t');
        }
        try buffer.appendSlice(allocator, line[tabs * tab_width ..]);
    } else {
        try buffer.appendSlice(allocator, line);
    }
    try buffer.append(allocator, '\n');
}

fn removeBackupFiles(
    allocator: std.mem.Allocator,
    backup_file: []const u8,
    versions: []const i64,
    start: usize,
    end: usize,
) !void {
    var index = start;
    while (index < end) : (index += 1) {
        const file_name = try std.fmt.allocPrint(allocator, "{s}{d}", .{ backup_file, versions[index] });
        sys_ops.deleteFile(file_name) catch {};
    }
}

fn buildTempOutputName(
    allocator: std.mem.Allocator,
    file_name: []const u8,
) ![]const u8 {
    var unique: usize = 0;
    while (true) : (unique += 1) {
        const candidate = if (unique == 0)
            try std.fmt.allocPrint(allocator, "{s}-lw", .{file_name})
        else
            try std.fmt.allocPrint(allocator, "{s}-lw{d}", .{ file_name, unique });
        if (!sys_ops.fileExists(candidate)) {
            return candidate;
        }
    }
}

fn writeOutputBytes(
    allocator: std.mem.Allocator,
    output_file: *types.FileObject,
    data: []const u8,
) !bool {
    if (output_file.Tnm.len == 0) {
        output_file.Tnm = try buildTempOutputName(allocator, output_file.Filename);
    }
    sys_ops.writeFile(output_file.Tnm, data, if (output_file.Mode != 0) @intCast(output_file.Mode) else 0o600) catch return false;

    const backup_name = try std.fmt.allocPrint(allocator, "{s}~", .{output_file.Filename});
    const versions = try sys_ops.listBackups(allocator, backup_name);
    const max_vnum: i64 = if (versions.len > 0) versions[versions.len - 1] else 0;
    if (output_file.Purge) {
        if (output_file.Versions <= 0) {
            try removeBackupFiles(allocator, backup_name, versions, 0, versions.len);
        } else {
            const retain: usize = @intCast(@max(output_file.Versions - 1, 0));
            if (versions.len > retain) {
                try removeBackupFiles(allocator, backup_name, versions, 0, versions.len - retain);
            }
        }
    } else if (versions.len > 0 and versions.len >= @as(usize, @intCast(@max(output_file.Versions, 0)))) {
        try removeBackupFiles(allocator, backup_name, versions, 0, 1);
    }

    if (output_file.Versions != 0 or (!output_file.Purge and max_vnum != 0)) {
        if (sys_ops.fileExists(output_file.Filename)) {
            const backup_path = try std.fmt.allocPrint(allocator, "{s}{d}", .{ backup_name, max_vnum + 1 });
            sys_ops.renamePath(output_file.Filename, backup_path) catch {};
        }
    }

    sys_ops.renamePath(output_file.Tnm, output_file.Filename) catch return false;
    if (output_file.Memory.len > 0 and !sys_ops.isTempPath(output_file.Filename)) {
        _ = try sys_ops.writeFilename(output_file.Memory, output_file.Filename);
    }
    const status = sys_ops.fileStatus(output_file.Filename);
    if (status.Valid) {
        output_file.Mode = status.Mode;
        output_file.PreviousFileId = @intCast(status.Mtime);
    }
    return true;
}

fn writeLineRangeToDisk(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    output_file: *types.FileObject,
    first: ?*const types.LineHdrObject,
    last: ?*const types.LineHdrObject,
) !bool {
    var bytes: std.ArrayListUnmanaged(u8) = .{};
    defer bytes.deinit(allocator);

    if (first != null and last != null) {
        const tab_width = clampTabWidth(editor);
        var line = first.?;
        while (true) {
            try appendEncodedLine(allocator, &bytes, line_ops.getLineContent(line), output_file.Entab, tab_width);
            if (line == last.?) {
                break;
            }
            line = line.FLink.?;
        }
    }
    return writeOutputBytes(allocator, output_file, bytes.items);
}

fn buildSavedFileContents(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    output_file: *types.FileObject,
    input_file: ?*types.FileObject,
) !*types.FileObject {
    const assembled = try createFileObject(allocator, false);

    if (output_file.FirstLine != null and output_file.LastLine != null) {
        try appendRangeCloneToFile(allocator, assembled, output_file.FirstLine.?, output_file.LastLine.?);
    }

    const visible_last = frame.LastGroup.?.LastLine.?.BLink;
    if (visible_last != null) {
        try appendRangeCloneToFile(allocator, assembled, frame.FirstGroup.?.FirstLine.?, visible_last.?);
    }

    if (input_file) |input| {
        if (input.FirstLine != null and input.LastLine != null) {
            try appendRangeCloneToFile(allocator, assembled, input.FirstLine.?, input.LastLine.?);
        }
    }

    assembled.Eof = assembled.LineCount == 0;
    return assembled;
}

fn persistDiskBackedFrameOutput(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    output_file: *types.FileObject,
    input_file: ?*types.FileObject,
) !?isize {
    if (output_file.Filename.len == 0) {
        return null;
    }

    const assembled = try buildSavedFileContents(allocator, frame, output_file, input_file);
    if (!try writeLineRangeToDisk(
        editor,
        allocator,
        output_file,
        assembled.FirstLine,
        assembled.LastLine,
    )) {
        return null;
    }

    if (input_file) |input| {
        input.RewindFirstLine = assembled.FirstLine;
        input.RewindLastLine = assembled.LastLine;
        input.RewindLineCount = assembled.LineCount;
    }
    return assembled.LineCount;
}

fn persistDiskBackedOutputFile(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    output_file: *types.FileObject,
) !bool {
    if (output_file.Filename.len == 0) {
        return true;
    }
    return writeLineRangeToDisk(
        editor,
        allocator,
        output_file,
        output_file.FirstLine,
        output_file.LastLine,
    );
}

fn fileReadBuffered(file: *types.FileObject, requested_count: isize, best_try: bool) ?ReadResult {
    if (file.OutputFlag or requested_count < 0) {
        return null;
    }

    var count = requested_count;
    if (file.LineCount < count) {
        if (!best_try) {
            return null;
        }
        count = file.LineCount;
    }
    if (count == 0) {
        return .{};
    }

    const first = file.FirstLine orelse return null;
    const last = file.LastLine orelse return null;
    if (file.LineCount == count) {
        setFileQueue(file, null, null, 0);
        file.Eof = true;
        file.LCounter += count;
        return .{
            .first = first,
            .last = last,
            .count = count,
        };
    }

    var split_last = first;
    var remaining: isize = count;
    while (remaining > 1) : (remaining -= 1) {
        split_last = split_last.FLink orelse return null;
    }
    const next = split_last.FLink orelse return null;
    next.BLink = null;
    split_last.FLink = null;
    file.FirstLine = next;
    file.LineCount -= count;
    file.Eof = false;
    file.LCounter += count;
    return .{
        .first = first,
        .last = split_last,
        .count = count,
    };
}

fn fileWriteBuffered(
    allocator: std.mem.Allocator,
    first: *types.LineHdrObject,
    last: *types.LineHdrObject,
    file: *types.FileObject,
) !bool {
    if (!file.OutputFlag) {
        return false;
    }
    const cloned = try cloneLineRange(allocator, first, last);
    try appendToFile(file, cloned.first, cloned.last);
    return true;
}

fn fileFixEOP(
    allocator: std.mem.Allocator,
    eof: bool,
    eop_line: *types.LineHdrObject,
) !void {
    const prefix = if (eof) "<End of File>   " else "<Page Boundary> ";
    const frame_name = if (eop_line.Group != null and eop_line.Group.?.Frame.Span != null)
        eop_line.Group.?.Frame.Span.?.Name
    else
        "";
    try line_ops.setSentinelDisplayContent(allocator, eop_line, prefix, frame_name);
}

fn computeLineRange(
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
    mark: ?*types.MarkObject,
) ?LineSelection {
    const dot = frame.Dot orelse return null;
    var first_line: ?*types.LineHdrObject = dot.Line;
    var last_line: ?*types.LineHdrObject = dot.Line;

    switch (rept) {
        .LeadParamNone, .LeadParamPlus, .LeadParamPInt => {
            if (count == 0) {
                first_line = null;
            } else if (count <= 20) {
                var line_nr: isize = 1;
                while (line_nr < count) : (line_nr += 1) {
                    last_line = last_line.?.FLink orelse return null;
                }
                if (last_line.?.FLink == null) {
                    return null;
                }
            } else {
                const line_nr = line_ops.LineToNumber(first_line.?);
                last_line = line_ops.LineFromNumber(frame, line_nr + count - 1) orelse return null;
                if (last_line.?.FLink == null) {
                    return null;
                }
            }
        },
        .LeadParamMinus, .LeadParamNInt => {
            const abs_count = -count;
            last_line = dot.Line.BLink orelse return null;
            if (abs_count <= 20) {
                var line_nr: isize = 1;
                while (line_nr <= abs_count) : (line_nr += 1) {
                    first_line = first_line.?.BLink orelse return null;
                }
            } else {
                var line_nr = line_ops.LineToNumber(last_line.?);
                if (abs_count > line_nr) {
                    return null;
                }
                line_nr = line_nr - abs_count + 1;
                first_line = line_ops.LineFromNumber(frame, line_nr);
            }
        },
        .LeadParamPIndef => {
            if (dot.Line.FLink == null) {
                first_line = null;
            } else {
                last_line = frame.LastGroup.?.LastLine.?.BLink;
            }
        },
        .LeadParamNIndef => {
            last_line = dot.Line.BLink;
            if (last_line == null) {
                first_line = null;
            } else {
                first_line = frame.FirstGroup.?.FirstLine;
            }
        },
        .LeadParamMarker => {
            const mark_line = mark orelse return null;
            if (mark_line.Line == first_line.?) {
                first_line = null;
            } else if (mark_line.Line.FLink == first_line.?) {
                first_line = mark_line.Line;
                last_line = mark_line.Line;
            } else if (mark_line.Line.BLink == first_line.?) {
                last_line = first_line.?;
            } else {
                const mark_line_nr = line_ops.LineToNumber(mark_line.Line);
                const line_nr = line_ops.LineToNumber(dot.Line);
                if (mark_line_nr < line_nr) {
                    first_line = mark_line.Line;
                    last_line = last_line.?.BLink;
                } else {
                    last_line = mark_line.Line.BLink;
                }
            }
        },
    }

    return .{
        .first = first_line,
        .last = last_line,
    };
}

pub fn fileReadCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
) !bool {
    if (editor.FgiFile <= 0 or editor.FgiFile > types.MaxFiles) {
        return false;
    }
    const input_file = editor.Files[@intCast(editor.FgiFile)] orelse return false;
    const lines_to_read = if (rept == .LeadParamPIndef) types.MaxInt else count;
    const read_result = fileReadBuffered(input_file, lines_to_read, rept == .LeadParamPIndef) orelse return false;
    if (read_result.first) |first| {
        const last = read_result.last.?;
        try line_ops.linesInject(allocator, first, last, frame.Dot.?.Line);
        try mark_ops.MarkCreate(allocator, first, 1, &frame.Marks[types.MarkEquals]);
        frame.TextModified = true;
        const after = last.FLink.?;
        try mark_ops.MarkCreate(allocator, after, 1, &frame.Marks[types.MarkModified]);
        try mark_ops.MarkCreate(allocator, after, 1, &frame.Dot);
    }
    return true;
}

pub fn fileWriteCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    rept: types.LeadParam,
    count: isize,
    mark: ?*types.MarkObject,
) !bool {
    if (editor.FgoFile <= 0 or editor.FgoFile > types.MaxFiles) {
        return false;
    }
    const output_file = editor.Files[@intCast(editor.FgoFile)] orelse return false;
    const range = computeLineRange(frame, rept, count, mark) orelse return false;
    if (range.first) |first| {
        return fileWriteBuffered(allocator, first, range.last.?, output_file);
    }
    return true;
}

pub fn filePage(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !bool {
    const page_out = computeLineRange(frame, .LeadParamNIndef, 0, null) orelse return false;
    if (page_out.first) |first| {
        const last = page_out.last.?;
        if (frame.OutputFile != 0) {
            const output_file = editor.Files[@intCast(frame.OutputFile)] orelse return false;
            if (!try fileWriteBuffered(allocator, first, last, output_file)) {
                editor.ExitAbort = true;
                return false;
            }
        }
        const after = last.FLink orelse return false;
        try mark_ops.MarksSqueeze(allocator, first, 1, after, 1);
        line_ops.linesExtract(first, last);
    }

    if (frame.InputFile == 0) {
        frame.DirtyLine = 1;
        return true;
    }
    const input_file = editor.Files[@intCast(frame.InputFile)] orelse return false;
    while (frame.SpaceLeft * 10 > frame.SpaceLimit and !editor.TtControlC) {
        const read_result = fileReadBuffered(input_file, 50, true) orelse return false;
        frame.InputCount += read_result.count;
        if (read_result.first == null) {
            break;
        }
        try line_ops.linesInject(allocator, read_result.first.?, read_result.last.?, frame.LastGroup.?.LastLine.?);
        if (frame.Dot.?.Line.FLink == null) {
            try mark_ops.MarkCreate(allocator, read_result.first.?, frame.Dot.?.Col, &frame.Dot);
        }
    }

    try fileFixEOP(allocator, input_file.Eof, frame.LastGroup.?.LastLine.?);
    frame.DirtyLine = 1;
    return true;
}

fn refreshFrameSpanMarks(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !void {
    if (frame.Span) |span| {
        try mark_ops.MarkCreate(allocator, frame.FirstGroup.?.FirstLine.?, 1, &span.MarkOne);
        try mark_ops.MarkCreate(allocator, frame.LastGroup.?.LastLine.?, 1, &span.MarkTwo);
    }
}

fn clearFrameText(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !void {
    const sentinel = frame.LastGroup.?.LastLine.?;
    const last_content = sentinel.BLink;
    if (last_content == null) {
        try mark_ops.MarkCreate(allocator, sentinel, 1, &frame.Dot);
        try refreshFrameSpanMarks(allocator, frame);
        return;
    }

    const first_content = frame.FirstGroup.?.FirstLine.?;
    try mark_ops.MarksSqueeze(allocator, first_content, 1, sentinel, 1);
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

    try line_ops.LineChangeLength(allocator, sentinel, 0);
    try mark_ops.MarkCreate(allocator, sentinel, 1, &frame.Dot);
    try refreshFrameSpanMarks(allocator, frame);
}

fn findBufferedInputByFilename(
    editor: *state.Editor,
    file_name: []const u8,
) ?*types.FileObject {
    var slot: usize = 1;
    while (slot <= types.MaxFiles) : (slot += 1) {
        const file = editor.Files[slot] orelse continue;
        if (!file.OutputFlag and std.mem.eql(u8, file.Filename, file_name)) {
            return file;
        }
    }
    return null;
}

fn injectFileIntoFrame(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    source: *const types.FileObject,
) !bool {
    try clearFrameText(allocator, frame);

    const source_first = if (source.RewindFirstLine != null) source.RewindFirstLine else source.FirstLine;
    const source_last = if (source.RewindLastLine != null) source.RewindLastLine else source.LastLine;
    if (source_first != null and source_last != null) {
        const cloned = try cloneLineRange(allocator, source_first.?, source_last.?);
        try line_ops.linesInject(allocator, cloned.first, cloned.last, frame.LastGroup.?.LastLine.?);
        if (frame.Dot.?.Line.FLink == null) {
            try mark_ops.MarkCreate(allocator, cloned.first, frame.Dot.?.Col, &frame.Dot);
        }
    }

    try refreshFrameSpanMarks(allocator, frame);
    return true;
}

fn getFreeSlot(editor: *const state.Editor, reserved_slot: isize) ?isize {
    var slot: isize = 1;
    while (slot <= types.MaxFiles) : (slot += 1) {
        if (slot == reserved_slot) {
            continue;
        }
        if (editor.Files[@intCast(slot)] == null) {
            return slot;
        }
    }
    return null;
}

fn getFileSlot(editor: *state.Editor, slot: isize) ?*types.FileObject {
    if (slot <= 0 or slot > types.MaxFiles) {
        return null;
    }
    return editor.Files[@intCast(slot)];
}

fn requireFileSlot(editor: *state.Editor, slot: isize, output_flag: bool) ?*types.FileObject {
    const file = getFileSlot(editor, slot) orelse return null;
    if (file.OutputFlag != output_flag) {
        return null;
    }
    return file;
}

pub fn fileOpenCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    command: types.Commands,
    file_name: []const u8,
) !bool {
    return switch (command) {
        .CmdFileInput => blk: {
            if (frame.InputFile != 0) {
                break :blk false;
            }
            const slot = getFreeSlot(editor, 0) orelse break :blk false;
            const input_file = (try makeDiskInputFile(editor, allocator, file_name)) orelse break :blk false;
            editor.Files[@intCast(slot)] = input_file;
            editor.FilesFrames[@intCast(slot)] = frame;
            frame.InputFile = slot;
            break :blk try pageFileWithLoadingMessage(editor, allocator, frame);
        },
        .CmdFileGlobalInput => blk: {
            if (editor.FgiFile != 0) {
                break :blk false;
            }
            const slot = getFreeSlot(editor, 0) orelse break :blk false;
            const input_file = (try makeDiskInputFile(editor, allocator, file_name)) orelse break :blk false;
            editor.Files[@intCast(slot)] = input_file;
            editor.FgiFile = slot;
            break :blk true;
        },
        .CmdFileOutput => blk: {
            if (frame.OutputFile != 0) {
                break :blk false;
            }
            const slot = getFreeSlot(editor, 0) orelse break :blk false;
            const related_name = if (frame.InputFile != 0)
                (requireFileSlot(editor, frame.InputFile, false) orelse break :blk false).Filename
            else
                null;
            const output_file = (try makeDiskOutputFile(editor, allocator, file_name, .{ .related_name = related_name })) orelse break :blk false;
            editor.Files[@intCast(slot)] = output_file;
            editor.FilesFrames[@intCast(slot)] = frame;
            frame.OutputFile = slot;
            break :blk true;
        },
        .CmdFileGlobalOutput => blk: {
            if (editor.FgoFile != 0) {
                break :blk false;
            }
            const slot = getFreeSlot(editor, 0) orelse break :blk false;
            const output_file = (try makeDiskOutputFile(editor, allocator, file_name, .{})) orelse break :blk false;
            editor.Files[@intCast(slot)] = output_file;
            editor.FgoFile = slot;
            break :blk true;
        },
        .CmdFileEdit => blk: {
            if (frame.InputFile != 0 or frame.OutputFile != 0) {
                break :blk false;
            }
            const input_slot = getFreeSlot(editor, 0) orelse break :blk false;
            const output_slot = getFreeSlot(editor, input_slot) orelse break :blk false;
            const input_file = (try makeDiskInputFile(editor, allocator, file_name)) orelse break :blk false;
            const output_file = (try makeDiskOutputFile(editor, allocator, file_name, .{ .related_name = input_file.Filename })) orelse break :blk false;
            editor.Files[@intCast(input_slot)] = input_file;
            editor.FilesFrames[@intCast(input_slot)] = frame;
            frame.InputFile = input_slot;
            editor.Files[@intCast(output_slot)] = output_file;
            editor.FilesFrames[@intCast(output_slot)] = frame;
            frame.OutputFile = output_slot;
            break :blk try pageFileWithLoadingMessage(editor, allocator, frame);
        },
        else => false,
    };
}

pub fn fileRewindCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !bool {
    const input_file = requireFileSlot(editor, frame.InputFile, false) orelse return false;
    if (!try loadFileQueueFromSnapshot(allocator, input_file)) {
        return false;
    }
    if (frame.Dot.?.Line.FLink == null) {
        try clearFrameText(allocator, frame);
    }
    return filePage(editor, allocator, frame);
}

pub fn fileGlobalRewindCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
) !bool {
    const input_file = requireFileSlot(editor, editor.FgiFile, false) orelse return false;
    return loadFileQueueFromSnapshot(allocator, input_file);
}

pub fn loadBufferedFileIntoFrameByName(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    file_name: []const u8,
) !bool {
    if (findBufferedInputByFilename(editor, file_name)) |source| {
        return injectFileIntoFrame(allocator, frame, source);
    }
    const source = (try makeDiskInputFile(editor, allocator, file_name)) orelse return false;
    return injectFileIntoFrame(allocator, frame, source);
}

fn copyUnreadInputToOutput(
    allocator: std.mem.Allocator,
    input_file: *types.FileObject,
    output_file: *types.FileObject,
) !void {
    if (input_file.FirstLine == null or input_file.LastLine == null) {
        return;
    }
    const cloned = try cloneLineRange(allocator, input_file.FirstLine.?, input_file.LastLine.?);
    try appendToFile(output_file, cloned.first, cloned.last);
}

fn detachFileSlot(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    slot: isize,
) !bool {
    _ = getFileSlot(editor, slot) orelse return false;
    const slot_index: usize = @intCast(slot);

    if (editor.FilesFrames[slot_index]) |frame| {
        if (slot == frame.OutputFile) {
            frame.OutputFile = 0;
        } else {
            frame.InputFile = 0;
            try fileFixEOP(allocator, true, frame.LastGroup.?.LastLine.?);
            frame.DirtyLine = 1;
        }
        editor.FilesFrames[slot_index] = null;
    } else if (slot == editor.FgiFile) {
        editor.FgiFile = 0;
    } else if (slot == editor.FgoFile) {
        editor.FgoFile = 0;
    }

    editor.Files[slot_index] = null;
    return true;
}

pub fn fileSaveCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !bool {
    const output_file = requireFileSlot(editor, frame.OutputFile, true) orelse return false;
    if (!frame.TextModified) {
        return true;
    }

    if (output_file.Filename.len > 0) {
        const input_file = if (frame.InputFile != 0)
            requireFileSlot(editor, frame.InputFile, false) orelse return false
        else
            null;
        const lines_read_before_save = frame.InputCount;
        const total_saved = (try persistDiskBackedFrameOutput(editor, allocator, frame, output_file, input_file)) orelse return false;
        frame.InputCount = total_saved;
        output_file.LCounter = total_saved;
        if (input_file) |input| {
            input.LCounter = lines_read_before_save + input.LineCount;
        }
    } else {
        const last = frame.LastGroup.?.LastLine.?.BLink;
        if (last != null) {
            const first = frame.FirstGroup.?.FirstLine.?;
            if (!try fileWriteBuffered(allocator, first, last.?, output_file)) {
                return false;
            }
        }

        if (frame.InputFile != 0) {
            const input_file = requireFileSlot(editor, frame.InputFile, false) orelse return false;
            const lines_read_before_save = frame.InputCount;
            try copyUnreadInputToOutput(allocator, input_file, output_file);
            frame.InputCount = output_file.LCounter;
            input_file.LCounter = lines_read_before_save + input_file.LineCount;
        } else {
            frame.InputCount = output_file.LCounter;
        }
    }

    frame.TextModified = false;
    mark_ops.MarkDestroy(allocator, &frame.Marks[types.MarkModified]);
    return true;
}

pub fn fileKillCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !bool {
    const output_file = requireFileSlot(editor, frame.OutputFile, true) orelse {
        emitNoFileOpenMessage(editor);
        return false;
    };
    if (output_file.Tnm.len > 0) {
        sys_ops.deleteFile(output_file.Tnm) catch {};
    }
    if (!try detachFileSlot(editor, allocator, frame.OutputFile)) {
        return false;
    }
    emitOutputDeletedMessage(editor, output_file);
    return true;
}

pub fn fileGlobalKillCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
) !bool {
    const output_file = requireFileSlot(editor, editor.FgoFile, true) orelse {
        emitNoFileOpenMessage(editor);
        return false;
    };
    if (output_file.Tnm.len > 0) {
        sys_ops.deleteFile(output_file.Tnm) catch {};
    }
    if (!try detachFileSlot(editor, allocator, editor.FgoFile)) {
        return false;
    }
    emitOutputDeletedMessage(editor, output_file);
    return true;
}

pub fn fileCloseCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    command: types.Commands,
) !bool {
    return switch (command) {
        .CmdFileInput => blk: {
            _ = requireFileSlot(editor, frame.InputFile, false) orelse break :blk false;
            break :blk try detachFileSlot(editor, allocator, frame.InputFile);
        },
        .CmdFileOutput => blk: {
            const output_file = requireFileSlot(editor, frame.OutputFile, true) orelse break :blk false;
            const had_modifications = frame.TextModified;
            if (had_modifications and !try fileSaveCommand(editor, allocator, frame)) {
                break :blk false;
            }
            if (!had_modifications and !try persistDiskBackedOutputFile(editor, allocator, output_file)) {
                break :blk false;
            }
            break :blk try detachFileSlot(editor, allocator, frame.OutputFile);
        },
        .CmdFileEdit => blk: {
            _ = requireFileSlot(editor, frame.InputFile, false) orelse break :blk false;
            _ = requireFileSlot(editor, frame.OutputFile, true) orelse break :blk false;
            if (frame.TextModified and !try fileSaveCommand(editor, allocator, frame)) {
                break :blk false;
            }
            if (!try detachFileSlot(editor, allocator, frame.OutputFile)) {
                break :blk false;
            }
            break :blk try detachFileSlot(editor, allocator, frame.InputFile);
        },
        .CmdFileGlobalInput => blk: {
            _ = requireFileSlot(editor, editor.FgiFile, false) orelse break :blk false;
            break :blk try detachFileSlot(editor, allocator, editor.FgiFile);
        },
        .CmdFileGlobalOutput => blk: {
            const output_file = requireFileSlot(editor, editor.FgoFile, true) orelse break :blk false;
            if (!try persistDiskBackedOutputFile(editor, allocator, output_file)) {
                break :blk false;
            }
            break :blk try detachFileSlot(editor, allocator, editor.FgoFile);
        },
        else => false,
    };
}

fn closeFrameFilesForQuit(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    slot: isize,
) !bool {
    const output_slot = if (frame.OutputFile != 0 and getFileSlot(editor, frame.OutputFile) != null)
        frame.OutputFile
    else
        0;
    const input_slot = if (frame.InputFile != 0 and getFileSlot(editor, frame.InputFile) != null)
        frame.InputFile
    else
        0;

    if (output_slot != 0) {
        if (output_slot != slot) {
            return true;
        }
        const output_file = requireFileSlot(editor, output_slot, true) orelse return false;
        const had_modifications = frame.TextModified;

        if (had_modifications and !try fileSaveCommand(editor, allocator, frame)) {
            return false;
        }

        if (input_slot != 0) {
            const input_file = requireFileSlot(editor, input_slot, false) orelse return false;
            if (editor.LudwigMode == .LudwigBatch and editor.BatchOutputEnabled) {
                emitInputClosedMessage(editor, input_file);
            }
            if (!try detachFileSlot(editor, allocator, input_slot)) {
                return false;
            }
        }

        if (had_modifications and output_file.Filename.len > 0 and editor.LudwigMode == .LudwigBatch and editor.BatchOutputEnabled) {
            emitOutputCreatedMessage(editor, output_file);
        }
        return detachFileSlot(editor, allocator, output_slot);
    }

    if (input_slot != 0 and input_slot == slot) {
        const input_file = requireFileSlot(editor, input_slot, false) orelse return false;
        if (editor.LudwigMode == .LudwigBatch and editor.BatchOutputEnabled) {
            emitInputClosedMessage(editor, input_file);
        }
        return detachFileSlot(editor, allocator, input_slot);
    }

    return true;
}

fn closeGlobalInputForQuit(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
) !bool {
    const input_file = requireFileSlot(editor, editor.FgiFile, false) orelse return false;
    if (editor.LudwigMode == .LudwigBatch and editor.BatchOutputEnabled) {
        emitInputClosedMessage(editor, input_file);
    }
    return detachFileSlot(editor, allocator, editor.FgiFile);
}

fn closeGlobalOutputForQuit(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
) !bool {
    const output_file = requireFileSlot(editor, editor.FgoFile, true) orelse return false;
    if (!try persistDiskBackedOutputFile(editor, allocator, output_file)) {
        return false;
    }
    if (output_file.Filename.len > 0 and editor.LudwigMode == .LudwigBatch and editor.BatchOutputEnabled) {
        emitOutputCreatedMessage(editor, output_file);
    }
    return detachFileSlot(editor, allocator, editor.FgoFile);
}

fn closeUnattachedSlotForQuit(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    slot: isize,
) !bool {
    const file = getFileSlot(editor, slot) orelse return false;
    if (file.OutputFlag) {
        if (!try persistDiskBackedOutputFile(editor, allocator, file)) {
            return false;
        }
        if (file.Filename.len > 0 and editor.LudwigMode == .LudwigBatch and editor.BatchOutputEnabled) {
            emitOutputCreatedMessage(editor, file);
        }
    } else if (editor.LudwigMode == .LudwigBatch and editor.BatchOutputEnabled) {
        emitInputClosedMessage(editor, file);
    }
    return detachFileSlot(editor, allocator, slot);
}

pub fn quitCloseFiles(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
) !bool {
    var slot: isize = 1;
    while (slot <= types.MaxFiles) : (slot += 1) {
        const slot_index: usize = @intCast(slot);
        if (editor.Files[slot_index] == null) {
            continue;
        }

        if (editor.FilesFrames[slot_index]) |frame| {
            if (!try closeFrameFilesForQuit(editor, allocator, frame, slot)) {
                return false;
            }
            continue;
        }

        if (slot == editor.FgiFile) {
            if (!try closeGlobalInputForQuit(editor, allocator)) {
                return false;
            }
            continue;
        }

        if (slot == editor.FgoFile) {
            if (!try closeGlobalOutputForQuit(editor, allocator)) {
                return false;
            }
            continue;
        }

        if (!try closeUnattachedSlotForQuit(editor, allocator, slot)) {
            return false;
        }
    }

    return true;
}

pub fn makeBufferedFile(
    allocator: std.mem.Allocator,
    contents: []const []const u8,
    output_flag: bool,
) !*types.FileObject {
    const file = try allocator.create(types.FileObject);
    file.* = .{
        .Valid = true,
        .OutputFlag = output_flag,
    };
    if (try buildLineRangeFromContents(allocator, contents)) |range| {
        setFileQueue(file, range.first, range.last, @intCast(contents.len));
    }
    if (try buildLineRangeFromContents(allocator, contents)) |range| {
        file.RewindFirstLine = range.first;
        file.RewindLastLine = range.last;
        file.RewindLineCount = @intCast(contents.len);
    }
    file.Eof = contents.len == 0;
    return file;
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

test "file table writes current file usage into report frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const root = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const work = (try @import("frame.zig").FrameEdit(&editor, allocator, root.frame, "WORK")).?;
    const oops = (try @import("frame.zig").FrameEdit(&editor, allocator, work, "OOPS")).?;

    const input = try allocator.create(types.FileObject);
    input.* = .{
        .Filename = "input.txt",
        .Eof = true,
    };
    editor.Files[1] = input;
    editor.FilesFrames[1] = work;
    work.InputFile = 1;
    work.TextModified = true;

    const output = try allocator.create(types.FileObject);
    output.* = .{
        .Filename = "output.txt",
        .OutputFlag = true,
    };
    editor.Files[2] = output;
    editor.FilesFrames[2] = work;
    work.OutputFile = 2;

    const global_input = try allocator.create(types.FileObject);
    global_input.* = .{
        .Filename = "global.in",
    };
    editor.Files[3] = global_input;
    editor.FgiFile = 3;

    const global_output = try allocator.create(types.FileObject);
    global_output.* = .{
        .Filename = "global.out",
        .OutputFlag = true,
    };
    editor.Files[4] = global_output;
    editor.FgoFile = 4;

    try std.testing.expect(try fileTable(&editor, allocator, oops));
    try expectFrameLines(oops, &[_][]const u8{
        "Usage   Mod Frame  Filename",
        "------- --- ------ --------",
        "",
        "FI  EOF  * WORK   input.txt",
        "FO       * WORK   output.txt",
        "FGI               global.in",
        "FGO               global.out",
    });
}

test "file table shows none when no files are open" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const root = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const oops = (try @import("frame.zig").FrameEdit(&editor, allocator, root.frame, "OOPS")).?;

    try std.testing.expect(try fileTable(&editor, allocator, oops));
    try expectFrameLines(oops, &[_][]const u8{
        "Usage   Mod Frame  Filename",
        "------- --- ------ --------",
        "",
        "<none>",
    });
}

test "file save appends frame and unread input to output buffer" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{
        "visible1",
        "visible2",
    });
    const input = try makeBufferedFile(allocator, &[_][]const u8{
        "tail1",
        "tail2",
    }, false);
    editor.Files[1] = input;
    editor.FilesFrames[1] = fixture.frame;
    fixture.frame.InputFile = 1;

    const output = try makeBufferedFile(allocator, &[_][]const u8{
        "paged",
    }, true);
    editor.Files[2] = output;
    editor.FilesFrames[2] = fixture.frame;
    fixture.frame.OutputFile = 2;
    fixture.frame.TextModified = true;
    try mark_ops.MarkCreate(allocator, fixture.content_lines[1], fixture.content_lines[1].Used + 1, &fixture.frame.Marks[types.MarkModified]);

    try std.testing.expect(try fileSaveCommand(&editor, allocator, fixture.frame));
    try std.testing.expect(!fixture.frame.TextModified);
    try std.testing.expect(fixture.frame.Marks[types.MarkModified] == null);
    try std.testing.expectEqual(@as(isize, 5), output.LineCount);
    try std.testing.expectEqualStrings("paged", line_ops.getLineContent(output.FirstLine));
    try std.testing.expectEqualStrings("visible1", line_ops.getLineContent(output.FirstLine.?.FLink));
    try std.testing.expectEqualStrings("visible2", line_ops.getLineContent(output.FirstLine.?.FLink.?.FLink));
    try std.testing.expectEqualStrings("tail1", line_ops.getLineContent(output.FirstLine.?.FLink.?.FLink.?.FLink));
    try std.testing.expectEqualStrings("tail2", line_ops.getLineContent(output.LastLine));
}

test "file kill detaches current output file" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const output = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    editor.Files[1] = output;
    editor.FilesFrames[1] = fixture.frame;
    fixture.frame.OutputFile = 1;

    try std.testing.expect(try fileKillCommand(&editor, allocator, fixture.frame));
    try std.testing.expectEqual(@as(isize, 0), fixture.frame.OutputFile);
    try std.testing.expect(editor.Files[1] == null);
    try std.testing.expect(editor.FilesFrames[1] == null);
}

test "file kill queues interactive deleted status message" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.LudwigMode = .LudwigScreen;

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const output = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    output.Filename = "output.txt";
    output.Tnm = "output.txt-lw";
    editor.Files[1] = output;
    editor.FilesFrames[1] = fixture.frame;
    fixture.frame.OutputFile = 1;

    try std.testing.expect(try fileKillCommand(&editor, allocator, fixture.frame));
    try std.testing.expectEqualStrings(
        "Output file output.txt-lw deleted.",
        interactive_io.takeStatusMessage().?,
    );
}

test "file kill queues no-file-open status message when no output is attached" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.LudwigMode = .LudwigScreen;

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});

    try std.testing.expect(!try fileKillCommand(&editor, allocator, fixture.frame));
    try std.testing.expectEqualStrings(no_file_open_message, interactive_io.takeStatusMessage().?);
}

test "file close detaches current input file and marks eof" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const input = try makeBufferedFile(allocator, &[_][]const u8{"tail"}, false);
    editor.Files[1] = input;
    editor.FilesFrames[1] = fixture.frame;
    fixture.frame.InputFile = 1;

    try std.testing.expect(try fileCloseCommand(&editor, allocator, fixture.frame, .CmdFileInput));
    try std.testing.expectEqual(@as(isize, 0), fixture.frame.InputFile);
    try std.testing.expect(editor.Files[1] == null);
    try std.testing.expectEqualStrings("<End of File>", line_ops.getDisplayLineContent(fixture.frame.LastGroup.?.LastLine.?));
}

test "file close detaches global output file" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const output = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    editor.Files[1] = output;
    editor.FgoFile = 1;

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    try std.testing.expect(try fileCloseCommand(&editor, allocator, fixture.frame, .CmdFileGlobalOutput));
    try std.testing.expectEqual(@as(isize, 0), editor.FgoFile);
    try std.testing.expect(editor.Files[1] == null);
}

test "file save rotates disk backups and updates memory file" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    editor.FileData.Versions = 2;

    const file_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/save.txt", .{tmp_dir.sub_path});
    const backup1_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/save.txt~1", .{tmp_dir.sub_path});
    const backup2_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/save.txt~2", .{tmp_dir.sub_path});
    const memory_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/memory.txt", .{tmp_dir.sub_path});
    const expanded_memory = (try sys_ops.expandFilename(allocator, memory_path)) orelse return error.TestUnexpectedResult;

    try tmp_dir.dir.writeFile(.{ .sub_path = "save.txt", .data = "old\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "save.txt~1", .data = "older\n" });

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"new"});
    const output = (try openDiskOutputFile(&editor, allocator, file_path, .{ .memory = expanded_memory })) orelse return error.TestUnexpectedResult;
    editor.Files[1] = output;
    editor.FilesFrames[1] = fixture.frame;
    fixture.frame.OutputFile = 1;
    fixture.frame.TextModified = true;
    try mark_ops.MarkCreate(allocator, fixture.content_lines[0], fixture.content_lines[0].Used + 1, &fixture.frame.Marks[types.MarkModified]);

    try std.testing.expect(try fileSaveCommand(&editor, allocator, fixture.frame));

    const saved = try std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize));
    try std.testing.expectEqualStrings("new\n", saved);
    const old_backup = try std.fs.cwd().readFileAlloc(allocator, backup1_path, std.math.maxInt(usize));
    try std.testing.expectEqualStrings("older\n", old_backup);
    const new_backup = try std.fs.cwd().readFileAlloc(allocator, backup2_path, std.math.maxInt(usize));
    try std.testing.expectEqualStrings("old\n", new_backup);
    const remembered = try std.fs.cwd().readFileAlloc(allocator, memory_path, std.math.maxInt(usize));
    const expected_memory = try std.fmt.allocPrint(allocator, "{s}\n", .{output.Filename});
    try std.testing.expectEqualStrings(expected_memory, remembered);
}
