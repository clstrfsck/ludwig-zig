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
    if (file.filename.len <= max_len) {
        return allocator.dupe(u8, file.filename);
    }

    const tail_len = @divFloor(max_len - 3, 2);
    const head_len = max_len - 3 - tail_len;
    return std.fmt.allocPrint(
        allocator,
        "{s}---{s}",
        .{
            file.filename[0..head_len],
            file.filename[file.filename.len - tail_len ..],
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
    if (editor.files_frames[slot] != null) {
        return if (file.output_flag) "FO" else "FI";
    }
    if (slot == @as(usize, @intCast(editor.fgi_file))) {
        return "FGI";
    }
    if (slot == @as(usize, @intCast(editor.fgo_file))) {
        return "FGO";
    }
    return if (file.output_flag) "FFO" else "FFI";
}

fn reportNameWidth(editor: *const state.Editor) usize {
    if (editor.ludwig_mode == .ludwig_screen and editor.terminal_info.width > 19) {
        return @intCast(@max(editor.terminal_info.width - 19, 5));
    }
    return types.file_name_len;
}

fn renderFileLine(editor: *const state.Editor, allocator: std.mem.Allocator, slot: usize, file: *const types.FileObject) ![]const u8 {
    const frame = editor.files_frames[slot];
    const usage = try padRight(allocator, usageLabel(editor, slot, file), 3);
    const eof_status: []const u8 = if (file.eof) "EOF" else "   ";
    const mod_status: []const u8 = if (frame != null and frame.?.text_modified) " * " else "   ";
    const frame_name = try padRight(allocator, if (frame != null and frame.?.span != null) frame.?.span.?.name else "", 6);
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
    const frame = editor.files_frames[slot];
    const usage = try padRight(allocator, usageLabel(editor, slot, file), 3);
    const eof_status: []const u8 = if (file.eof) "EOF" else "   ";
    const mod_status: []const u8 = if (frame != null and frame.?.text_modified) " * " else "   ";
    const frame_name = try padRight(allocator, if (frame != null and frame.?.span != null) frame.?.span.?.name else "", 6);
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

pub fn fileTable(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    report_frame: *types.FrameObject,
) !bool {
    var lines: std.ArrayList([]const u8) = .{};
    try lines.append(allocator, "Usage   Mod Frame  Filename");
    try lines.append(allocator, "------- --- ------ --------");
    try lines.append(allocator, "");

    var have_files = false;
    var slot: usize = 1;
    while (slot <= types.max_files) : (slot += 1) {
        const file = editor.files[slot] orelse continue;
        have_files = true;
        try lines.append(allocator, try renderFileLine(editor, allocator, slot, file));
    }
    if (!have_files) {
        try lines.append(allocator, "<none>");
    }

    const ok = try replaceReportFrame(allocator, report_frame, lines.items);
    if (ok) {
        switch (editor.ludwig_mode) {
            .ludwig_screen => try interactive_io.showTemporaryReport(allocator, lines.items),
            .ludwig_batch, .ludwig_hardcopy => if (editor.batch_output_enabled) {
                var batch_lines: std.ArrayList([]const u8) = .{};
                try batch_lines.append(allocator, "Usage   Mod Frame  Filename");
                try batch_lines.append(allocator, "------- --- ------ --------");
                try batch_lines.append(allocator, "");

                if (have_files) {
                    slot = 1;
                    while (slot <= types.max_files) : (slot += 1) {
                        const file = editor.files[slot] orelse continue;
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
        line = line.f_link orelse return null;
    }
    return count;
}

fn cloneLineRange(
    allocator: std.mem.Allocator,
    first: *const types.LineHdrObject,
    last: *const types.LineHdrObject,
) !line_ops.LineRange {
    const line_count = countRange(first, last) orelse return error.InvalidLineRange;
    const range = try line_ops.linesCreate(allocator, line_count);

    var src = first;
    var dst = range.first;
    while (true) {
        if (src.used > 0) {
            try line_ops.lineChangeLength(allocator, dst, src.used);
            try line_ops.setLineContent(dst, src.str.?.slice(1, src.used));
        } else {
            dst.used = 0;
        }
        if (src == last) {
            break;
        }
        src = src.f_link.?;
        dst = dst.f_link.?;
    }
    return range;
}

fn setFileQueue(
    file: *types.FileObject,
    first: ?*types.LineHdrObject,
    last: ?*types.LineHdrObject,
    line_count: isize,
) void {
    file.first_line = first;
    file.last_line = last;
    file.line_count = line_count;
}

fn buildLineRangeFromContents(
    allocator: std.mem.Allocator,
    contents: []const []const u8,
) !?line_ops.LineRange {
    if (contents.len == 0) {
        return null;
    }

    const range = try line_ops.linesCreate(allocator, contents.len);
    var line = range.first;
    for (contents, 0..) |content, index| {
        if (content.len > 0) {
            try line_ops.lineChangeLength(allocator, line, @intCast(content.len));
            try line_ops.setLineContent(line, content);
        } else {
            line.used = 0;
        }
        if (index + 1 < contents.len) {
            line = line.f_link.?;
        }
    }
    return range;
}

fn loadFileQueueFromSnapshot(
    allocator: std.mem.Allocator,
    file: *types.FileObject,
) !bool {
    setFileQueue(file, null, null, 0);
    file.l_counter = 0;
    if (file.rewind_first_line == null or file.rewind_last_line == null or file.rewind_line_count == 0) {
        file.eof = true;
        return true;
    }

    const cloned = try cloneLineRange(allocator, file.rewind_first_line.?, file.rewind_last_line.?);
    setFileQueue(file, cloned.first, cloned.last, file.rewind_line_count);
    file.eof = false;
    return true;
}

fn appendToFile(file: *types.FileObject, first: *types.LineHdrObject, last: *types.LineHdrObject) !void {
    const appended = countRange(first, last) orelse return error.InvalidLineRange;
    if (file.last_line) |tail| {
        tail.f_link = first;
        first.b_link = tail;
    } else {
        file.first_line = first;
        first.b_link = null;
    }
    file.last_line = last;
    file.line_count += @intCast(appended);
    file.l_counter += @intCast(appended);
}

fn linePlural(count: isize) []const u8 {
    return if (count == 1) "" else "s";
}

fn emitStatusMessage(editor: *const state.Editor, message: []const u8) void {
    switch (editor.ludwig_mode) {
        .ludwig_screen => interactive_io.queueStatusMessage(message),
        .ludwig_batch, .ludwig_hardcopy => if (editor.batch_output_enabled) {
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
    if (editor.ludwig_mode == .ludwig_screen) {
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
        .{ file.filename, file.l_counter, linePlural(file.l_counter) },
    ) catch return;
    emitStatusMessage(editor, message);
}

fn emitOutputCreatedMessage(editor: *const state.Editor, file: *const types.FileObject) void {
    var buffer: [4096]u8 = undefined;
    const message = std.fmt.bufPrint(
        &buffer,
        "File {s} created ({d} line{s} written).",
        .{ file.filename, file.l_counter, linePlural(file.l_counter) },
    ) catch return;
    emitStatusMessage(editor, message);
}

fn emitOutputDeletedMessage(editor: *const state.Editor, file: *const types.FileObject) void {
    const display_name = if (file.tnm.len > 0) file.tnm else file.filename;
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
        .valid = true,
        .output_flag = output_flag,
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
    const range = try line_ops.linesCreate(allocator, 1);
    if (content.len > 0) {
        try line_ops.lineChangeLength(allocator, range.first, @intCast(content.len));
        try line_ops.setLineContent(range.first, content);
    } else {
        range.first.used = 0;
    }
    try appendToFile(file, range.first, range.last);
}

fn setSnapshotFromQueue(
    allocator: std.mem.Allocator,
    file: *types.FileObject,
) !void {
    file.rewind_first_line = null;
    file.rewind_last_line = null;
    file.rewind_line_count = 0;
    if (file.first_line == null or file.last_line == null or file.line_count == 0) {
        return;
    }

    const cloned = try cloneLineRange(allocator, file.first_line.?, file.last_line.?);
    file.rewind_first_line = cloned.first;
    file.rewind_last_line = cloned.last;
    file.rewind_line_count = file.line_count;
}

fn clampTabWidth(editor: *const state.Editor) usize {
    return @intCast(@min(@as(isize, 8), @max(@as(isize, 2), editor.file_data.tab_width)));
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
    if (!status.valid or status.is_dir) {
        return null;
    }
    const data = sys_ops.readFileAlloc(allocator, owned_name, std.math.maxInt(usize)) catch return null;
    const file = try createFileObject(allocator, false);
    file.filename = owned_name;
    file.mode = status.mode;
    file.previous_file_id = @intCast(status.m_time);

    var line_buffer: std.ArrayList(u8) = .{};
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
                if (line_buffer.items.len == types.max_str_len) {
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

        if (line_buffer.items.len == types.max_str_len) {
            try appendLineBytesToFile(allocator, file, line_buffer.items);
            line_buffer.clearRetainingCapacity();
        }
        try line_buffer.append(allocator, byte);
    }

    if (line_buffer.items.len > 0 or (data.len > 0 and !isLineTerminator(data[data.len - 1]))) {
        try appendLineBytesToFile(allocator, file, line_buffer.items);
    }

    file.l_counter = 0;
    file.eof = file.line_count == 0;
    if (file.line_count > 0) {
        file.eof = false;
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
    if (status.valid and status.is_dir) {
        const related_name = options.related_name orelse return null;
        owned_name = try sys_ops.copyFilename(allocator, related_name, owned_name);
        status = sys_ops.fileStatus(owned_name);
    }
    if (status.valid) {
        if (options.create or status.is_dir or !sys_ops.fileWritable(owned_name)) {
            return null;
        }
    }

    const file = try createFileObject(allocator, true);
    file.filename = owned_name;
    file.memory = if (options.memory) |memory| memory else "";
    file.tnm = try buildTempOutputName(allocator, owned_name);
    file.entab = editor.file_data.entab;
    file.create = options.create;
    file.mode = if (status.valid) status.mode else sys_ops.fileMask();
    file.previous_file_id = if (status.valid) @intCast(status.m_time) else 0;
    file.purge = editor.file_data.purge;
    file.versions = editor.file_data.versions;
    file.eof = false;
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
    buffer: *std.ArrayList(u8),
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
    if (output_file.tnm.len == 0) {
        output_file.tnm = try buildTempOutputName(allocator, output_file.filename);
    }
    sys_ops.writeFile(output_file.tnm, data, if (output_file.mode != 0) @intCast(output_file.mode) else 0o600) catch return false;

    const backup_name = try std.fmt.allocPrint(allocator, "{s}~", .{output_file.filename});
    const versions = try sys_ops.listBackups(allocator, backup_name);
    const max_vnum: i64 = if (versions.len > 0) versions[versions.len - 1] else 0;
    if (output_file.purge) {
        if (output_file.versions <= 0) {
            try removeBackupFiles(allocator, backup_name, versions, 0, versions.len);
        } else {
            const retain: usize = @intCast(@max(output_file.versions - 1, 0));
            if (versions.len > retain) {
                try removeBackupFiles(allocator, backup_name, versions, 0, versions.len - retain);
            }
        }
    } else if (versions.len > 0 and versions.len >= @as(usize, @intCast(@max(output_file.versions, 0)))) {
        try removeBackupFiles(allocator, backup_name, versions, 0, 1);
    }

    if (output_file.versions != 0 or (!output_file.purge and max_vnum != 0)) {
        if (sys_ops.fileExists(output_file.filename)) {
            const backup_path = try std.fmt.allocPrint(allocator, "{s}{d}", .{ backup_name, max_vnum + 1 });
            sys_ops.renamePath(output_file.filename, backup_path) catch {};
        }
    }

    sys_ops.renamePath(output_file.tnm, output_file.filename) catch return false;
    if (output_file.memory.len > 0 and !sys_ops.isTempPath(output_file.filename)) {
        _ = try sys_ops.writeFilename(output_file.memory, output_file.filename);
    }
    const status = sys_ops.fileStatus(output_file.filename);
    if (status.valid) {
        output_file.mode = status.mode;
        output_file.previous_file_id = @intCast(status.m_time);
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
    var bytes: std.ArrayList(u8) = .{};
    defer bytes.deinit(allocator);

    if (first != null and last != null) {
        const tab_width = clampTabWidth(editor);
        var line = first.?;
        while (true) {
            try appendEncodedLine(allocator, &bytes, line_ops.getLineContent(line), output_file.entab, tab_width);
            if (line == last.?) {
                break;
            }
            line = line.f_link.?;
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

    if (output_file.first_line != null and output_file.last_line != null) {
        try appendRangeCloneToFile(allocator, assembled, output_file.first_line.?, output_file.last_line.?);
    }

    const visible_last = frame.last_group.?.last_line.?.b_link;
    if (visible_last != null) {
        try appendRangeCloneToFile(allocator, assembled, frame.first_group.?.first_line.?, visible_last.?);
    }

    if (input_file) |input| {
        if (input.first_line != null and input.last_line != null) {
            try appendRangeCloneToFile(allocator, assembled, input.first_line.?, input.last_line.?);
        }
    }

    assembled.eof = assembled.line_count == 0;
    return assembled;
}

fn persistDiskBackedFrameOutput(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    output_file: *types.FileObject,
    input_file: ?*types.FileObject,
) !?isize {
    if (output_file.filename.len == 0) {
        return null;
    }

    const assembled = try buildSavedFileContents(allocator, frame, output_file, input_file);
    if (!try writeLineRangeToDisk(
        editor,
        allocator,
        output_file,
        assembled.first_line,
        assembled.last_line,
    )) {
        return null;
    }

    if (input_file) |input| {
        input.rewind_first_line = assembled.first_line;
        input.rewind_last_line = assembled.last_line;
        input.rewind_line_count = assembled.line_count;
    }
    return assembled.line_count;
}

fn persistDiskBackedOutputFile(
    editor: *const state.Editor,
    allocator: std.mem.Allocator,
    output_file: *types.FileObject,
) !bool {
    if (output_file.filename.len == 0) {
        return true;
    }
    return writeLineRangeToDisk(
        editor,
        allocator,
        output_file,
        output_file.first_line,
        output_file.last_line,
    );
}

fn fileReadBuffered(file: *types.FileObject, requested_count: isize, best_try: bool) ?ReadResult {
    if (file.output_flag or requested_count < 0) {
        return null;
    }

    var count = requested_count;
    if (file.line_count < count) {
        if (!best_try) {
            return null;
        }
        count = file.line_count;
    }
    if (count == 0) {
        return .{};
    }

    const first = file.first_line orelse return null;
    const last = file.last_line orelse return null;
    if (file.line_count == count) {
        setFileQueue(file, null, null, 0);
        file.eof = true;
        file.l_counter += count;
        return .{
            .first = first,
            .last = last,
            .count = count,
        };
    }

    var split_last = first;
    var remaining: isize = count;
    while (remaining > 1) : (remaining -= 1) {
        split_last = split_last.f_link orelse return null;
    }
    const next = split_last.f_link orelse return null;
    next.b_link = null;
    split_last.f_link = null;
    file.first_line = next;
    file.line_count -= count;
    file.eof = false;
    file.l_counter += count;
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
    if (!file.output_flag) {
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
    const frame_name = if (eop_line.group != null and eop_line.group.?.frame.span != null)
        eop_line.group.?.frame.span.?.name
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
    const dot = frame.dot orelse return null;
    var first_line: ?*types.LineHdrObject = dot.line;
    var last_line: ?*types.LineHdrObject = dot.line;

    switch (rept) {
        .lead_param_none, .lead_param_plus, .lead_param_p_int => {
            if (count == 0) {
                first_line = null;
            } else if (count <= 20) {
                var line_nr: isize = 1;
                while (line_nr < count) : (line_nr += 1) {
                    last_line = last_line.?.f_link orelse return null;
                }
                if (last_line.?.f_link == null) {
                    return null;
                }
            } else {
                const line_nr = line_ops.lineToNumber(first_line.?);
                last_line = line_ops.lineFromNumber(frame, line_nr + count - 1) orelse return null;
                if (last_line.?.f_link == null) {
                    return null;
                }
            }
        },
        .lead_param_minus, .lead_param_n_int => {
            const abs_count = -count;
            last_line = dot.line.b_link orelse return null;
            if (abs_count <= 20) {
                var line_nr: isize = 1;
                while (line_nr <= abs_count) : (line_nr += 1) {
                    first_line = first_line.?.b_link orelse return null;
                }
            } else {
                var line_nr = line_ops.lineToNumber(last_line.?);
                if (abs_count > line_nr) {
                    return null;
                }
                line_nr = line_nr - abs_count + 1;
                first_line = line_ops.lineFromNumber(frame, line_nr);
            }
        },
        .lead_param_p_indef => {
            if (dot.line.f_link == null) {
                first_line = null;
            } else {
                last_line = frame.last_group.?.last_line.?.b_link;
            }
        },
        .lead_param_n_indef => {
            last_line = dot.line.b_link;
            if (last_line == null) {
                first_line = null;
            } else {
                first_line = frame.first_group.?.first_line;
            }
        },
        .lead_param_marker => {
            const mark_line = mark orelse return null;
            if (mark_line.line == first_line.?) {
                first_line = null;
            } else if (mark_line.line.f_link == first_line.?) {
                first_line = mark_line.line;
                last_line = mark_line.line;
            } else if (mark_line.line.b_link == first_line.?) {
                last_line = first_line.?;
            } else {
                const mark_line_nr = line_ops.lineToNumber(mark_line.line);
                const line_nr = line_ops.lineToNumber(dot.line);
                if (mark_line_nr < line_nr) {
                    first_line = mark_line.line;
                    last_line = last_line.?.b_link;
                } else {
                    last_line = mark_line.line.b_link;
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
    if (editor.fgi_file <= 0 or editor.fgi_file > types.max_files) {
        return false;
    }
    const input_file = editor.files[@intCast(editor.fgi_file)] orelse return false;
    const lines_to_read = if (rept == .lead_param_p_indef) types.max_int else count;
    const read_result = fileReadBuffered(input_file, lines_to_read, rept == .lead_param_p_indef) orelse return false;
    if (read_result.first) |first| {
        const last = read_result.last.?;
        try line_ops.linesInject(allocator, first, last, frame.dot.?.line);
        try mark_ops.markCreate(allocator, first, 1, &frame.marks[types.mark_equals]);
        frame.text_modified = true;
        const after = last.f_link.?;
        try mark_ops.markCreate(allocator, after, 1, &frame.marks[types.mark_modified]);
        try mark_ops.markCreate(allocator, after, 1, &frame.dot);
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
    if (editor.fgo_file <= 0 or editor.fgo_file > types.max_files) {
        return false;
    }
    const output_file = editor.files[@intCast(editor.fgo_file)] orelse return false;
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
    const page_out = computeLineRange(frame, .lead_param_n_indef, 0, null) orelse return false;
    if (page_out.first) |first| {
        const last = page_out.last.?;
        if (frame.output_file != 0) {
            const output_file = editor.files[@intCast(frame.output_file)] orelse return false;
            if (!try fileWriteBuffered(allocator, first, last, output_file)) {
                editor.exit_abort = true;
                return false;
            }
        }
        const after = last.f_link orelse return false;
        try mark_ops.marksSqueeze(allocator, first, 1, after, 1);
        line_ops.linesExtract(first, last);
    }

    if (frame.input_file == 0) {
        frame.dirty_line = 1;
        return true;
    }
    const input_file = editor.files[@intCast(frame.input_file)] orelse return false;
    while (frame.space_left * 10 > frame.space_limit and !editor.tt_control_c) {
        const read_result = fileReadBuffered(input_file, 50, true) orelse return false;
        frame.input_count += read_result.count;
        if (read_result.first == null) {
            break;
        }
        try line_ops.linesInject(allocator, read_result.first.?, read_result.last.?, frame.last_group.?.last_line.?);
        if (frame.dot.?.line.f_link == null) {
            try mark_ops.markCreate(allocator, read_result.first.?, frame.dot.?.col, &frame.dot);
        }
    }

    try fileFixEOP(allocator, input_file.eof, frame.last_group.?.last_line.?);
    frame.dirty_line = 1;
    return true;
}

fn refreshFrameSpanMarks(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !void {
    if (frame.span) |span| {
        try mark_ops.markCreate(allocator, frame.first_group.?.first_line.?, 1, &span.mark_one);
        try mark_ops.markCreate(allocator, frame.last_group.?.last_line.?, 1, &span.mark_two);
    }
}

fn clearFrameText(
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !void {
    const sentinel = frame.last_group.?.last_line.?;
    const last_content = sentinel.b_link;
    if (last_content == null) {
        try mark_ops.markCreate(allocator, sentinel, 1, &frame.dot);
        try refreshFrameSpanMarks(allocator, frame);
        return;
    }

    const first_content = frame.first_group.?.first_line.?;
    try mark_ops.marksSqueeze(allocator, first_content, 1, sentinel, 1);
    first_content.b_link = null;
    last_content.?.f_link = null;
    sentinel.b_link = null;
    sentinel.offset_num = 0;

    const empty_group = sentinel.group.?;
    frame.first_group = empty_group;
    frame.last_group = empty_group;
    empty_group.b_link = null;
    empty_group.f_link = null;
    empty_group.first_line = sentinel;
    empty_group.last_line = sentinel;
    empty_group.first_line_num = 1;
    empty_group.num_lines = 0;

    try line_ops.lineChangeLength(allocator, sentinel, 0);
    try mark_ops.markCreate(allocator, sentinel, 1, &frame.dot);
    try refreshFrameSpanMarks(allocator, frame);
}

fn findBufferedInputByFilename(
    editor: *state.Editor,
    file_name: []const u8,
) ?*types.FileObject {
    var slot: usize = 1;
    while (slot <= types.max_files) : (slot += 1) {
        const file = editor.files[slot] orelse continue;
        if (!file.output_flag and std.mem.eql(u8, file.filename, file_name)) {
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

    const source_first = if (source.rewind_first_line != null) source.rewind_first_line else source.first_line;
    const source_last = if (source.rewind_last_line != null) source.rewind_last_line else source.last_line;
    if (source_first != null and source_last != null) {
        const cloned = try cloneLineRange(allocator, source_first.?, source_last.?);
        try line_ops.linesInject(allocator, cloned.first, cloned.last, frame.last_group.?.last_line.?);
        if (frame.dot.?.line.f_link == null) {
            try mark_ops.markCreate(allocator, cloned.first, frame.dot.?.col, &frame.dot);
        }
    }

    try refreshFrameSpanMarks(allocator, frame);
    return true;
}

fn getFreeSlot(editor: *const state.Editor, reserved_slot: isize) ?isize {
    var slot: isize = 1;
    while (slot <= types.max_files) : (slot += 1) {
        if (slot == reserved_slot) {
            continue;
        }
        if (editor.files[@intCast(slot)] == null) {
            return slot;
        }
    }
    return null;
}

fn getFileSlot(editor: *state.Editor, slot: isize) ?*types.FileObject {
    if (slot <= 0 or slot > types.max_files) {
        return null;
    }
    return editor.files[@intCast(slot)];
}

fn requireFileSlot(editor: *state.Editor, slot: isize, output_flag: bool) ?*types.FileObject {
    const file = getFileSlot(editor, slot) orelse return null;
    if (file.output_flag != output_flag) {
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
        .cmd_file_input => blk: {
            if (frame.input_file != 0) {
                break :blk false;
            }
            const slot = getFreeSlot(editor, 0) orelse break :blk false;
            const input_file = (try makeDiskInputFile(editor, allocator, file_name)) orelse break :blk false;
            editor.files[@intCast(slot)] = input_file;
            editor.files_frames[@intCast(slot)] = frame;
            frame.input_file = slot;
            break :blk try pageFileWithLoadingMessage(editor, allocator, frame);
        },
        .cmd_file_global_input => blk: {
            if (editor.fgi_file != 0) {
                break :blk false;
            }
            const slot = getFreeSlot(editor, 0) orelse break :blk false;
            const input_file = (try makeDiskInputFile(editor, allocator, file_name)) orelse break :blk false;
            editor.files[@intCast(slot)] = input_file;
            editor.fgi_file = slot;
            break :blk true;
        },
        .cmd_file_output => blk: {
            if (frame.output_file != 0) {
                break :blk false;
            }
            const slot = getFreeSlot(editor, 0) orelse break :blk false;
            const related_name = if (frame.input_file != 0)
                (requireFileSlot(editor, frame.input_file, false) orelse break :blk false).filename
            else
                null;
            const output_file = (try makeDiskOutputFile(editor, allocator, file_name, .{ .related_name = related_name })) orelse break :blk false;
            editor.files[@intCast(slot)] = output_file;
            editor.files_frames[@intCast(slot)] = frame;
            frame.output_file = slot;
            break :blk true;
        },
        .cmd_file_global_output => blk: {
            if (editor.fgo_file != 0) {
                break :blk false;
            }
            const slot = getFreeSlot(editor, 0) orelse break :blk false;
            const output_file = (try makeDiskOutputFile(editor, allocator, file_name, .{})) orelse break :blk false;
            editor.files[@intCast(slot)] = output_file;
            editor.fgo_file = slot;
            break :blk true;
        },
        .cmd_file_edit => blk: {
            if (frame.input_file != 0 or frame.output_file != 0) {
                break :blk false;
            }
            const input_slot = getFreeSlot(editor, 0) orelse break :blk false;
            const output_slot = getFreeSlot(editor, input_slot) orelse break :blk false;
            const input_file = (try makeDiskInputFile(editor, allocator, file_name)) orelse break :blk false;
            const output_file = (try makeDiskOutputFile(editor, allocator, file_name, .{ .related_name = input_file.filename })) orelse break :blk false;
            editor.files[@intCast(input_slot)] = input_file;
            editor.files_frames[@intCast(input_slot)] = frame;
            frame.input_file = input_slot;
            editor.files[@intCast(output_slot)] = output_file;
            editor.files_frames[@intCast(output_slot)] = frame;
            frame.output_file = output_slot;
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
    const input_file = requireFileSlot(editor, frame.input_file, false) orelse return false;
    if (!try loadFileQueueFromSnapshot(allocator, input_file)) {
        return false;
    }
    if (frame.dot.?.line.f_link == null) {
        try clearFrameText(allocator, frame);
    }
    return filePage(editor, allocator, frame);
}

pub fn fileGlobalRewindCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
) !bool {
    const input_file = requireFileSlot(editor, editor.fgi_file, false) orelse return false;
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
    if (input_file.first_line == null or input_file.last_line == null) {
        return;
    }
    const cloned = try cloneLineRange(allocator, input_file.first_line.?, input_file.last_line.?);
    try appendToFile(output_file, cloned.first, cloned.last);
}

fn detachFileSlot(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    slot: isize,
) !bool {
    _ = getFileSlot(editor, slot) orelse return false;
    const slot_index: usize = @intCast(slot);

    if (editor.files_frames[slot_index]) |frame| {
        if (slot == frame.output_file) {
            frame.output_file = 0;
        } else {
            frame.input_file = 0;
            try fileFixEOP(allocator, true, frame.last_group.?.last_line.?);
            frame.dirty_line = 1;
        }
        editor.files_frames[slot_index] = null;
    } else if (slot == editor.fgi_file) {
        editor.fgi_file = 0;
    } else if (slot == editor.fgo_file) {
        editor.fgo_file = 0;
    }

    editor.files[slot_index] = null;
    return true;
}

pub fn fileSaveCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !bool {
    const output_file = requireFileSlot(editor, frame.output_file, true) orelse return false;
    if (!frame.text_modified) {
        return true;
    }

    if (output_file.filename.len > 0) {
        const input_file = if (frame.input_file != 0)
            requireFileSlot(editor, frame.input_file, false) orelse return false
        else
            null;
        const lines_read_before_save = frame.input_count;
        const total_saved = (try persistDiskBackedFrameOutput(editor, allocator, frame, output_file, input_file)) orelse return false;
        frame.input_count = total_saved;
        output_file.l_counter = total_saved;
        if (input_file) |input| {
            input.l_counter = lines_read_before_save + input.line_count;
        }
    } else {
        const last = frame.last_group.?.last_line.?.b_link;
        if (last != null) {
            const first = frame.first_group.?.first_line.?;
            if (!try fileWriteBuffered(allocator, first, last.?, output_file)) {
                return false;
            }
        }

        if (frame.input_file != 0) {
            const input_file = requireFileSlot(editor, frame.input_file, false) orelse return false;
            const lines_read_before_save = frame.input_count;
            try copyUnreadInputToOutput(allocator, input_file, output_file);
            frame.input_count = output_file.l_counter;
            input_file.l_counter = lines_read_before_save + input_file.line_count;
        } else {
            frame.input_count = output_file.l_counter;
        }
    }

    frame.text_modified = false;
    mark_ops.markDestroy(allocator, &frame.marks[types.mark_modified]);
    return true;
}

pub fn fileKillCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !bool {
    const output_file = requireFileSlot(editor, frame.output_file, true) orelse {
        emitNoFileOpenMessage(editor);
        return false;
    };
    if (output_file.tnm.len > 0) {
        sys_ops.deleteFile(output_file.tnm) catch {};
    }
    if (!try detachFileSlot(editor, allocator, frame.output_file)) {
        return false;
    }
    emitOutputDeletedMessage(editor, output_file);
    return true;
}

pub fn fileGlobalKillCommand(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
) !bool {
    const output_file = requireFileSlot(editor, editor.fgo_file, true) orelse {
        emitNoFileOpenMessage(editor);
        return false;
    };
    if (output_file.tnm.len > 0) {
        sys_ops.deleteFile(output_file.tnm) catch {};
    }
    if (!try detachFileSlot(editor, allocator, editor.fgo_file)) {
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
        .cmd_file_input => blk: {
            _ = requireFileSlot(editor, frame.input_file, false) orelse break :blk false;
            break :blk try detachFileSlot(editor, allocator, frame.input_file);
        },
        .cmd_file_output => blk: {
            const output_file = requireFileSlot(editor, frame.output_file, true) orelse break :blk false;
            const had_modifications = frame.text_modified;
            if (had_modifications and !try fileSaveCommand(editor, allocator, frame)) {
                break :blk false;
            }
            if (!had_modifications and !try persistDiskBackedOutputFile(editor, allocator, output_file)) {
                break :blk false;
            }
            break :blk try detachFileSlot(editor, allocator, frame.output_file);
        },
        .cmd_file_edit => blk: {
            _ = requireFileSlot(editor, frame.input_file, false) orelse break :blk false;
            _ = requireFileSlot(editor, frame.output_file, true) orelse break :blk false;
            if (frame.text_modified and !try fileSaveCommand(editor, allocator, frame)) {
                break :blk false;
            }
            if (!try detachFileSlot(editor, allocator, frame.output_file)) {
                break :blk false;
            }
            break :blk try detachFileSlot(editor, allocator, frame.input_file);
        },
        .cmd_file_global_input => blk: {
            _ = requireFileSlot(editor, editor.fgi_file, false) orelse break :blk false;
            break :blk try detachFileSlot(editor, allocator, editor.fgi_file);
        },
        .cmd_file_global_output => blk: {
            const output_file = requireFileSlot(editor, editor.fgo_file, true) orelse break :blk false;
            if (!try persistDiskBackedOutputFile(editor, allocator, output_file)) {
                break :blk false;
            }
            break :blk try detachFileSlot(editor, allocator, editor.fgo_file);
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
    const output_slot = if (frame.output_file != 0 and getFileSlot(editor, frame.output_file) != null)
        frame.output_file
    else
        0;
    const input_slot = if (frame.input_file != 0 and getFileSlot(editor, frame.input_file) != null)
        frame.input_file
    else
        0;

    if (output_slot != 0) {
        if (output_slot != slot) {
            return true;
        }
        const output_file = requireFileSlot(editor, output_slot, true) orelse return false;
        const had_modifications = frame.text_modified;

        if (had_modifications and !try fileSaveCommand(editor, allocator, frame)) {
            return false;
        }

        if (input_slot != 0) {
            const input_file = requireFileSlot(editor, input_slot, false) orelse return false;
            if (editor.ludwig_mode == .ludwig_batch and editor.batch_output_enabled) {
                emitInputClosedMessage(editor, input_file);
            }
            if (!try detachFileSlot(editor, allocator, input_slot)) {
                return false;
            }
        }

        if (had_modifications and output_file.filename.len > 0 and editor.ludwig_mode == .ludwig_batch and editor.batch_output_enabled) {
            emitOutputCreatedMessage(editor, output_file);
        }
        return detachFileSlot(editor, allocator, output_slot);
    }

    if (input_slot != 0 and input_slot == slot) {
        const input_file = requireFileSlot(editor, input_slot, false) orelse return false;
        if (editor.ludwig_mode == .ludwig_batch and editor.batch_output_enabled) {
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
    const input_file = requireFileSlot(editor, editor.fgi_file, false) orelse return false;
    if (editor.ludwig_mode == .ludwig_batch and editor.batch_output_enabled) {
        emitInputClosedMessage(editor, input_file);
    }
    return detachFileSlot(editor, allocator, editor.fgi_file);
}

fn closeGlobalOutputForQuit(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
) !bool {
    const output_file = requireFileSlot(editor, editor.fgo_file, true) orelse return false;
    if (!try persistDiskBackedOutputFile(editor, allocator, output_file)) {
        return false;
    }
    if (output_file.filename.len > 0 and editor.ludwig_mode == .ludwig_batch and editor.batch_output_enabled) {
        emitOutputCreatedMessage(editor, output_file);
    }
    return detachFileSlot(editor, allocator, editor.fgo_file);
}

fn closeUnattachedSlotForQuit(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    slot: isize,
) !bool {
    const file = getFileSlot(editor, slot) orelse return false;
    if (file.output_flag) {
        if (!try persistDiskBackedOutputFile(editor, allocator, file)) {
            return false;
        }
        if (file.filename.len > 0 and editor.ludwig_mode == .ludwig_batch and editor.batch_output_enabled) {
            emitOutputCreatedMessage(editor, file);
        }
    } else if (editor.ludwig_mode == .ludwig_batch and editor.batch_output_enabled) {
        emitInputClosedMessage(editor, file);
    }
    return detachFileSlot(editor, allocator, slot);
}

pub fn quitCloseFiles(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
) !bool {
    var slot: isize = 1;
    while (slot <= types.max_files) : (slot += 1) {
        const slot_index: usize = @intCast(slot);
        if (editor.files[slot_index] == null) {
            continue;
        }

        if (editor.files_frames[slot_index]) |frame| {
            if (!try closeFrameFilesForQuit(editor, allocator, frame, slot)) {
                return false;
            }
            continue;
        }

        if (slot == editor.fgi_file) {
            if (!try closeGlobalInputForQuit(editor, allocator)) {
                return false;
            }
            continue;
        }

        if (slot == editor.fgo_file) {
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
        .valid = true,
        .output_flag = output_flag,
    };
    if (try buildLineRangeFromContents(allocator, contents)) |range| {
        setFileQueue(file, range.first, range.last, @intCast(contents.len));
    }
    if (try buildLineRangeFromContents(allocator, contents)) |range| {
        file.rewind_first_line = range.first;
        file.rewind_last_line = range.last;
        file.rewind_line_count = @intCast(contents.len);
    }
    file.eof = contents.len == 0;
    return file;
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

test "file table writes current file usage into report frame" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const root = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const work = (try @import("frame.zig").frameEdit(&editor, allocator, root.frame, "WORK")).?;
    const oops = (try @import("frame.zig").frameEdit(&editor, allocator, work, "OOPS")).?;

    const input = try allocator.create(types.FileObject);
    input.* = .{
        .filename = "input.txt",
        .eof = true,
    };
    editor.files[1] = input;
    editor.files_frames[1] = work;
    work.input_file = 1;
    work.text_modified = true;

    const output = try allocator.create(types.FileObject);
    output.* = .{
        .filename = "output.txt",
        .output_flag = true,
    };
    editor.files[2] = output;
    editor.files_frames[2] = work;
    work.output_file = 2;

    const global_input = try allocator.create(types.FileObject);
    global_input.* = .{
        .filename = "global.in",
    };
    editor.files[3] = global_input;
    editor.fgi_file = 3;

    const global_output = try allocator.create(types.FileObject);
    global_output.* = .{
        .filename = "global.out",
        .output_flag = true,
    };
    editor.files[4] = global_output;
    editor.fgo_file = 4;

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
    const oops = (try @import("frame.zig").frameEdit(&editor, allocator, root.frame, "OOPS")).?;

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
    editor.files[1] = input;
    editor.files_frames[1] = fixture.frame;
    fixture.frame.input_file = 1;

    const output = try makeBufferedFile(allocator, &[_][]const u8{
        "paged",
    }, true);
    editor.files[2] = output;
    editor.files_frames[2] = fixture.frame;
    fixture.frame.output_file = 2;
    fixture.frame.text_modified = true;
    try mark_ops.markCreate(allocator, fixture.content_lines[1], fixture.content_lines[1].used + 1, &fixture.frame.marks[types.mark_modified]);

    try std.testing.expect(try fileSaveCommand(&editor, allocator, fixture.frame));
    try std.testing.expect(!fixture.frame.text_modified);
    try std.testing.expect(fixture.frame.marks[types.mark_modified] == null);
    try std.testing.expectEqual(@as(isize, 5), output.line_count);
    try std.testing.expectEqualStrings("paged", line_ops.getLineContent(output.first_line));
    try std.testing.expectEqualStrings("visible1", line_ops.getLineContent(output.first_line.?.f_link));
    try std.testing.expectEqualStrings("visible2", line_ops.getLineContent(output.first_line.?.f_link.?.f_link));
    try std.testing.expectEqualStrings("tail1", line_ops.getLineContent(output.first_line.?.f_link.?.f_link.?.f_link));
    try std.testing.expectEqualStrings("tail2", line_ops.getLineContent(output.last_line));
}

test "file kill detaches current output file" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const output = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    editor.files[1] = output;
    editor.files_frames[1] = fixture.frame;
    fixture.frame.output_file = 1;

    try std.testing.expect(try fileKillCommand(&editor, allocator, fixture.frame));
    try std.testing.expectEqual(@as(isize, 0), fixture.frame.output_file);
    try std.testing.expect(editor.files[1] == null);
    try std.testing.expect(editor.files_frames[1] == null);
}

test "file kill queues interactive deleted status message" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.ludwig_mode = .ludwig_screen;

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    const output = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    output.filename = "output.txt";
    output.tnm = "output.txt-lw";
    editor.files[1] = output;
    editor.files_frames[1] = fixture.frame;
    fixture.frame.output_file = 1;

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
    editor.ludwig_mode = .ludwig_screen;

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
    editor.files[1] = input;
    editor.files_frames[1] = fixture.frame;
    fixture.frame.input_file = 1;

    try std.testing.expect(try fileCloseCommand(&editor, allocator, fixture.frame, .cmd_file_input));
    try std.testing.expectEqual(@as(isize, 0), fixture.frame.input_file);
    try std.testing.expect(editor.files[1] == null);
    try std.testing.expectEqualStrings("<End of File>", line_ops.getDisplayLineContent(fixture.frame.last_group.?.last_line.?));
}

test "file close detaches global output file" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const output = try makeBufferedFile(allocator, &[_][]const u8{}, true);
    editor.files[1] = output;
    editor.fgo_file = 1;

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"root"});
    try std.testing.expect(try fileCloseCommand(&editor, allocator, fixture.frame, .cmd_file_global_output));
    try std.testing.expectEqual(@as(isize, 0), editor.fgo_file);
    try std.testing.expect(editor.files[1] == null);
}

test "file save rotates disk backups and updates memory file" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    editor.file_data.versions = 2;

    const file_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/save.txt", .{tmp_dir.sub_path});
    const backup1_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/save.txt~1", .{tmp_dir.sub_path});
    const backup2_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/save.txt~2", .{tmp_dir.sub_path});
    const memory_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/memory.txt", .{tmp_dir.sub_path});
    const expanded_memory = (try sys_ops.expandFilename(allocator, memory_path)) orelse return error.TestUnexpectedResult;

    try tmp_dir.dir.writeFile(.{ .sub_path = "save.txt", .data = "old\n" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "save.txt~1", .data = "older\n" });

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"new"});
    const output = (try openDiskOutputFile(&editor, allocator, file_path, .{ .memory = expanded_memory })) orelse return error.TestUnexpectedResult;
    editor.files[1] = output;
    editor.files_frames[1] = fixture.frame;
    fixture.frame.output_file = 1;
    fixture.frame.text_modified = true;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], fixture.content_lines[0].used + 1, &fixture.frame.marks[types.mark_modified]);

    try std.testing.expect(try fileSaveCommand(&editor, allocator, fixture.frame));

    const saved = try std.fs.cwd().readFileAlloc(allocator, file_path, std.math.maxInt(usize));
    try std.testing.expectEqualStrings("new\n", saved);
    const old_backup = try std.fs.cwd().readFileAlloc(allocator, backup1_path, std.math.maxInt(usize));
    try std.testing.expectEqualStrings("older\n", old_backup);
    const new_backup = try std.fs.cwd().readFileAlloc(allocator, backup2_path, std.math.maxInt(usize));
    try std.testing.expectEqualStrings("old\n", new_backup);
    const remembered = try std.fs.cwd().readFileAlloc(allocator, memory_path, std.math.maxInt(usize));
    const expected_memory = try std.fmt.allocPrint(allocator, "{s}\n", .{output.filename});
    try std.testing.expectEqualStrings(expected_memory, remembered);
}
