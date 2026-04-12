const std = @import("std");

const generated = @import("generated_syntax_data");
const static_data = @import("syntax_data_types");
const pcre2 = @import("pcre2.zig");
const line_ops = @import("../core/line.zig");
const state = @import("../core/state.zig");
const types = @import("../core/types.zig");
const syntax_colors = @import("../platform/syntax_colors.zig");

const CompiledPattern = struct {
    group: []const u8,
    pair: u16,
    regex: pcre2.Regex,

    fn deinit(self: *CompiledPattern) void {
        self.regex.deinit();
    }
};

const CompiledRuleSet = struct {
    patterns: []CompiledPattern = &.{},
    regions: []*CompiledRegion = &.{},

    fn deinit(self: *CompiledRuleSet, allocator: std.mem.Allocator) void {
        for (self.patterns) |*pattern| {
            pattern.deinit();
        }
        allocator.free(self.patterns);
        for (self.regions) |region| {
            region.deinit(allocator);
            allocator.destroy(region);
        }
        allocator.free(self.regions);
    }
};

const CompiledRegion = struct {
    group: []const u8,
    pair: u16,
    limit_group: []const u8,
    limit_pair: u16,
    start: pcre2.Regex,
    end: pcre2.Regex,
    skip: ?pcre2.Regex = null,
    rules: CompiledRuleSet = .{},
    parent: ?*CompiledRegion = null,

    fn deinit(self: *CompiledRegion, allocator: std.mem.Allocator) void {
        self.start.deinit();
        self.end.deinit();
        if (self.skip) |*skip| {
            skip.deinit();
        }
        self.rules.deinit(allocator);
    }
};

const CompiledSyntaxFile = struct {
    filetype: []const u8,
    filename_regex: ?pcre2.Regex = null,
    header_regex: ?pcre2.Regex = null,
    signature_regex: ?pcre2.Regex = null,
    rules: CompiledRuleSet = .{},

    fn deinit(self: *CompiledSyntaxFile, allocator: std.mem.Allocator) void {
        if (self.filename_regex) |*regex| regex.deinit();
        if (self.header_regex) |*regex| regex.deinit();
        if (self.signature_regex) |*regex| regex.deinit();
        self.rules.deinit(allocator);
    }
};

const Registry = struct {
    allocator: std.mem.Allocator,
    files: []CompiledSyntaxFile,

    fn init(allocator: std.mem.Allocator) !Registry {
        var files = try allocator.alloc(CompiledSyntaxFile, generated.syntax_files.len);
        errdefer allocator.free(files);

        for (generated.syntax_files, 0..) |syntax_file, index| {
            files[index] = try compileSyntaxFile(allocator, syntax_file);
        }

        return .{
            .allocator = allocator,
            .files = files,
        };
    }

    fn deinit(self: *Registry) void {
        for (self.files) |*syntax_file| {
            syntax_file.deinit(self.allocator);
        }
        self.allocator.free(self.files);
    }

    fn detect(self: *Registry, filename: []const u8, first_line: []const u8) ?*CompiledSyntaxFile {
        if (filename.len != 0) {
            for (self.files) |*syntax_file| {
                if (syntax_file.filename_regex) |*regex| {
                    if ((regex.find(filename, 0) catch null) != null) {
                        return syntax_file;
                    }
                }
            }
        }

        if (first_line.len != 0) {
            for (self.files) |*syntax_file| {
                if (syntax_file.header_regex) |*regex| {
                    if ((regex.find(first_line, 0) catch null) != null) {
                        return syntax_file;
                    }
                }
            }
        }

        return null;
    }
};

