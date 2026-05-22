const builtin = @import("builtin");
const std = @import("std");
const data = @import("syntax_data_types");

const max_file_size = 1024 * 1024;

const ParsedLine = struct {
    indent: usize,
    content: []const u8,
    line_number: usize,
};

const MappingLine = struct {
    key: []const u8,
    value: ?[]const u8,
};

const Parser = struct {
    allocator: std.mem.Allocator,
    lines: []const ParsedLine,
    index: usize = 0,

    fn peek(self: *const Parser) ?ParsedLine {
        if (self.index >= self.lines.len) {
            return null;
        }
        return self.lines[self.index];
    }

    fn advance(self: *Parser) ?ParsedLine {
        const line = self.peek() orelse return null;
        self.index += 1;
        return line;
    }

    fn childIndent(self: *const Parser, parent_indent: usize) anyerror!usize {
        const next = self.peek() orelse return error.ExpectedIndentedBlock;
        if (next.indent <= parent_indent) {
            return error.ExpectedIndentedBlock;
        }
        return next.indent;
    }

    fn parseSyntaxFile(self: *Parser) anyerror!data.SyntaxFile {
        var filetype: ?[]const u8 = null;
        var detect: data.Detect = .{};
        var rules: []const data.Rule = &.{};

        while (self.peek()) |line| {
            if (line.indent != 0) {
                return error.InvalidIndentation;
            }

            const mapping = try parseMappingLine(line.content);
            _ = self.advance();

            if (std.mem.eql(u8, mapping.key, "filetype")) {
                filetype = try parseScalar(self.allocator, mapping.value orelse return error.MissingScalarValue);
            } else if (std.mem.eql(u8, mapping.key, "detect")) {
                if (mapping.value != null) {
                    return error.UnexpectedInlineDetectValue;
                }
                detect = try self.parseDetect(try self.childIndent(line.indent));
            } else if (std.mem.eql(u8, mapping.key, "rules")) {
                if (mapping.value) |value| {
                    if (!std.mem.eql(u8, std.mem.trim(u8, value, " \t"), "[]")) {
                        return error.UnexpectedInlineRulesValue;
                    }
                } else {
                    rules = try self.parseRules(try self.childIndent(line.indent));
                }
            } else {
                return error.UnknownTopLevelField;
            }
        }

        return .{
            .filetype = filetype orelse return error.MissingFileType,
            .detect = detect,
            .rules = rules,
        };
    }

    fn parseDetect(self: *Parser, indent: usize) anyerror!data.Detect {
        var detect: data.Detect = .{};
        while (self.peek()) |line| {
            if (line.indent < indent) break;
            if (line.indent != indent) return error.InvalidIndentation;

            const mapping = try parseMappingLine(line.content);
            _ = self.advance();
            const value = try parseScalar(self.allocator, mapping.value orelse return error.MissingScalarValue);

            if (std.mem.eql(u8, mapping.key, "filename")) {
                detect.filename = value;
            } else if (std.mem.eql(u8, mapping.key, "header")) {
                detect.header = value;
            } else if (std.mem.eql(u8, mapping.key, "signature")) {
                detect.signature = value;
            } else {
                return error.UnknownDetectField;
            }
        }
        return detect;
    }

    fn parseRules(self: *Parser, indent: usize) anyerror![]const data.Rule {
        var list: std.ArrayList(data.Rule) = .empty;
        errdefer list.deinit(self.allocator);
        while (self.peek()) |line| {
            if (line.indent < indent) break;
            if (line.indent != indent) return error.InvalidIndentation;
            if (!std.mem.startsWith(u8, line.content, "- ")) {
                return error.ExpectedRuleEntry;
            }

            _ = self.advance();
            try list.append(self.allocator, try self.parseRuleItem(line));
        }
        return list.toOwnedSlice(self.allocator);
    }

    fn parseRuleItem(self: *Parser, line: ParsedLine) anyerror!data.Rule {
        const mapping = try parseMappingLine(line.content[2..]);
        if (mapping.value) |value_slice| {
            const value = try parseScalar(self.allocator, value_slice);
            if (std.mem.eql(u8, mapping.key, "include")) {
                return .{ .include = value };
            }
            return .{
                .pattern = .{
                    .group = mapping.key,
                    .regex = value,
                },
            };
        }

        return .{
            .region = try self.parseRegion(mapping.key, try self.childIndent(line.indent)),
        };
    }

    fn parseRegion(self: *Parser, group: []const u8, indent: usize) anyerror!data.RegionRule {
        var start: ?[]const u8 = null;
        var end: ?[]const u8 = null;
        var skip: ?[]const u8 = null;
        var limit_group: ?[]const u8 = null;
        var rules: []const data.Rule = &.{};

        while (self.peek()) |line| {
            if (line.indent < indent) break;
            if (line.indent != indent) return error.InvalidIndentation;

            const mapping = try parseMappingLine(line.content);
            _ = self.advance();

            if (std.mem.eql(u8, mapping.key, "start")) {
                start = try parseScalar(self.allocator, mapping.value orelse return error.MissingScalarValue);
            } else if (std.mem.eql(u8, mapping.key, "end")) {
                end = try parseScalar(self.allocator, mapping.value orelse return error.MissingScalarValue);
            } else if (std.mem.eql(u8, mapping.key, "skip")) {
                skip = try parseScalar(self.allocator, mapping.value orelse return error.MissingScalarValue);
            } else if (std.mem.eql(u8, mapping.key, "limit-group")) {
                limit_group = try parseScalar(self.allocator, mapping.value orelse return error.MissingScalarValue);
            } else if (std.mem.eql(u8, mapping.key, "rules")) {
                if (mapping.value) |value| {
                    if (!std.mem.eql(u8, std.mem.trim(u8, value, " \t"), "[]")) {
                        return error.UnexpectedInlineRulesValue;
                    }
                } else {
                    rules = try self.parseRules(try self.childIndent(line.indent));
                }
            } else {
                return error.UnknownRegionField;
            }
        }

        return .{
            .group = group,
            .start = start orelse return error.MissingRegionStart,
            .end = end orelse return error.MissingRegionEnd,
            .skip = skip,
            .limit_group = limit_group,
            .rules = rules,
        };
    }
};

