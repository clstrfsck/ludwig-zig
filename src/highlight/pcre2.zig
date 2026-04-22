const std = @import("std");

pub const c = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

pub const Match = struct {
    start: usize,
    end: usize,
};

pub const Regex = struct {
    code: *c.pcre2_code_8,

    pub fn compile(allocator: std.mem.Allocator, pattern_in: []const u8) !Regex {
        const pattern = try normalizePattern(allocator, pattern_in);
        defer allocator.free(pattern);

        var error_code: c_int = 0;
        var error_offset: c.PCRE2_SIZE = 0;
        const code = c.pcre2_compile_8(
            pattern.ptr,
            pattern.len,
            c.PCRE2_UTF | c.PCRE2_UCP,
            &error_code,
            &error_offset,
            null,
        ) orelse {
            var message_buffer: [256]u8 = undefined;
            const message_len = c.pcre2_get_error_message_8(
                error_code,
                &message_buffer,
                message_buffer.len,
            );
            const message = if (message_len > 0)
                message_buffer[0..@intCast(message_len)]
            else
                "unknown pcre2 error";
            std.debug.print(
                "pcre2 compile failed at offset {d} for /{s}/: {s}\n",
                .{ error_offset, pattern_in, message },
            );
            return error.InvalidRegex;
        };
        return .{ .code = code };
    }

    pub fn deinit(self: *Regex) void {
        c.pcre2_code_free_8(self.code);
    }

    pub fn find(self: *const Regex, subject: []const u8, start_offset: usize) !?Match {
        const match_data = c.pcre2_match_data_create_from_pattern_8(self.code, null) orelse return error.OutOfMemory;
        defer c.pcre2_match_data_free_8(match_data);

        const rc = c.pcre2_match_8(
            self.code,
            if (subject.len == 0) "" else subject.ptr,
            subject.len,
            start_offset,
            0,
            match_data,
            null,
        );
        if (rc == c.PCRE2_ERROR_NOMATCH) {
            return null;
        }
        if (rc < 0) {
            return error.RegexMatchFailed;
        }

        const ovector = c.pcre2_get_ovector_pointer_8(match_data);
        return .{
            .start = @intCast(ovector[0]),
            .end = @intCast(ovector[1]),
        };
    }
};

fn normalizePattern(allocator: std.mem.Allocator, pattern: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    var index: usize = 0;
    while (index < pattern.len) : (index += 1) {
        if (pattern[index] == '\\' and index + 1 < pattern.len and (pattern[index + 1] == '<' or pattern[index + 1] == '>')) {
            try output.appendSlice(allocator, "\\b");
            index += 1;
            continue;
        }
        try output.append(allocator, pattern[index]);
    }

    return output.toOwnedSlice(allocator);
}
