const std = @import("std");

pub const FileStatus = struct {
    valid: bool = false,
    mode: u16 = 0o600,
    m_time: i128 = -1,
    is_dir: bool = false,
};

pub fn getEnv(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    return std.process.getEnvVarOwned(allocator, name) catch null;
}

fn currentHomeDir(allocator: std.mem.Allocator) ?[]const u8 {
    return getEnv(allocator, "HOME");
}

fn expandTilde(allocator: std.mem.Allocator, filename: []const u8) !?[]const u8 {
    if (filename.len == 0 or filename[0] != '~') {
        const dup: []const u8 = try allocator.dupe(u8, filename);
        return dup;
    }

    const remainder = filename[1..];
    const slash_index = std.mem.indexOfScalar(u8, remainder, std.fs.path.sep) orelse remainder.len;
    const user = remainder[0..slash_index];
    const rest = if (slash_index < remainder.len) remainder[slash_index + 1 ..] else "";

    const home = if (user.len == 0) blk: {
        break :blk currentHomeDir(allocator) orelse return null;
    } else blk: {
        const current_user = getEnv(allocator, "USER") orelse return null;
        if (!std.mem.eql(u8, current_user, user)) {
            return null;
        }
        break :blk currentHomeDir(allocator) orelse return null;
    };

    if (rest.len == 0) {
        const dup: []const u8 = try allocator.dupe(u8, home);
        return dup;
    }
    const joined: []const u8 = try std.fs.path.join(allocator, &.{ home, rest });
    return joined;
}

pub fn expandFilename(allocator: std.mem.Allocator, filename: []const u8) !?[]const u8 {
    const expanded = (try expandTilde(allocator, filename)) orelse return null;
    if (expanded.len == 0) {
        return expanded;
    }
    if (std.fs.path.isAbsolute(expanded)) {
        return expanded;
    }

    const cwd = try std.process.getCwdAlloc(allocator);
    const resolved: []const u8 = try std.fs.path.resolve(allocator, &.{ cwd, expanded });
    return resolved;
}

pub fn copyFilename(allocator: std.mem.Allocator, src_path: []const u8, dst_path: []const u8) ![]const u8 {
    return std.fs.path.join(allocator, &.{ dst_path, std.fs.path.basename(src_path) });
}

fn openReadOnly(path: []const u8) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.openFileAbsolute(path, .{});
    }
    return std.fs.cwd().openFile(path, .{});
}

fn createTruncated(path: []const u8, mode: u16) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.createFileAbsolute(path, .{
            .truncate = true,
            .read = true,
            .mode = mode,
        });
    }
    return std.fs.cwd().createFile(path, .{
        .truncate = true,
        .read = true,
        .mode = mode,
    });
}

fn openWriteOnly(path: []const u8) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.openFileAbsolute(path, .{ .mode = .write_only });
    }
    return std.fs.cwd().openFile(path, .{ .mode = .write_only });
}

fn openDirIter(path: []const u8) !std.fs.Dir {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.openDirAbsolute(path, .{ .iterate = true });
    }
    return std.fs.cwd().openDir(path, .{ .iterate = true });
}

pub fn readFileAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
    max_bytes: usize,
) ![]u8 {
    var file = try openReadOnly(path);
    defer file.close();

    var buf: [4096]u8 = undefined;
    var reader = file.reader(&buf);
    return reader.interface.allocRemaining(allocator, .limited(max_bytes)) catch |err| switch (err) {
        error.StreamTooLong => error.FileTooBig,
        else => |e| e,
    };
}

pub fn writeFile(path: []const u8, data: []const u8, mode: u16) !void {
    var file = try createTruncated(path, mode);
    defer file.close();

    var buf: [4096]u8 = undefined;
    var file_writer = file.writer(&buf);
    defer file_writer.interface.flush() catch {};
    try file_writer.interface.writeAll(data);
}

pub fn renamePath(old_path: []const u8, new_path: []const u8) !void {
    if (std.fs.path.isAbsolute(old_path) and std.fs.path.isAbsolute(new_path)) {
        return std.fs.renameAbsolute(old_path, new_path);
    }
    return std.fs.cwd().rename(old_path, new_path);
}

pub fn deleteFile(path: []const u8) !void {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.deleteFileAbsolute(path);
    }
    return std.fs.cwd().deleteFile(path);
}