fn buildParsedLines(
    allocator: std.mem.Allocator,
    input: []const u8,
) ![]const ParsedLine {
    var lines: std.ArrayList(ParsedLine) = .empty;
    errdefer lines.deinit(allocator);

    var start: usize = 0;
    var line_number: usize = 1;
    while (start <= input.len) {
        const line_end = std.mem.indexOfScalarPos(u8, input, start, '\n') orelse input.len;
        var raw = input[start..line_end];
        raw = std.mem.trimEnd(u8, raw, "\r");

        var indent: usize = 0;
        while (indent < raw.len and raw[indent] == ' ') : (indent += 1) {}
        if (indent < raw.len and raw[indent] == '\t') {
            return error.TabIndentationUnsupported;
        }

        const content = raw[indent..];
        if (content.len != 0 and content[0] != '#') {
            try lines.append(allocator, .{
                .indent = indent,
                .content = content,
                .line_number = line_number,
            });
        }

        if (line_end == input.len) break;
        start = line_end + 1;
        line_number += 1;
    }

    return lines.toOwnedSlice(allocator);
}

fn parseMappingLine(content: []const u8) !MappingLine {
    const colon = std.mem.indexOfScalar(u8, content, ':') orelse return error.ExpectedMappingSeparator;
    const key = std.mem.trim(u8, content[0..colon], " \t");
    const raw_value = std.mem.trim(u8, content[colon + 1 ..], " \t");
    if (key.len == 0) {
        return error.EmptyMappingKey;
    }
    return .{
        .key = key,
        .value = if (raw_value.len == 0) null else raw_value,
    };
}

fn parseScalar(allocator: std.mem.Allocator, raw_value: []const u8) ![]const u8 {
    const value = std.mem.trim(u8, raw_value, " \t");
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        return parseDoubleQuotedScalar(allocator, value[1 .. value.len - 1]);
    }
    return allocator.dupe(u8, value);
}

fn parseDoubleQuotedScalar(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    var index: usize = 0;
    while (index < input.len) : (index += 1) {
        const ch = input[index];
        if (ch != '\\') {
            try output.append(allocator, ch);
            continue;
        }
        index += 1;
        if (index >= input.len) return error.DanglingEscape;

        switch (input[index]) {
            '"' => try output.append(allocator, '"'),
            '\\' => try output.append(allocator, '\\'),
            '/' => try output.append(allocator, '/'),
            '0' => try output.append(allocator, 0),
            'a' => try output.append(allocator, 0x07),
            'b' => try output.append(allocator, 0x08),
            't' => try output.append(allocator, '\t'),
            'n' => try output.append(allocator, '\n'),
            'v' => try output.append(allocator, 0x0b),
            'f' => try output.append(allocator, 0x0c),
            'r' => try output.append(allocator, '\r'),
            'e' => try output.append(allocator, 0x1b),
            'x' => {
                if (index + 2 >= input.len) return error.InvalidHexEscape;
                const value = try std.fmt.parseInt(u8, input[index + 1 .. index + 3], 16);
                try output.append(allocator, value);
                index += 2;
            },
            'u' => {
                if (index + 4 >= input.len) return error.InvalidUnicodeEscape;
                const codepoint = try std.fmt.parseInt(u21, input[index + 1 .. index + 5], 16);
                try appendCodepoint(allocator, &output, codepoint);
                index += 4;
            },
            'U' => {
                if (index + 8 >= input.len) return error.InvalidUnicodeEscape;
                const codepoint = try std.fmt.parseInt(u21, input[index + 1 .. index + 9], 16);
                try appendCodepoint(allocator, &output, codepoint);
                index += 8;
            },
            else => return error.UnsupportedEscapeSequence,
        }
    }
    return output.toOwnedSlice(allocator);
}

