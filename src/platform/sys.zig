const std = @import("std");

pub const FileStatus = struct {
    valid: bool = false,
    mode: u16 = 0o600,
    m_time: i128 = -1,
    is_dir: bool = false,
};

pub fn getEnv(allocator: std.mem.Allocator, env: std.process.Environ.Map, name: []const u8) ?[]const u8 {
    const value = env.get(name) orelse return null;
    return allocator.dupe(u8, value) catch null;
}

fn currentHomeDir(
    allocator: std.mem.Allocator,
    env: std.process.Environ.Map,
) ?[]const u8 {
    return getEnv(allocator, env, "HOME");
}

fn expandTilde(allocator: std.mem.Allocator, env: std.process.Environ.Map, filename: []const u8) !?[]const u8 {
    if (filename.len == 0 or filename[0] != '~') {
        const dup: []const u8 = try allocator.dupe(u8, filename);
        return dup;
    }

    const remainder = filename[1..];
    const slash_index = std.mem.indexOfScalar(u8, remainder, std.fs.path.sep) orelse remainder.len;
    const user = remainder[0..slash_index];
    const rest = if (slash_index < remainder.len) remainder[slash_index + 1 ..] else "";

    const home = if (user.len == 0) blk: {
        break :blk currentHomeDir(allocator, env) orelse return null;
    } else blk: {
        const current_user = getEnv(allocator, env, "USER") orelse return null;
        defer allocator.free(current_user);
        if (!std.mem.eql(u8, current_user, user)) {
            return null;
        }
        break :blk currentHomeDir(allocator, env) orelse return null;
    };

    if (rest.len == 0) {
        const dup: []const u8 = try allocator.dupe(u8, home);
        return dup;
    }
    const joined: []const u8 = try std.fs.path.join(allocator, &.{ home, rest });
    return joined;
}

pub fn expandFilename(io: std.Io, allocator: std.mem.Allocator, env: std.process.Environ.Map, filename: []const u8) !?[]const u8 {
    const expanded = (try expandTilde(allocator, env, filename)) orelse return null;
    if (expanded.len == 0) {
        return expanded;
    }
    if (std.fs.path.isAbsolute(expanded)) {
        return expanded;
    }

    const cwd = try std.process.currentPathAlloc(io, allocator);
    const resolved: []const u8 = try std.fs.path.resolve(allocator, &.{ cwd, expanded });
    return resolved;
}

pub fn copyFilename(allocator: std.mem.Allocator, src_path: []const u8, dst_path: []const u8) ![]const u8 {
    return std.fs.path.join(allocator, &.{ dst_path, std.fs.path.basename(src_path) });
}

fn openReadOnly(io: std.Io, path: []const u8) !std.Io.File {
    return std.Io.Dir.cwd().openFile(io, path, .{});
}

fn createTruncated(io: std.Io, path: []const u8, mode: u16) !std.Io.File {
    if (std.fs.path.isAbsolute(path)) {
        return std.Io.Dir.createFileAbsolute(io, path, .{
            .truncate = true,
            .read = true,
            .permissions = std.Io.File.Permissions.fromMode(mode),
        });
    }
    return std.Io.Dir.cwd().createFile(io, path, .{
        .truncate = true,
        .read = true,
        .permissions = std.Io.File.Permissions.fromMode(mode),
    });
}

fn openWriteOnly(io: std.Io, path: []const u8) !std.Io.File {
    return std.Io.Dir.cwd().openFile(io, path, .{ .mode = .write_only });
}

fn openDirIter(io: std.Io, path: []const u8) !std.Io.Dir {
    if (std.fs.path.isAbsolute(path)) {
        return std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
    }
    return std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
}

pub fn readFileAlloc(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    max_bytes: usize,
) ![]u8 {
    var file = try openReadOnly(io, path);
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);
    return reader.interface.allocRemaining(allocator, .limited(max_bytes)) catch |err| switch (err) {
        error.StreamTooLong => error.FileTooBig,
        else => |e| e,
    };
}

