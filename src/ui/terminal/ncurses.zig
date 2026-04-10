const types = @import("../../core/types.zig");

pub const c = @cImport({
    @cInclude("ncurses.h");
});

pub fn sanityCheck() void {
    _ = c.A_BOLD;
    _ = c.A_DIM;
    _ = c.KEY_MAX;
    _ = c.KEY_UP;
    _ = c.KEY_DOWN;
    _ = c.KEY_LEFT;
    _ = c.KEY_RIGHT;
    _ = c.KEY_HOME;
    _ = c.KEY_BTAB;
    _ = c.KEY_IC;
    _ = c.KEY_DC;
    _ = c.KEY_PPAGE;
    _ = c.KEY_NPAGE;
}

pub fn keyMax() c_int {
    return c.KEY_MAX;
}

pub const Dimensions = struct {
    width: isize = 80,
    height: isize = 24,
};

pub const TextStyle = enum {
    normal,
    bold,
    dim,
};

pub const TextSegment = struct {
    text: []const u8,
    style: TextStyle = .normal,
    color_pair: u16 = 0,
};

pub const COLOR_BLACK: i16 = c.COLOR_BLACK;
pub const COLOR_RED: i16 = c.COLOR_RED;
pub const COLOR_GREEN: i16 = c.COLOR_GREEN;
pub const COLOR_YELLOW: i16 = c.COLOR_YELLOW;
pub const COLOR_BLUE: i16 = c.COLOR_BLUE;
pub const COLOR_MAGENTA: i16 = c.COLOR_MAGENTA;
pub const COLOR_CYAN: i16 = c.COLOR_CYAN;
pub const COLOR_WHITE: i16 = c.COLOR_WHITE;

var window: ?*c.WINDOW = null;
var colors_initialized = false;

fn applyFormatting(style: TextStyle, color_pair: u16) void {
    if (window) |win| {
        _ = c.wattrset(win, c.A_NORMAL);
        if (colors_initialized) {
            _ = c.wcolor_set(win, @intCast(color_pair), null);
        }
        switch (style) {
            .normal => {},
            .bold => _ = c.wattron(win, c.A_BOLD),
            .dim => _ = c.wattron(win, c.A_DIM),
        }
    }
}

fn decodeCsiFinal(final: u8) ?isize {
    return switch (final) {
        'A' => types.TerminalKeyCodes.UpArrow,
        'B' => types.TerminalKeyCodes.DownArrow,
        'C' => types.TerminalKeyCodes.RightArrow,
        'D' => types.TerminalKeyCodes.LeftArrow,
        'H' => types.TerminalKeyCodes.Home,
        'Z' => types.TerminalKeyCodes.BackTab,
        else => null,
    };
}

fn decodeCsiTilde(final: u8) ?isize {
    return switch (final) {
        '1', '7' => types.TerminalKeyCodes.Home,
        '2' => types.TerminalKeyCodes.InsertChar,
        '3' => types.TerminalKeyCodes.DeleteChar,
        '5' => types.TerminalKeyCodes.PageUp,
        '6' => types.TerminalKeyCodes.PageDown,
        else => null,
    };
}

pub fn init() !Dimensions {
    window = c.initscr();
    if (window == null) {
        return error.NcursesUnavailable;
    }

    if (c.raw() == c.ERR) {
        _ = c.endwin();
        window = null;
        return error.NcursesUnavailable;
    }

    _ = c.noecho();
    _ = c.nonl();
    _ = c.keypad(window.?, true);
    _ = c.notimeout(window.?, false);
    _ = c.set_escdelay(250);
    _ = c.intrflush(window.?, false);
    _ = c.idlok(window.?, true);
    c.idcok(window.?, true);
    _ = c.scrollok(window.?, false);
    _ = c.curs_set(1);
    _ = c.werase(window.?);
    _ = c.wrefresh(window.?);
    colors_initialized = false;
    return .{};
}

pub fn deinit() void {
    colors_initialized = false;
    window = null;
    _ = c.endwin();
}

pub fn dimensions() Dimensions {
    return .{};
}

pub fn clearScreen() void {
    if (window) |win| {
        _ = c.werase(win);
    }
}

pub fn initColors() bool {
    if (window == null or !c.has_colors()) {
        colors_initialized = false;
        return false;
    }
    _ = c.start_color();
    _ = c.use_default_colors();
    colors_initialized = true;
    return true;
}

pub fn colors() c_int {
    return c.COLORS;
}

pub fn colorPairs() c_int {
    return c.COLOR_PAIRS;
}

pub fn initPair(pair: u16, fg: i16, bg: i16) void {
    if (!colors_initialized) {
        return;
    }
    _ = c.init_pair(@intCast(pair), fg, bg);
}

pub fn setBackgroundPair(pair: u16) void {
    if (!colors_initialized) {
        return;
    }
    const attrs = @as(c.chtype, @intCast(c.COLOR_PAIR(@intCast(pair)))) | @as(c.chtype, @intCast(' '));
    if (window) |win| {
        c.wbkgdset(win, attrs);
    }
    c.bkgdset(attrs);
}