fn appendCodepoint(
    allocator: std.mem.Allocator,
    output: *std.ArrayList(u8),
    codepoint: u21,
) !void {
    var utf8: [4]u8 = undefined;
    const len = try std.unicode.utf8Encode(codepoint, &utf8);
    try output.appendSlice(allocator, utf8[0..len]);
}

fn collectSyntaxFileNames(allocator: std.mem.Allocator, io: std.Io, input_dir: []const u8) ![]const []const u8 {
    var directory = try std.Io.Dir.cwd().openDir(io, input_dir, .{ .iterate = true });
    defer directory.close(io);

    var names: std.ArrayList([]const u8) = .empty;
    var iterator = directory.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".yaml")) continue;
        try names.append(allocator, try allocator.dupe(u8, entry.name));
    }
    std.sort.heap([]const u8, names.items, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);
    return names.toOwnedSlice(allocator);
}

fn parseSyntaxDirectory(allocator: std.mem.Allocator, io: std.Io, input_dir: []const u8) ![]const data.SyntaxFile {
    const names = try collectSyntaxFileNames(allocator, io, input_dir);
    var syntax_files = try allocator.alloc(data.SyntaxFile, names.len);

    var directory = try std.Io.Dir.cwd().openDir(io, input_dir, .{});
    defer directory.close(io);

    for (names, 0..) |name, index| {
        const source = try directory.readFileAlloc(io, name, allocator, .limited(max_file_size));
        const lines = try buildParsedLines(allocator, source);
        var parser = Parser{
            .allocator = allocator,
            .lines = lines,
        };
        syntax_files[index] = try parser.parseSyntaxFile();
    }

    return syntax_files;
}

fn writeZigString(writer: anytype, value: []const u8) !void {
    try writer.print("\"{f}\"", .{std.zig.fmtString(value)});
}

fn writeOptionalZigString(writer: anytype, value: ?[]const u8) !void {
    if (value) |text| {
        try writeZigString(writer, text);
    } else {
        try writer.writeAll("null");
    }
}

fn emitRuleList(writer: anytype, indent: []const u8, rules: []const data.Rule) !void {
    try writer.writeAll("&[_]data.Rule{");
    if (rules.len == 0) {
        try writer.writeAll("}");
        return;
    }
    try writer.writeByte('\n');
    for (rules) |rule| {
        switch (rule) {
            .include => |include| {
                try writer.writeAll(indent);
                try writer.writeAll("    .{ .include = ");
                try writeZigString(writer, include);
                try writer.writeAll(" },\n");
            },
            .pattern => |pattern| {
                try writer.writeAll(indent);
                try writer.writeAll("    .{ .pattern = .{ .group = ");
                try writeZigString(writer, pattern.group);
                try writer.writeAll(", .regex = ");
                try writeZigString(writer, pattern.regex);
                try writer.writeAll(" } },\n");
            },
            .region => |region| {
                try writer.writeAll(indent);
                try writer.writeAll("    .{ .region = .{\n");
                try writer.writeAll(indent);
                try writer.writeAll("        .group = ");
                try writeZigString(writer, region.group);
                try writer.writeAll(",\n");
                try writer.writeAll(indent);
                try writer.writeAll("        .start = ");
                try writeZigString(writer, region.start);
                try writer.writeAll(",\n");
                try writer.writeAll(indent);
                try writer.writeAll("        .end = ");
                try writeZigString(writer, region.end);
                try writer.writeAll(",\n");
                try writer.writeAll(indent);
                try writer.writeAll("        .skip = ");
                try writeOptionalZigString(writer, region.skip);
                try writer.writeAll(",\n");
                try writer.writeAll(indent);
                try writer.writeAll("        .limit_group = ");
                try writeOptionalZigString(writer, region.limit_group);
                try writer.writeAll(",\n");
                try writer.writeAll(indent);
                try writer.writeAll("        .rules = ");
                var nested_indent_buffer: [256]u8 = undefined;
                const nested_indent = try std.fmt.bufPrint(&nested_indent_buffer, "{s}        ", .{indent});
                try emitRuleList(writer, nested_indent, region.rules);
                try writer.writeByte('\n');
                try writer.writeAll(indent);
                try writer.writeAll("    } },\n");
            },
        }
    }
    try writer.writeAll(indent);
    try writer.writeAll("}");
}