pub fn fileStatus(path: []const u8) FileStatus {
    const stat = std.fs.cwd().statFile(path) catch return .{};
    return .{
        .valid = true,
        .mode = @intCast(stat.mode & 0o777),
        .m_time = stat.mtime,
        .is_dir = stat.kind == .directory,
    };
}

pub fn fileExists(path: []const u8) bool {
    return fileStatus(path).valid;
}

pub fn fileWritable(path: []const u8) bool {
    var file = openWriteOnly(path) catch return false;
    file.close();
    return true;
}

pub fn fileMask() u16 {
    return 0o666;
}

pub fn writeFilename(path: []const u8, filename: []const u8) !bool {
    if (path.len == 0) {
        return false;
    }
    const contents = try std.fmt.allocPrint(std.heap.page_allocator, "{s}\n", .{filename});
    defer std.heap.page_allocator.free(contents);
    writeFile(path, contents, 0o600) catch return false;
    return true;
}

pub fn readFilename(allocator: std.mem.Allocator, path: []const u8) !?[]const u8 {
    const data = readFileAlloc(allocator, path, 4096) catch return null;
    const line_end = std.mem.indexOfAny(u8, data, "\r\n") orelse data.len;
    const line = data[0..line_end];
    if (line.len == 0) {
        return null;
    }
    const dup: []const u8 = try allocator.dupe(u8, line);
    return dup;
}

fn sortVersions(values: []i64) void {
    var index: usize = 1;
    while (index < values.len) : (index += 1) {
        const key = values[index];
        var pos = index;
        while (pos > 0 and values[pos - 1] > key) : (pos -= 1) {
            values[pos] = values[pos - 1];
        }
        values[pos] = key;
    }
}

pub fn listBackups(allocator: std.mem.Allocator, backup_name: []const u8) ![]i64 {
    const dir_name = std.fs.path.dirname(backup_name) orelse ".";
    const base_name = std.fs.path.basename(backup_name);

    var dir = openDirIter(dir_name) catch return allocator.alloc(i64, 0);
    defer dir.close();

    var versions: std.ArrayList(i64) = .{};
    errdefer versions.deinit(allocator);
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (!std.mem.startsWith(u8, entry.name, base_name)) {
            continue;
        }
        const suffix = entry.name[base_name.len..];
        if (suffix.len == 0) {
            continue;
        }
        const version = std.fmt.parseInt(i64, suffix, 10) catch continue;
        try versions.append(allocator, version);
    }

    sortVersions(versions.items);
    return versions.toOwnedSlice(allocator);
}

pub fn isTempPath(path: []const u8) bool {
    return std.mem.eql(u8, path, "/tmp") or
        std.mem.eql(u8, path, "/usr/tmp") or
        std.mem.eql(u8, path, "/var/tmp") or
        std.mem.startsWith(u8, path, "/tmp/") or
        std.mem.startsWith(u8, path, "/usr/tmp/") or
        std.mem.startsWith(u8, path, "/var/tmp/");
}

fn tmpPath(allocator: std.mem.Allocator, tmp_dir: *std.testing.TmpDir, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/{s}", .{ tmp_dir.sub_path, name });
}

test "sys expands relative and home-prefixed filenames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const rel = (try expandFilename(allocator, "docs")) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.fs.path.isAbsolute(rel));

    const home = currentHomeDir(allocator) orelse return error.SkipZigTest;
    const home_expanded = (try expandFilename(allocator, "~/tmp")) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.startsWith(u8, home_expanded, home));
}

test "sys writes and reads memory filenames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const memory_path = try tmpPath(allocator, &tmp_dir, "memory.txt");
    try std.testing.expect(try writeFilename(memory_path, "/tmp/example.txt"));
    const remembered = (try readFilename(allocator, memory_path)) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("/tmp/example.txt", remembered);
}

test "sys lists numeric backup suffixes in order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "sample~10", .data = "" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "sample~2", .data = "" });
    try tmp_dir.dir.writeFile(.{ .sub_path = "sample~x", .data = "" });

    const backup_base = try tmpPath(allocator, &tmp_dir, "sample~");
    const versions = try listBackups(allocator, backup_base);
    try std.testing.expectEqual(@as(usize, 2), versions.len);
    try std.testing.expectEqual(@as(i64, 2), versions[0]);
    try std.testing.expectEqual(@as(i64, 10), versions[1]);
}