const Highlighter = struct {
    syntax_file: *CompiledSyntaxFile,
    last_region: ?*CompiledRegion = null,

    fn highlightFrame(
        self: *Highlighter,
        store_allocator: std.mem.Allocator,
        temp_allocator: std.mem.Allocator,
        frame: *types.FrameObject,
    ) anyerror!void {
        clearFrameHighlighting(frame);
        var line = frame.FirstGroup.?.FirstLine.?;
        while (line.FLink != null) : (line = line.FLink.?) {
            try self.highlightLine(store_allocator, temp_allocator, line);
        }
    }

    fn highlightLine(
        self: *Highlighter,
        store_allocator: std.mem.Allocator,
        temp_allocator: std.mem.Allocator,
        line: *types.LineHdrObject,
    ) anyerror!void {
        line.HlMatch.clearRetainingCapacity();
        const text = if (line.Str) |str| str.slice(1, line.Used) else "";

        var entries: std.ArrayList(types.HighlightMatchEntry) = .{};
        if (self.last_region) |region| {
            try self.highlightRegion(temp_allocator, &entries, 0, text, region, true);
        } else {
            try self.highlightEmptyRegion(temp_allocator, &entries, 0, text, true);
        }

        std.sort.heap(types.HighlightMatchEntry, entries.items, {}, highlightEntryLessThan);
        for (entries.items) |entry| {
            try line.HlMatch.append(store_allocator, entry);
        }
        line.HlState = if (self.last_region) |region|
            @ptrCast(region)
        else
            null;
    }

    fn highlightRegion(
        self: *Highlighter,
        allocator: std.mem.Allocator,
        entries: *std.ArrayList(types.HighlightMatchEntry),
        start: usize,
        line: []const u8,
        current_region: *CompiledRegion,
        can_match_end: bool,
    ) anyerror!void {
        const line_len = line.len;
        if (start == 0) {
            try setHighlight(entries, allocator, 0, current_region.pair);
        }

        var first_region: ?*CompiledRegion = null;
        var first_loc = pcre2.Match{ .start = line_len, .end = 0 };
        var search_nesting = true;
        const end_loc = try findIndex(allocator, &current_region.end, if (current_region.skip) |*skip| skip else null, line);
        if (end_loc) |loc| {
            if (start == loc.start) {
                search_nesting = false;
            } else {
                first_loc = loc;
            }
        }
        if (search_nesting) {
            for (current_region.rules.regions) |region| {
                const loc = try findIndex(allocator, &region.start, if (region.skip) |*skip| skip else null, line);
                if (loc) |match| {
                    if (match.start < first_loc.start) {
                        first_loc = match;
                        first_region = region;
                    }
                }
            }
        }
        if (first_region != null and first_loc.start != line_len) {
            try setHighlight(entries, allocator, start + first_loc.start, first_region.?.limit_pair);
            try self.highlightEmptyRegion(
                allocator,
                entries,
                start + first_loc.end,
                sliceStart(line, first_loc.end),
                can_match_end,
            );
            try self.highlightRegion(
                allocator,
                entries,
                start + first_loc.end,
                sliceStart(line, first_loc.end),
                first_region.?,
                can_match_end,
            );
            return;
        }

        var full_highlights = try allocator.alloc(u16, line_len);
        @memset(full_highlights, current_region.pair);

        if (search_nesting) {
            for (current_region.rules.patterns) |*pattern| {
                if (!std.mem.eql(u8, current_region.group, current_region.limit_group) and
                    !std.mem.eql(u8, pattern.group, current_region.limit_group))
                {
                    continue;
                }
                const matches = try findAllIndices(allocator, &pattern.regex, line);
                for (matches) |match| {
                    if (end_loc == null or match.start < end_loc.?.start) {
                        const limit = if (match.end > line_len) line_len else match.end;
                        var index = match.start;
                        while (index < limit) : (index += 1) {
                            full_highlights[index] = pattern.pair;
                        }
                    }
                }
            }
        }

        for (full_highlights, 0..) |pair, index| {
            if (index == 0 or pair != full_highlights[index - 1]) {
                try setHighlight(entries, allocator, start + index, pair);
            }
        }

        if (end_loc) |loc| {
            try setHighlight(entries, allocator, start + loc.start, current_region.limit_pair);
            if (current_region.parent == null) {
                try setHighlight(entries, allocator, start + loc.end, 0);
                try self.highlightEmptyRegion(
                    allocator,
                    entries,
                    start + loc.end,
                    sliceStart(line, loc.end),
                    can_match_end,
                );
                return;
            }
            try setHighlight(entries, allocator, start + loc.end, current_region.parent.?.pair);
            try self.highlightRegion(
                allocator,
                entries,
                start + loc.end,
                sliceStart(line, loc.end),
                current_region.parent.?,
                can_match_end,
            );
            return;
        }

        if (can_match_end) {
            self.last_region = current_region;
        }
    }

    fn highlightEmptyRegion(
        self: *Highlighter,
        allocator: std.mem.Allocator,
        entries: *std.ArrayList(types.HighlightMatchEntry),
        start: usize,
        line: []const u8,
        can_match_end: bool,
    ) anyerror!void {
        const line_len = line.len;
        if (line_len == 0) {
            if (can_match_end) {
                self.last_region = null;
            }
            return;
        }

        var first_region: ?*CompiledRegion = null;
        var first_loc = pcre2.Match{ .start = line_len, .end = 0 };
        for (self.syntax_file.rules.regions) |region| {
            const loc = try findIndex(allocator, &region.start, if (region.skip) |*skip| skip else null, line);
            if (loc) |match| {
                if (match.start < first_loc.start) {
                    first_loc = match;
                    first_region = region;
                }
            }
        }
        if (first_region != null and first_loc.start != line_len) {
            try setHighlight(entries, allocator, start + first_loc.start, first_region.?.limit_pair);
            try self.highlightEmptyRegion(
                allocator,
                entries,
                start,
                sliceEnd(line, first_loc.start),
                false,
            );
            try self.highlightRegion(
                allocator,
                entries,
                start + first_loc.end,
                sliceStart(line, first_loc.end),
                first_region.?,
                can_match_end,
            );
            return;
        }

        var full_highlights = try allocator.alloc(u16, line_len);
        @memset(full_highlights, 0);
        for (self.syntax_file.rules.patterns) |*pattern| {
            const matches = try findAllIndices(allocator, &pattern.regex, line);
            for (matches) |match| {
                const limit = if (match.end > line_len) line_len else match.end;
                var index = match.start;
                while (index < limit) : (index += 1) {
                    full_highlights[index] = pattern.pair;
                }
            }
        }
        for (full_highlights, 0..) |pair, index| {
            if (index == 0 or pair != full_highlights[index - 1]) {
                try setHighlight(entries, allocator, start + index, pair);
            }
        }

        if (can_match_end) {
            self.last_region = null;
        }
    }
};