pub fn moveCursor(col: isize, row: isize) void {
    if (window == null or col < 1 or row < 1) {
        return;
    }
    _ = c.wmove(window.?, @intCast(row - 1), @intCast(col - 1));
}

pub fn clearLine() void {
    if (window) |win| {
        _ = c.wclrtoeol(win);
    }
}

pub fn writeText(text: []const u8) void {
    if (window == null or text.len == 0) {
        return;
    }
    _ = c.waddnstr(window.?, text.ptr, @intCast(text.len));
}

pub fn writeByte(byte: u8) void {
    if (window) |win| {
        _ = c.waddch(win, @as(c.chtype, @intCast(byte)));
    }
}

pub fn writeLineAt(row: isize, text: []const u8) void {
    writeLineAtStyled(row, text, .normal);
}

pub fn writeLineAtStyled(row: isize, text: []const u8, style: TextStyle) void {
    moveCursor(1, row);
    clearLine();
    moveCursor(1, row);
    applyFormatting(style, 0);
    writeText(text);
    applyFormatting(.normal, 0);
}

pub fn writeSegmentsAt(row: isize, segments: []const TextSegment) void {
    moveCursor(1, row);
    clearLine();
    moveCursor(1, row);
    for (segments) |segment| {
        if (segment.text.len == 0) continue;
        applyFormatting(segment.style, segment.color_pair);
        writeText(segment.text);
    }
    applyFormatting(.normal, 0);
}

pub fn refresh() void {
    if (window) |win| {
        _ = c.wrefresh(win);
    }
}

pub fn beep() void {
    _ = c.flash();
}

fn mapKey(key: c_int) isize {
    if (@hasDecl(c, "KEY_IL") and key == c.KEY_IL) {
        return types.TerminalKeyCodes.InsertLine;
    }
    if (@hasDecl(c, "KEY_DL") and key == c.KEY_DL) {
        return types.TerminalKeyCodes.DeleteLine;
    }
    if (@hasDecl(c, "KEY_FIND") and key == c.KEY_FIND) {
        return types.TerminalKeyCodes.Find;
    }
    if (@hasDecl(c, "KEY_HELP") and key == c.KEY_HELP) {
        return types.TerminalKeyCodes.Help;
    }
    return switch (key) {
        c.KEY_UP => types.TerminalKeyCodes.UpArrow,
        c.KEY_DOWN => types.TerminalKeyCodes.DownArrow,
        c.KEY_LEFT => types.TerminalKeyCodes.LeftArrow,
        c.KEY_RIGHT => types.TerminalKeyCodes.RightArrow,
        c.KEY_HOME => types.TerminalKeyCodes.Home,
        c.KEY_BTAB => types.TerminalKeyCodes.BackTab,
        c.KEY_IC => types.TerminalKeyCodes.InsertChar,
        c.KEY_DC => types.TerminalKeyCodes.DeleteChar,
        c.KEY_PPAGE => types.TerminalKeyCodes.PageUp,
        c.KEY_NPAGE => types.TerminalKeyCodes.PageDown,
        c.KEY_RESIZE => types.TerminalKeyCodes.WindowResize,
        c.KEY_BACKSPACE => 127,
        c.KEY_ENTER => '\r',
        else => key,
    };
}

fn readQueuedEscapeSequence() isize {
    const win = window.?;
    c.wtimeout(win, 250);
    defer c.wtimeout(win, -1);

    const second = c.wgetch(win);
    if (second == c.ERR) {
        return 27;
    }
    if (second >= c.KEY_MIN) {
        return mapKey(second);
    }

    switch (second) {
        '[' => {
            const third = c.wgetch(win);
            if (third == c.ERR) {
                _ = c.ungetch(second);
                return 27;
            }
            if (third >= c.KEY_MIN) {
                return mapKey(third);
            }
            const third_byte: u8 = @intCast(third);
            if (decodeCsiFinal(third_byte)) |decoded| {
                return decoded;
            }
            if (third_byte >= '0' and third_byte <= '9') {
                const fourth = c.wgetch(win);
                if (fourth == c.ERR) {
                    _ = c.ungetch(third);
                    _ = c.ungetch(second);
                    return 27;
                }
                if (fourth == '~') {
                    if (decodeCsiTilde(third_byte)) |decoded| {
                        return decoded;
                    }
                }
                _ = c.ungetch(fourth);
            }
            _ = c.ungetch(third);
            _ = c.ungetch(second);
            return 27;
        },
        'O' => {
            const third = c.wgetch(win);
            if (third == c.ERR) {
                _ = c.ungetch(second);
                return 27;
            }
            if (third >= c.KEY_MIN) {
                return mapKey(third);
            }
            const third_byte: u8 = @intCast(third);
            if (decodeCsiFinal(third_byte)) |decoded| {
                return decoded;
            }
            _ = c.ungetch(third);
            _ = c.ungetch(second);
            return 27;
        },
        else => {
            _ = c.ungetch(second);
            return 27;
        },
    }
}

pub fn readKey() ?isize {
    if (window == null) {
        return null;
    }
    const key = c.wgetch(window.?);
    if (key == c.ERR) {
        return null;
    }
    // if (key == 27) {
    //     return readQueuedEscapeSequence();
    // }
    return mapKey(key);
}
