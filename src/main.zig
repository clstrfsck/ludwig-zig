const builtin = @import("builtin");
const std = @import("std");

const state = @import("core/state.zig");
const types = @import("core/types.zig");
const filesys = @import("platform/filesys.zig");
const interactive_io = @import("platform/interactive_io.zig");
const batch = @import("runtime/batch.zig");
const interactive = @import("runtime/interactive.zig");
const ncurses = @import("ui/terminal/ncurses.zig");

pub fn main() !void {
    const use_checked_allocator = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (use_checked_allocator) {
        const status = gpa.deinit();
        std.debug.assert(status == .ok);
    };
    const allocator = if (use_checked_allocator) gpa.allocator() else std.heap.page_allocator;

    var editor = try state.Editor.init(allocator);
    defer editor.deinit();

    ncurses.sanityCheck();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var input: ?*types.FileObject = null;
    var output: ?*types.FileObject = null;
    const parse = try filesys.fileCreateOpen(&editor, editor.allocator(), args[1..], .ParseCommand, &input, &output);
    if (!parse.ok) {
        const writer = if (parse.show_usage)
            std.fs.File.stdout().deprecatedWriter()
        else
            std.fs.File.stderr().deprecatedWriter();
        if (parse.message.len > 0) {
            try writer.print("{s}\n", .{parse.message});
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

    const stdin_source = try batch.readStdinAlloc(editor.allocator());
    var session = try batch.startUp(&editor, editor.allocator(), input, output);
    _ = try batch.runBatchCommands(&editor, editor.allocator(), &session, stdin_source);
}