var registry: ?Registry = null;

fn compileSyntaxFile(allocator: std.mem.Allocator, syntax_file: static_data.SyntaxFile) !CompiledSyntaxFile {
    return .{
        .filetype = syntax_file.filetype,
        .filename_regex = if (syntax_file.detect.filename) |pattern| try pcre2.Regex.compile(allocator, pattern) else null,
        .header_regex = if (syntax_file.detect.header) |pattern| try pcre2.Regex.compile(allocator, pattern) else null,
        .signature_regex = if (syntax_file.detect.signature) |pattern| try pcre2.Regex.compile(allocator, pattern) else null,
        .rules = try compileRuleSet(allocator, syntax_file.rules, null),
    };
}

fn compileRuleSet(
    allocator: std.mem.Allocator,
    rules: []const static_data.Rule,
    parent: ?*CompiledRegion,
) !CompiledRuleSet {
    var patterns: std.ArrayList(CompiledPattern) = .{};
    errdefer {
        for (patterns.items) |*pattern| pattern.deinit();
        patterns.deinit(allocator);
    }

    var regions: std.ArrayList(*CompiledRegion) = .{};
    errdefer {
        for (regions.items) |region| {
            region.deinit(allocator);
            allocator.destroy(region);
        }
        regions.deinit(allocator);
    }

    for (rules) |rule| {
        switch (rule) {
            .include => |filetype| {
                std.debug.print("syntax include not supported yet for {s}\n", .{filetype});
                return error.UnsupportedSyntaxInclude;
            },
            .pattern => |pattern| {
                try patterns.append(allocator, .{
                    .group = pattern.group,
                    .pair = syntax_colors.pairForGroup(pattern.group),
                    .regex = try pcre2.Regex.compile(allocator, pattern.regex),
                });
            },
            .region => |region_data| {
                const region = try allocator.create(CompiledRegion);
                region.* = .{
                    .group = region_data.group,
                    .pair = syntax_colors.pairForGroup(region_data.group),
                    .limit_group = region_data.limit_group orelse region_data.group,
                    .limit_pair = syntax_colors.pairForGroup(region_data.limit_group orelse region_data.group),
                    .start = try pcre2.Regex.compile(allocator, region_data.start),
                    .end = try pcre2.Regex.compile(allocator, region_data.end),
                    .skip = if (region_data.skip) |skip| try pcre2.Regex.compile(allocator, skip) else null,
                    .parent = parent,
                };
                region.rules = try compileRuleSet(allocator, region_data.rules, region);
                try regions.append(allocator, region);
            },
        }
    }

    return .{
        .patterns = try patterns.toOwnedSlice(allocator),
        .regions = try regions.toOwnedSlice(allocator),
    };
}

