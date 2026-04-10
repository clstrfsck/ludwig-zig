const std = @import("std");
const terminal = @import("../ui/terminal/ncurses.zig");

const GroupColor = struct {
    name: []const u8,
    color: []const u8,
};

const GroupPair = struct {
    name: []const u8,
    pair: u16,
};

const basic_pairs = [_]GroupPair{
    .{ .name = "statement", .pair = 1 },
    .{ .name = "keyword", .pair = 1 },
    .{ .name = "type", .pair = 4 },
    .{ .name = "string", .pair = 2 },
    .{ .name = "stringx", .pair = 2 },
    .{ .name = "comment", .pair = 3 },
    .{ .name = "preproc", .pair = 5 },
    .{ .name = "constant", .pair = 6 },
    .{ .name = "special", .pair = 7 },
    .{ .name = "underlined", .pair = 7 },
    .{ .name = "todo", .pair = 7 },
    .{ .name = "error", .pair = 8 },
};

const twilight_scheme = [_]GroupColor{
    .{ .name = "default", .color = "#F8F8F8,#141414" },
    .{ .name = "color-column", .color = "#1B1B1B" },
    .{ .name = "comment", .color = "#5F5A60" },
    .{ .name = "constant", .color = "#CF6A4C" },
    .{ .name = "constant.specialChar", .color = "#DDF2A4" },
    .{ .name = "constant.string", .color = "#8F9D6A" },
    .{ .name = "current-line-number", .color = "#868686" },
    .{ .name = "cursor-line", .color = "#1B1B1B" },
    .{ .name = "divider", .color = "#1E1E1E" },
    .{ .name = "error", .color = "#D2A8A1" },
    .{ .name = "diff-added", .color = "#00AF00" },
    .{ .name = "diff-modified", .color = "#FFAF00" },
    .{ .name = "diff-deleted", .color = "#D70000" },
    .{ .name = "gutter-error", .color = "#9B859D" },
    .{ .name = "gutter-warning", .color = "#9B859D" },
    .{ .name = "hlsearch", .color = "#141414" },
    .{ .name = "identifier", .color = "#9B703F" },
    .{ .name = "identifier.class", .color = "#DAD085" },
    .{ .name = "identifier.var", .color = "#7587A6" },
    .{ .name = "indent-char", .color = "#515151" },
    .{ .name = "line-number", .color = "#868686" },
    .{ .name = "preproc", .color = "#E0C589" },
    .{ .name = "special", .color = "#E0C589" },
    .{ .name = "statement", .color = "#CDA869" },
    .{ .name = "statusline", .color = "#515151" },
    .{ .name = "symbol", .color = "#AC885B" },
    .{ .name = "symbol.brackets", .color = "#F8F8F8" },
    .{ .name = "symbol.operator", .color = "#CDA869" },
    .{ .name = "symbol.tag", .color = "#AC885B" },
    .{ .name = "tabbar", .color = "#F2F0EC" },
    .{ .name = "todo", .color = "#8B98AB" },
    .{ .name = "type", .color = "#F9EE98" },
    .{ .name = "type.keyword", .color = "#CDA869" },
    .{ .name = "underlined", .color = "#8996A8" },
    .{ .name = "match-brace", .color = "#141414" },
    .{ .name = "tab-error", .color = "#D75F5F" },
    .{ .name = "trailingws", .color = "#D75F5F" },
};

var initialized = false;
var colors_enabled = false;
var default_pair: u16 = 0;
var active_pairs: [twilight_scheme.len]GroupPair = undefined;
var active_pair_count: usize = 0;

pub fn init() void {
    if (initialized) {
        return;
    }
    initialized = true;
    colors_enabled = terminal.initColors();
    if (!colors_enabled) {
        return;
    }
    if (terminal.colors() < 8 or terminal.colorPairs() < 8) {
        colors_enabled = false;
        return;
    }
    if (terminal.colors() < 256 or terminal.colorPairs() < 256) {
        initBasicScheme();
        return;
    }
    initTwilightScheme();
}

pub fn reset() void {
    initialized = false;
    colors_enabled = false;
    default_pair = 0;
    active_pair_count = 0;
}

pub fn pairForGroup(group_name: []const u8) u16 {
    if (!colors_enabled or group_name.len == 0) {
        return 0;
    }

    var current = group_name;
    while (current.len != 0) {
        for (active_pairs[0..active_pair_count]) |entry| {
            if (std.mem.eql(u8, current, entry.name)) {
                return entry.pair;
            }
        }

        const dot = std.mem.lastIndexOfScalar(u8, current, '.') orelse break;
        current = current[0..dot];
    }
    return 0;
}

