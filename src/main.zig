const builtin = @import("builtin");
const std = @import("std");

const state = @import("core/state.zig");
const types = @import("core/types.zig");
const filesys = @import("platform/filesys.zig");
const interactive_io = @import("platform/interactive_io.zig");
const batch = @import("runtime/batch.zig");
const interactive = @import("runtime/interactive.zig");
const ncurses = @import("ui/terminal/ncurses.zig");

pub fn main(init: std.process.Init) !void {
    const use_checked_allocator = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer if (use_checked_allocator) {
        const status = gpa.deinit();
        std.debug.assert(status == .ok);
    };
    const allocator = if (use_checked_allocator) gpa.allocator() else std.heap.page_allocator;

    var env = try init.minimal.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(init.io, allocator, env);
    defer editor.deinit();

    ncurses.sanityCheck();

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    var input: ?*types.FileObject = null;
    var output: ?*types.FileObject = null;
    const parse = try filesys.fileCreateOpen(&editor, args[1..], .parse_command, &input, &output);
    if (!parse.ok) {
        if (parse.message.len > 0) {
            var buf: [1024]u8 = undefined;
            var writer = if (parse.show_usage)
                std.Io.File.stdout().writer(editor.io, &buf).interface
            else
                std.Io.File.stderr().writer(editor.io, &buf).interface;
            try writer.print("{s}\n", .{parse.message});
            try writer.flush();
        }
        if (parse.show_usage) {
            return;
        }
        return error.InvalidArguments;
    }

    if (interactive_io.interactiveAvailable()) {
        const session = try interactive.startUp(&editor, editor.allocator(), input, output);
        try interactive.run(&editor, editor.allocator(), session);
        return;
    }

    const stdin_source = try batch.readStdinAlloc(editor.io, editor.allocator());
    var session = try batch.startUp(&editor, input, output);
    _ = try batch.runBatchCommands(&editor, &session, stdin_source);
}