fn ensureRegistry(allocator: std.mem.Allocator) !*Registry {
    if (registry == null) {
        registry = try Registry.init(allocator);
    }
    return &registry.?;
}

// clearFrameHighlighting resets highlight state on all lines, retaining the HlMatch
// backing buffers for reuse on the next highlight pass.
fn clearFrameHighlighting(frame: *types.FrameObject) void {
    if (frame.FirstGroup == null) {
        frame.Highlighter = null;
        return;
    }
    var line = frame.FirstGroup.?.FirstLine.?;
    while (true) {
        line.HlMatch.clearRetainingCapacity();
        line.HlState = null;
        if (line.FLink == null) {
            break;
        }
        line = line.FLink.?;
    }
    frame.Highlighter = null;
}

// freeFrameHighlighting releases the HlMatch backing buffers using the provided allocator.
// Use this when highlight data will not be immediately rebuilt (shutdown, or when
// highlighting is disabled/inapplicable for this frame).
fn freeFrameHighlighting(allocator: std.mem.Allocator, frame: *types.FrameObject) void {
    if (frame.FirstGroup == null) {
        frame.Highlighter = null;
        return;
    }
    var line = frame.FirstGroup.?.FirstLine.?;
    while (true) {
        line.HlMatch.clearAndFree(allocator);
        line.HlState = null;
        if (line.FLink == null) {
            break;
        }
        line = line.FLink.?;
    }
    frame.Highlighter = null;
}

fn highlightEntryLessThan(_: void, lhs: types.HighlightMatchEntry, rhs: types.HighlightMatchEntry) bool {
    return lhs.Position < rhs.Position;
}

fn setHighlight(
    entries: *std.ArrayList(types.HighlightMatchEntry),
    allocator: std.mem.Allocator,
    position: usize,
    pair: u16,
) !void {
    for (entries.items) |*entry| {
        if (entry.Position == position) {
            entry.Pair = pair;
            return;
        }
    }
    try entries.append(allocator, .{ .Position = position, .Pair = pair });
}

fn sliceStart(subject: []const u8, index: usize) []const u8 {
    return subject[@min(index, subject.len)..];
}

fn sliceEnd(subject: []const u8, index: usize) []const u8 {
    return subject[0..@min(index, subject.len)];
}

fn findIndex(
    allocator: std.mem.Allocator,
    regex: *const pcre2.Regex,
    skip: ?*const pcre2.Regex,
    subject: []const u8,
) !?pcre2.Match {
    if (skip) |skip_regex| {
        const masked = try allocator.dupe(u8, subject);
        var offset: usize = 0;
        while (try skip_regex.find(masked, offset)) |match| {
            @memset(masked[match.start..match.end], ' ');
            if (match.end > offset) {
                offset = match.end;
            } else {
                offset += 1;
            }
            if (offset > masked.len) {
                break;
            }
        }
        return regex.find(masked, 0);
    }
    return regex.find(subject, 0);
}