fn initBasicScheme() void {
    terminal.initPair(1, terminal.COLOR_YELLOW, -1);
    terminal.initPair(2, terminal.COLOR_GREEN, -1);
    terminal.initPair(3, terminal.COLOR_CYAN, -1);
    terminal.initPair(4, terminal.COLOR_BLUE, -1);
    terminal.initPair(5, terminal.COLOR_MAGENTA, -1);
    terminal.initPair(6, terminal.COLOR_WHITE, -1);
    terminal.initPair(7, terminal.COLOR_WHITE, -1);
    terminal.initPair(8, terminal.COLOR_RED, -1);
    active_pair_count = basic_pairs.len;
    @memcpy(active_pairs[0..basic_pairs.len], basic_pairs[0..]);
}

fn initTwilightScheme() void {
    active_pair_count = 0;
    default_pair = 0;

    var pair_index: u16 = 1;
    var default_fg: i16 = -1;
    var default_bg: i16 = -1;

    for (twilight_scheme) |entry| {
        var fg: i16 = default_fg;
        var bg: i16 = default_bg;
        if (std.mem.eql(u8, entry.name, "default")) {
            const parsed = hexesToXterms(entry.color);
            fg = parsed.fg;
            bg = parsed.bg;
            default_fg = fg;
            default_bg = bg;
            default_pair = pair_index;
            terminal.initPair(pair_index, fg, bg);
            terminal.setBackgroundPair(pair_index);
            active_pairs[active_pair_count] = .{ .name = entry.name, .pair = pair_index };
            active_pair_count += 1;
            pair_index += 1;
            continue;
        }

        if (!std.mem.eql(u8, entry.color, "default")) {
            const parsed = hexesToXterms(entry.color);
            if (parsed.fg >= 0) {
                fg = parsed.fg;
            }
            if (parsed.bg >= 0) {
                bg = parsed.bg;
            }
        }

        terminal.initPair(pair_index, fg, bg);
        active_pairs[active_pair_count] = .{ .name = entry.name, .pair = pair_index };
        active_pair_count += 1;
        pair_index += 1;
    }
}

const ParsedPair = struct {
    fg: i16 = -1,
    bg: i16 = -1,
};

fn squareDistance(r1: i32, g1: i32, b1: i32, r2: i32, g2: i32, b2: i32) i32 {
    return (r1 - r2) * (r1 - r2) + (g1 - g2) * (g1 - g2) + (b1 - b2) * (b1 - b2);
}

fn hexToXterm(hex: []const u8) ?i16 {
    const trimmed = if (hex.len > 0 and hex[0] == '#') hex[1..] else hex;
    if (trimmed.len != 6) {
        return null;
    }

    const r = std.fmt.parseInt(i32, trimmed[0..2], 16) catch return null;
    const g = std.fmt.parseInt(i32, trimmed[2..4], 16) catch return null;
    const b = std.fmt.parseInt(i32, trimmed[4..6], 16) catch return null;

    var best_index: i16 = 0;
    var min_distance: i32 = std.math.maxInt(i32);

    if (r == g and g == b) {
        const black_distance = squareDistance(r, g, b, 0, 0, 0);
        if (black_distance < min_distance) {
            min_distance = black_distance;
            best_index = 16;
        }

        const white_distance = squareDistance(r, g, b, 255, 255, 255);
        if (white_distance < min_distance) {
            min_distance = white_distance;
            best_index = 231;
        }

        var gray_index: i32 = 232;
        while (gray_index <= 255) : (gray_index += 1) {
            const value = 8 + (gray_index - 232) * 10;
            const distance = squareDistance(r, g, b, value, value, value);
            if (distance < min_distance) {
                min_distance = distance;
                best_index = @intCast(gray_index);
            }
        }
        return best_index;
    }

    const steps = [_]i32{ 0, 95, 135, 175, 215, 255 };
    for (steps, 0..) |red, r_index| {
        for (steps, 0..) |green, g_index| {
            for (steps, 0..) |blue, b_index| {
                const distance = squareDistance(r, g, b, red, green, blue);
                if (distance < min_distance) {
                    min_distance = distance;
                    best_index = @intCast(16 + (36 * r_index) + (6 * g_index) + b_index);
                }
            }
        }
    }
    return best_index;
}

fn hexesToXterms(hexes: []const u8) ParsedPair {
    var result: ParsedPair = .{};
    var iterator = std.mem.splitScalar(u8, hexes, ',');
    if (iterator.next()) |fg_hex| {
        result.fg = hexToXterm(fg_hex) orelse -1;
    }
    if (iterator.next()) |bg_hex| {
        result.bg = hexToXterm(bg_hex) orelse -1;
    }
    return result;
}

test "syntax colors map twilight palette to xterm pairs" {
    try std.testing.expectEqual(@as(?i16, 186), hexToXterm("#E0C589"));
    try std.testing.expectEqual(@as(?i16, 233), hexToXterm("#141414"));
}