pub fn writeFile(io: std.Io, path: []const u8, data: []const u8, mode: u16) !void {
    var file = try createTruncated(io, path, mode);
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &buf);
    defer file_writer.interface.flush() catch {};
    try file_writer.interface.writeAll(data);
}

pub fn renamePath(io: std.Io, old_path: []const u8, new_path: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    return std.Io.Dir.rename(cwd, old_path, cwd, new_path, io);
}

pub fn deleteFile(io: std.Io, path: []const u8) !void {
    if (std.fs.path.isAbsolute(path)) {
        return std.Io.Dir.deleteFileAbsolute(io, path);
    }
    return std.Io.Dir.cwd().deleteFile(io, path);
}

pub fn fileStatus(io: std.Io, path: []const u8) FileStatus {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return .{};
    return .{
        .valid = true,
        .mode = @intCast(stat.permissions.toMode() & 0o777),
        .m_time = stat.mtime.toSeconds(),
        .is_dir = stat.kind == .directory,
    };
}

pub fn fileExists(io: std.Io, path: []const u8) bool {
    return fileStatus(io, path).valid;
}

pub fn fileWritable(io: std.Io, path: []const u8) bool {
    var file = openWriteOnly(io, path) catch return false;
    file.close(io);
    return true;
}

pub fn fileMask() u16 {
    return 0o666;
}

pub fn writeFilename(io: std.Io, path: []const u8, filename: []const u8) !bool {
    if (path.len == 0) {
        return false;
    }
    const contents = try std.fmt.allocPrint(std.heap.page_allocator, "{s}\n", .{filename});
    defer std.heap.page_allocator.free(contents);
    writeFile(io, path, contents, 0o600) catch return false;
    return true;
}

pub fn readFilename(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !?[]const u8 {
    const data = readFileAlloc(io, allocator, path, 4096) catch return null;
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

pub fn listBackups(io: std.Io, allocator: std.mem.Allocator, backup_name: []const u8) ![]i64 {
    const dir_name = std.fs.path.dirname(backup_name) orelse ".";
    const base_name = std.fs.path.basename(backup_name);

    var dir = openDirIter(io, dir_name) catch return allocator.alloc(i64, 0);
    defer dir.close(io);

    var versions: std.ArrayList(i64) = .empty;
    errdefer versions.deinit(allocator);
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
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
    const io = std.testing.io;
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();

    const rel = (try expandFilename(io, allocator, env, "docs")) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.fs.path.isAbsolute(rel));

    const home = currentHomeDir(allocator, env) orelse return error.SkipZigTest;
    const home_expanded = (try expandFilename(io, allocator, env, "~/tmp")) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.startsWith(u8, home_expanded, home));
}

test "sys writes and reads memory filenames" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const io = std.testing.io;
    const allocator = arena.allocator();
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const memory_path = try tmpPath(allocator, &tmp_dir, "memory.txt");
    try std.testing.expect(try writeFilename(io, memory_path, "/tmp/example.txt"));
    const remembered = (try readFilename(io, allocator, memory_path)) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("/tmp/example.txt", remembered);
}

test "sys lists numeric backup suffixes in order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const io = std.testing.io;
    const allocator = arena.allocator();
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(io, .{ .sub_path = "sample~10", .data = "" });
    try tmp_dir.dir.writeFile(io, .{ .sub_path = "sample~2", .data = "" });
    try tmp_dir.dir.writeFile(io, .{ .sub_path = "sample~x", .data = "" });

    const backup_base = try tmpPath(allocator, &tmp_dir, "sample~");
    const versions = try listBackups(io, allocator, backup_base);
    try std.testing.expectEqual(@as(usize, 2), versions.len);
    try std.testing.expectEqual(@as(i64, 2), versions[0]);
    try std.testing.expectEqual(@as(i64, 10), versions[1]);
}