fn findAllIndices(
    allocator: std.mem.Allocator,
    regex: *const pcre2.Regex,
    subject: []const u8,
) ![]const pcre2.Match {
    var matches: std.ArrayList(pcre2.Match) = .{};
    var offset: usize = 0;
    while (offset <= subject.len) {
        const match = try regex.find(subject, offset) orelse break;
        try matches.append(allocator, match);
        if (match.end > offset) {
            offset = match.end;
        } else {
            offset += 1;
        }
    }
    return matches.items;
}

fn frameFirstLine(frame: *types.FrameObject) []const u8 {
    const line = frame.FirstGroup.?.FirstLine.?;
    if (line.FLink == null or line.Str == null) {
        return "";
    }
    return line.Str.?.slice(1, line.Used);
}

pub fn deinit() void {
    if (registry) |*compiled| {
        compiled.deinit();
        registry = null;
    }
}

pub fn deinitHighlighting(base_allocator: std.mem.Allocator, editor: *const state.Editor) void {
    var span = editor.FirstSpan;
    while (span) |s| : (span = s.FLink) {
        if (s.Frame) |frame| {
            freeFrameHighlighting(base_allocator, frame);
        }
    }
}

pub fn applyDirty(editor: *state.Editor, frame: *types.FrameObject) void {
    if (!editor.FileData.Highlighting or editor.LudwigMode != .LudwigScreen or frame.InputFile == 0) {
        freeFrameHighlighting(editor.base_allocator, frame);
        frame.DirtyLine = 0;
        return;
    }
    if (frame.DirtyLine == 0) {
        return;
    }

    syntax_colors.init();
    const compiled = ensureRegistry(editor.base_allocator) catch {
        freeFrameHighlighting(editor.base_allocator, frame);
        frame.DirtyLine = 0;
        return;
    };

    const input_file = editor.Files[@intCast(frame.InputFile)] orelse {
        freeFrameHighlighting(editor.base_allocator, frame);
        frame.DirtyLine = 0;
        return;
    };

    const syntax_file = compiled.detect(input_file.Filename, frameFirstLine(frame)) orelse {
        freeFrameHighlighting(editor.base_allocator, frame);
        frame.DirtyLine = 0;
        return;
    };

    var temp_arena = std.heap.ArenaAllocator.init(editor.base_allocator);
    defer temp_arena.deinit();

    var highlighter = Highlighter{ .syntax_file = syntax_file };
    highlighter.highlightFrame(editor.base_allocator, temp_arena.allocator(), frame) catch {
        freeFrameHighlighting(editor.base_allocator, frame);
        frame.DirtyLine = 0;
        return;
    };
    frame.Highlighter = @ptrCast(syntax_file);
    frame.DirtyLine = 0;
}

test "generated syntax registry detects go files and highlights tokens" {
    syntax_colors.init();
    var compiled = try Registry.init(std.testing.allocator);
    defer compiled.deinit();

    const syntax_file = compiled.detect("sample.go", "package main") orelse {
        try std.testing.expect(false);
        return;
    };
    try std.testing.expectEqualStrings("go", syntax_file.filetype);

    var fixture_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer fixture_arena.deinit();

    const fixture = try line_ops.createContentFrame(fixture_arena.allocator(), &[_][]const u8{
        "package main",
        "// TODO: hi",
    });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var highlighter = Highlighter{ .syntax_file = syntax_file };
    try highlighter.highlightFrame(fixture_arena.allocator(), arena.allocator(), fixture.frame);

    try std.testing.expect(fixture.content_lines[0].HlMatch.items.len > 0);
    try std.testing.expect(fixture.content_lines[1].HlMatch.items.len > 0);
    try std.testing.expectEqual(@as(u16, syntax_colors.pairForGroup("preproc")), fixture.content_lines[0].HlMatch.items[0].Pair);
}