fn generateSyntaxData(allocator: std.mem.Allocator, io: std.Io, input_dir: []const u8) ![]u8 {
    const syntax_files = try parseSyntaxDirectory(allocator, io, input_dir);

    var output: std.ArrayList(u8) = .empty;
    var aw: std.Io.Writer.Allocating = .fromArrayList(allocator, &output);
    const writer = &aw.writer;

    try writer.writeAll("// Code generated by ludwig-syntax-gen; DO NOT EDIT.\n");
    try writer.writeAll("// Syntax definitions originate from highlight assets adapted from micro.\n");
    try writer.writeAll("const data = @import(\"syntax_data_types\");\n\n");
    try writer.writeAll("pub const attribution = ");
    try writeZigString(writer, "Syntax definitions originate from highlight assets adapted from micro; keep attribution and licensing explicit.");
    try writer.writeAll(";\n");
    try writer.writeAll("pub const syntax_files = [_]data.SyntaxFile{\n");

    for (syntax_files) |syntax_file| {
        try writer.writeAll("    .{\n");
        try writer.writeAll("        .filetype = ");
        try writeZigString(writer, syntax_file.filetype);
        try writer.writeAll(",\n");
        try writer.writeAll("        .detect = .{ .filename = ");
        try writeOptionalZigString(writer, syntax_file.detect.filename);
        try writer.writeAll(", .header = ");
        try writeOptionalZigString(writer, syntax_file.detect.header);
        try writer.writeAll(", .signature = ");
        try writeOptionalZigString(writer, syntax_file.detect.signature);
        try writer.writeAll(" },\n");
        try writer.writeAll("        .rules = ");
        try emitRuleList(writer, "        ", syntax_file.rules);
        try writer.writeByte('\n');
        try writer.writeAll("    },\n");
    }
    try writer.writeAll("};\n");

    var result = aw.toArrayList();
    return result.toOwnedSlice(allocator);
}

pub fn main(init: std.process.Init) !void {
    const use_checked_allocator = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer if (use_checked_allocator) {
        const status = gpa.deinit();
        std.debug.assert(status == .ok);
    };

    const base_allocator = if (use_checked_allocator) gpa.allocator() else std.heap.page_allocator;

    var arena = std.heap.ArenaAllocator.init(base_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    if (args.len != 3) {
        std.debug.print("usage: ludwig-syntax-gen <syntax-dir> <output-zig>\n", .{});
        std.process.exit(2);
    }

    const generated = try generateSyntaxData(allocator, init.io, args[1]);
    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = args[2],
        .data = generated,
    });
}

test "parser handles representative go-like syntax file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const input =
        \\filetype: go
        \\
        \\detect:
        \\    filename: "\\.go$"
        \\
        \\rules:
        \\    - statement: "\\b(package|func|return)\\b"
        \\    - constant.string:
        \\        start: "\""
        \\        end: "\""
        \\        skip: "\\\\."
        \\        rules:
        \\            - constant.specialChar: "\\\\."
        \\    - comment:
        \\        start: "//"
        \\        end: "$"
        \\        rules:
        \\            - todo: "(TODO|FIXME):?"
    ;
    const lines = try buildParsedLines(arena.allocator(), input);
    var parser = Parser{
        .allocator = arena.allocator(),
        .lines = lines,
    };
    const syntax_file = try parser.parseSyntaxFile();

    try std.testing.expectEqualStrings("go", syntax_file.filetype);
    try std.testing.expectEqualStrings("\\.go$", syntax_file.detect.filename.?);
    try std.testing.expectEqual(@as(usize, 3), syntax_file.rules.len);
}

test "parser supports nested region rules and empty lists" {
    const input =
        \\filetype: demo
        \\
        \\detect:
        \\    filename: "\\.demo$"
        \\
        \\rules:
        \\    - comment:
        \\        start: "#"
        \\        end: "$"
        \\        rules:
        \\            - todo: "(TODO|FIXME)"
        \\    - string:
        \\        start: "\""
        \\        end: "\""
        \\        rules: []
        \\    - keyword: "if"
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const lines = try buildParsedLines(arena.allocator(), input);
    var parser = Parser{
        .allocator = arena.allocator(),
        .lines = lines,
    };
    const syntax_file = try parser.parseSyntaxFile();

    try std.testing.expectEqualStrings("demo", syntax_file.filetype);
    try std.testing.expectEqual(@as(usize, 3), syntax_file.rules.len);
    try std.testing.expectEqualStrings("comment", syntax_file.rules[0].region.group);
    try std.testing.expectEqual(@as(usize, 1), syntax_file.rules[0].region.rules.len);
    try std.testing.expectEqual(@as(usize, 0), syntax_file.rules[1].region.rules.len);
    try std.testing.expectEqualStrings("keyword", syntax_file.rules[2].pattern.group);
}
