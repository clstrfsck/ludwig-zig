const chars = @import("chars.zig");
const dfa = @import("dfa.zig");
const interactive_io = @import("../platform/interactive_io.zig");
const std = @import("std");
const line_ops = @import("line.zig");
const mark_ops = @import("mark.zig");
const span_ops = @import("span.zig");
const state = @import("state.zig");
const str_object = @import("str_object.zig");
const tpar_ops = @import("tpar.zig");
const types = @import("types.zig");
const user_ops = @import("user.zig");

const new_values_prompt = "  New Values: ";
const end_of_file_prefix = "<End of File>   ";
const invalid_cmd_introducer_message = "Invalid command introducer.";
const unrecognized_key_name_message = "Unrecognized key name";
const screen_mode_only_message = "Command allowed in screen mode only.";
const mode_error_message = "Illegal Mode specification -- must be O,C or I";
const syntax_error_in_options_message = "Syntax error in options.";
const invalid_ruler_message = "Invalid Ruler.";
const out_of_range_tab_value_message = "Invalid value for tab stop.";
const bad_format_in_tab_table_message = "Bad Format for list of Tab stops.";
const invalid_t_option_message = "Invalid Tab Option.";
const left_margin_ge_right_message = "Specified Left Margin is not less than Right Margin.";
const margin_out_of_range_message = "Margin out of Range.";
const margin_syntax_error_message = "Margin Syntax Error.";
const unknown_option_message = "Not a valid option.";
const invalid_parameter_code_message = "Invalid Parameter Code.";
const syntax_error_in_param_cmd_message = "Syntax error in parameter command.";
const invalid_screen_height_message = "Invalid height for screen.";
const screen_width_invalid_message = "Invalid screen width specified.";

fn emitFrameMessage(editor: *const state.Editor, message: []const u8) void {
    if (editor.ludwig_mode == .ludwig_screen) {
        interactive_io.queueStatusMessage(message);
    }
}

pub fn frameEdit(
    editor: *state.Editor,
    return_frame: ?*types.FrameObject,
    frame_name: []const u8,
) !?*types.FrameObject {
    const resolved_name = if (frame_name.len == 0) types.default_frame_name else frame_name;

    var span_ptr: ?*types.SpanObject = null;
    var span_prev: ?*types.SpanObject = null;
    if (try span_ops.spanFind(editor, resolved_name, &span_ptr, &span_prev)) {
        if (span_ptr.?.frame) |frame| {
            if (return_frame != null and frame != return_frame.?) {
                frame.return_frame = return_frame;
            }
            return frame;
        }
        return null;
    }

    const frame = try editor.allocator().create(types.FrameObject);
    frame.* = .{
        .marks = editor.initial_marks,
        .scr_height = editor.initial_scr_height,
        .scr_width = editor.initial_scr_width,
        .scr_offset = editor.initial_scr_offset,
        .scr_dot_line = 1,
        .return_frame = return_frame,
        .space_limit = editor.file_data.space,
        .space_left = editor.file_data.space,
        .margin_left = editor.initial_margin_left,
        .margin_right = editor.initial_margin_right,
        .margin_top = editor.initial_margin_top,
        .margin_bottom = editor.initial_margin_bottom,
        .tab_stops = editor.initial_tab_stops,
        .options = editor.initial_options,
    };

    const group = try line_ops.lineEOPCreate(editor.allocator(), frame);
    frame.first_group = group;
    frame.last_group = group;
    try line_ops.setSentinelDisplayContent(editor.allocator(), group.first_line.?, end_of_file_prefix, resolved_name);

    const span = try editor.allocator().create(types.SpanObject);
    span.* = .{
        .b_link = span_prev,
        .f_link = span_ptr,
        .frame = frame,
        .name = try editor.allocator().dupe(u8, resolved_name),
    };
    if (span_prev) |prev| {
        prev.f_link = span;
    } else {
        editor.first_span = span;
    }
    if (span_ptr) |next| {
        next.b_link = span;
    }

    try mark_ops.markCreate(editor.allocator(), group.first_line.?, 1, &span.mark_one);
    try mark_ops.markCreate(editor.allocator(), group.last_line.?, 1, &span.mark_two);
    frame.span = span;
    try mark_ops.markCreate(editor.allocator(), group.first_line.?, editor.initial_margin_left, &frame.dot);
    return frame;
}

pub fn frameKill(
    editor: *state.Editor,
    current_frame: *types.FrameObject,
    frame_name: []const u8,
) !bool {
    var span_ptr: ?*types.SpanObject = null;
    var span_prev: ?*types.SpanObject = null;
    if (!try span_ops.spanFind(editor, frame_name, &span_ptr, &span_prev)) {
        return false;
    }
    if (span_ptr.?.frame == null) {
        return false;
    }

    const target_frame = span_ptr.?.frame.?;
    if (target_frame == current_frame or target_frame == editor.screen.frame or target_frame.options.special_frame) {
        return false;
    }
    if (target_frame.input_file != 0 or target_frame.output_file != 0) {
        return false;
    }

    var iter = editor.first_span;
    while (iter) |span| {
        const next = span.f_link;
        if (span.frame) |span_frame| {
            if (span_frame.return_frame == target_frame) {
                span_frame.return_frame = null;
            }
        } else if (span.mark_one != null and span.mark_one.?.line.group.?.frame == target_frame) {
            var slot = iter;
            if (!span_ops.spanDestroy(editor, &slot)) {
                return false;
            }
        }
        iter = next;
    }

    target_frame.span.?.frame = null;
    var frame_span = target_frame.span;
    if (!span_ops.spanDestroy(editor, &frame_span)) {
        return false;
    }
    target_frame.span = null;

    mark_ops.markDestroy(editor.allocator(), &target_frame.dot);
    var mark_index: usize = 0;
    while (mark_index < target_frame.marks.len) : (mark_index += 1) {
        mark_ops.markDestroy(editor.allocator(), &target_frame.marks[mark_index]);
    }

    const last_content = target_frame.last_group.?.last_line.?.b_link;
    if (last_content != null) {
        line_ops.linesExtract(target_frame.first_group.?.first_line.?, last_content.?);
    }

    target_frame.first_group = null;
    target_frame.last_group = null;

    dfa.patternDFATableKill(editor.allocator(), &target_frame.eqs_pattern_ptr);
    dfa.patternDFATableKill(editor.allocator(), &target_frame.get_pattern_ptr);
    dfa.patternDFATableKill(editor.allocator(), &target_frame.rep_pattern_ptr);
    return true;
}

const TparParser = struct {
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    request: *types.TParObject,
    pos: isize = 1,

    fn nextChar(self: *TparParser) u8 {
        while (self.pos < self.request.len and self.request.str.?.get(self.pos) == ' ') {
            self.pos += 1;
        }
        var ch: u8 = 0;
        if (self.pos > self.request.len or self.request.str.?.get(self.pos) == ' ') {
            ch = 0;
        } else {
            ch = self.request.str.?.get(self.pos);
        }
        if (self.pos <= self.request.len) {
            self.pos += 1;
        }
        return ch;
    }

    fn toInt(self: *TparParser) ?isize {
        return tpar_ops.tparToIntMessage(self.editor, self.request, &self.pos);
    }

    fn setMode(self: *TparParser) bool {
        switch (self.nextChar()) {
            'I' => self.editor.edit_mode = .mode_insert,
            'O' => self.editor.edit_mode = .mode_overtype,
            'C' => self.editor.edit_mode = .mode_command,
            else => {
                emitFrameMessage(self.editor, mode_error_message);
                return false;
            },
        }
        return true;
    }

    fn setCmdIntr(self: *TparParser) bool {
        if (self.editor.ludwig_mode != .ludwig_screen) {
            emitFrameMessage(self.editor, screen_mode_only_message);
            return false;
        }

        while (self.pos <= self.request.len and self.request.str.?.get(self.pos) == ' ') {
            self.pos += 1;
        }
        const start = self.pos;
        while (self.pos <= self.request.len and self.request.str.?.get(self.pos) != ',') {
            self.pos += 1;
        }
        const end = self.pos - 1;
        if (end < start) {
            emitFrameMessage(self.editor, invalid_cmd_introducer_message);
            return false;
        }
        const len: usize = @intCast(end - start + 1);
        const key_name = std.mem.trim(u8, self.request.str.?.slice(start, @intCast(len)), " ");
        if (key_name.len == 0) {
            emitFrameMessage(self.editor, invalid_cmd_introducer_message);
            return false;
        }

        if (key_name.len == 1) {
            const ch = key_name[0];
            if (!chars.chIsPunctuation(ch)) {
                emitFrameMessage(self.editor, invalid_cmd_introducer_message);
                return false;
            }
            self.editor.command_introducer = ch;
            return true;
        }

        const key_code = user_ops.userKeyNameToCode(self.editor, key_name) orelse {
            emitFrameMessage(self.editor, unrecognized_key_name_message);
            return false;
        };
        if (key_code >= 0 and key_code < types.lookup_count and self.editor.key_introducers.isSet(@intCast(key_code))) {
            emitFrameMessage(self.editor, invalid_cmd_introducer_message);
            return false;
        }

        self.editor.command_introducer = key_code;
        return true;
    }

    fn setOptions(self: *TparParser, frame: *types.FrameObject, set_initial: bool) bool {
        var ok = false;
        var ch = self.nextChar();
        if (ch == '(') {
            while (true) {
                var set_on = true;
                ch = self.nextChar();
                if (ch == '-') {
                    set_on = false;
                    ch = self.nextChar();
                }
                if (set_initial and !setOpt(frame, ch, set_on, &self.editor.initial_options)) {
                    emitFrameMessage(self.editor, unknown_option_message);
                    return false;
                }
                ok = setOpt(frame, ch, set_on, &frame.options);
                ch = self.nextChar();
                if (ch != ',' and ch != ')') {
                    emitFrameMessage(self.editor, syntax_error_in_options_message);
                    return false;
                }
                if (!ok or ch == ')') {
                    break;
                }
            }
        } else {
            var set_on = true;
            if (ch == '-') {
                set_on = false;
                ch = self.nextChar();
            }
            if (set_initial and !setOpt(frame, ch, set_on, &self.editor.initial_options)) {
                emitFrameMessage(self.editor, unknown_option_message);
                return false;
            }
            ok = setOpt(frame, ch, set_on, &frame.options);
        }
        if (!ok) {
            emitFrameMessage(self.editor, unknown_option_message);
        }
        return ok;
    }

    fn getMar(self: *TparParser, ch: *u8, lo_bnd: isize, hi_bnd: isize, margin: *isize) bool {
        if (ch.* >= '0' and ch.* <= '9') {
            self.pos -= 1;
            const m = self.toInt() orelse return false;
            if (m < lo_bnd or m > hi_bnd) {
                emitFrameMessage(self.editor, margin_out_of_range_message);
                return false;
            }
            ch.* = self.nextChar();
            margin.* = m;
        }
        return true;
    }

    fn getMargins(
        self: *TparParser,
        frame: *types.FrameObject,
        lo_bnd: isize,
        hi_bnd: isize,
        lower: *isize,
        upper: *isize,
        lr: bool,
    ) bool {
        var ch = self.nextChar();
        if (ch != '(') {
            emitFrameMessage(self.editor, margin_syntax_error_message);
            return false;
        }
        ch = self.nextChar();
        if (ch == '.') {
            lower.* = if (lr) frame.dot.?.col else frame.dot.?.line.scr_row_num;
            ch = self.nextChar();
        } else if (!self.getMar(&ch, lo_bnd, hi_bnd, lower)) {
            return false;
        }
        if (ch == ',') {
            ch = self.nextChar();
            if (ch == '.') {
                upper.* = if (lr) frame.dot.?.col else frame.scr_height - frame.dot.?.line.scr_row_num;
                ch = self.nextChar();
            } else if (!self.getMar(&ch, lo_bnd, hi_bnd, upper)) {
                return false;
            }
        }
        if (ch != ')') {
            emitFrameMessage(self.editor, margin_syntax_error_message);
            return false;
        }
        return true;
    }

    fn setLRMargin(self: *TparParser, frame: *types.FrameObject, set_initial: bool) bool {
        var left = if (set_initial) self.editor.initial_margin_left else frame.margin_left;
        var right = if (set_initial) self.editor.initial_margin_right else frame.margin_right;
        if (!self.getMargins(frame, 1, types.max_str_len, &left, &right, true)) {
            return false;
        }
        if (left >= right) {
            emitFrameMessage(self.editor, left_margin_ge_right_message);
            return false;
        }
        if (set_initial) {
            self.editor.initial_margin_left = left;
            self.editor.initial_margin_right = right;
        }
        frame.margin_left = left;
        frame.margin_right = right;
        return true;
    }

    fn setTBMargin(self: *TparParser, frame: *types.FrameObject, set_initial: bool) bool {
        var top = if (set_initial) self.editor.initial_margin_top else frame.margin_top;
        var bottom = if (set_initial) self.editor.initial_margin_bottom else frame.margin_bottom;
        if (!self.getMargins(frame, 0, frame.scr_height, &top, &bottom, false)) {
            return false;
        }
        if (top + bottom >= frame.scr_height) {
            emitFrameMessage(self.editor, margin_out_of_range_message);
            return false;
        }
        if (set_initial) {
            self.editor.initial_margin_top = top;
            self.editor.initial_margin_bottom = bottom;
        }
        frame.margin_top = top;
        frame.margin_bottom = bottom;
        return true;
    }

    fn setTabs(self: *TparParser, frame: *types.FrameObject, set_initial: bool) !bool {
        const ch = self.nextChar();
        switch (ch) {
            'D' => {
                if (set_initial) {
                    self.editor.initial_tab_stops = self.editor.default_tab_stops;
                }
                frame.tab_stops = self.editor.default_tab_stops;
            },
            'T' => {
                if (frame.dot.?.line.used > 0) {
                    const ts = frame.dot.?.line.str.?.get(1) != ' ';
                    if (set_initial) self.editor.initial_tab_stops[1] = ts;
                    frame.tab_stops[1] = ts;
                }
                var i: isize = 2;
                while (i <= frame.dot.?.line.used) : (i += 1) {
                    const chi = frame.dot.?.line.str.?.get(i);
                    const chim1 = frame.dot.?.line.str.?.get(i - 1);
                    const value = (chi != ' ') and (chim1 == ' ');
                    if (set_initial) self.editor.initial_tab_stops[@intCast(i)] = value;
                    frame.tab_stops[@intCast(i)] = value;
                }
                i = frame.dot.?.line.used + 1;
                while (i <= types.max_str_len) : (i += 1) {
                    if (set_initial) self.editor.initial_tab_stops[@intCast(i)] = false;
                    frame.tab_stops[@intCast(i)] = false;
                }
            },
            'I' => {
                const range = try line_ops.linesCreate(self.allocator, 1);
                const first_line = range.first;
                try line_ops.lineChangeLength(self.allocator, first_line, types.max_str_len);
                var i: isize = 1;
                if (set_initial) {
                    while (i <= types.max_str_len) : (i += 1) {
                        if (self.editor.initial_tab_stops[@intCast(i)]) {
                            first_line.str.?.set(i, 'T');
                        }
                    }
                    first_line.str.?.set(self.editor.initial_margin_left, 'L');
                    first_line.str.?.set(self.editor.initial_margin_right, 'R');
                } else {
                    while (i <= types.max_str_len) : (i += 1) {
                        if (frame.tab_stops[@intCast(i)]) {
                            first_line.str.?.set(i, 'T');
                        }
                    }
                    first_line.str.?.set(frame.margin_left, 'L');
                    first_line.str.?.set(frame.margin_right, 'R');
                }
                first_line.used = first_line.str.?.trimmedLen(' ', types.max_str_len);
                try line_ops.linesInject(self.allocator, first_line, range.last, frame.dot.?.line);
                try mark_ops.markCreate(self.allocator, first_line, frame.dot.?.col, &frame.dot);
                frame.text_modified = true;
                try mark_ops.markCreate(self.allocator, first_line, frame.dot.?.col, &frame.marks[types.mark_modified]);
            },
            'R' => {
                var i: isize = 1;
                var legal = true;
                const MarginState = enum { none, left, right };
                var last_margin: MarginState = .none;
                while (i <= frame.dot.?.line.used and legal) : (i += 1) {
                    const chi = chars.chToUpper(frame.dot.?.line.str.?.get(i));
                    legal = chi == 'T' or chi == 'L' or chi == 'R' or chi == ' ';
                    switch (chi) {
                        'L' => {
                            legal = legal and last_margin == .none;
                            last_margin = .left;
                        },
                        'R' => {
                            legal = legal and last_margin == .left;
                            last_margin = .right;
                        },
                        else => {},
                    }
                }
                legal = legal and last_margin == .right;
                if (!legal) {
                    emitFrameMessage(self.editor, invalid_ruler_message);
                    return false;
                }

                i = 1;
                while (i <= frame.dot.?.line.used) : (i += 1) {
                    const chi = chars.chToUpper(frame.dot.?.line.str.?.get(i));
                    const value = chi != ' ';
                    if (set_initial) {
                        self.editor.initial_tab_stops[@intCast(i)] = value;
                    }
                    frame.tab_stops[@intCast(i)] = value;
                    switch (chi) {
                        'L' => {
                            if (set_initial) self.editor.initial_margin_left = i;
                            frame.margin_left = i;
                        },
                        'R' => {
                            if (set_initial) self.editor.initial_margin_right = i;
                            frame.margin_right = i;
                        },
                        else => {},
                    }
                }
                var j = frame.dot.?.line.used + 1;
                while (j <= types.max_str_len) : (j += 1) {
                    if (set_initial) self.editor.initial_tab_stops[@intCast(j)] = false;
                    frame.tab_stops[@intCast(j)] = false;
                }

                const first_line = frame.dot.?.line;
                const dot_col = frame.dot.?.col;
                try mark_ops.marksSqueeze(self.allocator, first_line, 1, first_line.f_link.?, 1);
                line_ops.linesExtract(first_line, first_line);
                frame.dot.?.col = dot_col;
            },
            'S' => {
                if (frame.dot.?.col == types.max_str_len_p1) {
                    emitFrameMessage(self.editor, out_of_range_tab_value_message);
                    return false;
                }
                if (set_initial) self.editor.initial_tab_stops[@intCast(frame.dot.?.col)] = true;
                frame.tab_stops[@intCast(frame.dot.?.col)] = true;
            },
            'C' => {
                if (frame.dot.?.col == types.max_str_len_p1) {
                    emitFrameMessage(self.editor, out_of_range_tab_value_message);
                    return false;
                }
                if (set_initial) self.editor.initial_tab_stops[@intCast(frame.dot.?.col)] = false;
                frame.tab_stops[@intCast(frame.dot.?.col)] = false;
            },
            'W' => {
                const width = self.toInt() orelse return false;
                if (width <= 1) {
                    return false;
                }
                var tabs: types.TabArray = [_]bool{false} ** (types.max_str_len_p1 + 1);
                tabs[0] = true;
                tabs[types.max_str_len_p1] = true;
                var i: isize = 1;
                while (i <= types.max_str_len) : (i += 1) {
                    if (@mod(i, width) == 1) {
                        tabs[@intCast(i)] = true;
                    }
                }
                if (set_initial) self.editor.initial_tab_stops = tabs;
                frame.tab_stops = tabs;
            },
            '(' => {
                var tabs: types.TabArray = [_]bool{false} ** (types.max_str_len_p1 + 1);
                tabs[0] = true;
                tabs[types.max_str_len_p1] = true;
                while (true) {
                    const n = self.toInt() orelse {
                        emitFrameMessage(self.editor, bad_format_in_tab_table_message);
                        return false;
                    };
                    if (n < 1 or n > types.max_str_len) {
                        emitFrameMessage(self.editor, out_of_range_tab_value_message);
                        return false;
                    }
                    tabs[@intCast(n)] = true;
                    const delim = self.nextChar();
                    if (delim != ',' and delim != ')') {
                        emitFrameMessage(self.editor, bad_format_in_tab_table_message);
                        return false;
                    }
                    if (delim == ')') {
                        break;
                    }
                }
                if (set_initial) self.editor.initial_tab_stops = tabs;
                frame.tab_stops = tabs;
            },
            else => {
                emitFrameMessage(self.editor, invalid_t_option_message);
                return false;
            },
        }
        return true;
    }
};

fn setMemory(editor: *state.Editor, frame: *types.FrameObject, size: isize, set_initial: bool) bool {
    var sz = size;
    if (sz >= types.max_space) {
        sz = types.max_space;
    }
    if (set_initial) {
        editor.file_data.space = sz;
    }

    const used_storage = frame.space_limit - frame.space_left;
    const min_size = @min(used_storage + 800, frame.space_limit);
    if (sz < min_size) {
        sz = min_size;
    }
    frame.space_limit = sz;
    frame.space_left = sz - used_storage;
    return true;
}

pub fn frameSetHeight(editor: *state.Editor, frame: *types.FrameObject, height: isize, set_initial: bool) bool {
    if (height >= 1 and height <= editor.terminal_info.height) {
        if (set_initial) {
            editor.initial_scr_height = height;
        }
        frame.scr_height = height;
        const band = @divTrunc(height, 6);
        if (set_initial) {
            editor.initial_margin_top = band;
            editor.initial_margin_bottom = band;
        }
        frame.margin_top = band;
        frame.margin_bottom = band;
        return true;
    }
    emitFrameMessage(editor, invalid_screen_height_message);
    return false;
}

fn setWidth(editor: *state.Editor, frame: *types.FrameObject, width: isize, set_initial: bool) bool {
    if (width >= 10 and width <= editor.terminal_info.width) {
        if (set_initial) {
            editor.initial_scr_width = width;
        }
        frame.scr_width = width;
        return true;
    }
    emitFrameMessage(editor, screen_width_invalid_message);
    return false;
}

fn setOpt(frame: *types.FrameObject, ch: u8, set_on: bool, options: *types.FrameOptions) bool {
    _ = frame;
    switch (ch) {
        'S' => return true,
        'I' => options.auto_indent = set_on,
        'W' => options.auto_wrap = set_on,
        'N' => options.new_line = set_on,
        else => return false,
    }
    return true;
}

fn keyboardModeName(mode: types.ModeType) []const u8 {
    return switch (mode) {
        .mode_overtype => "Overtype Mode",
        .mode_insert => "Insert Mode",
        .mode_command => "Command Mode",
    };
}

fn appendDisplayOption(
    allocator: std.mem.Allocator,
    buffer: *std.ArrayList(u8),
    ch: u8,
    first: *bool,
) !void {
    if (first.*) {
        try buffer.append(allocator, '(');
    } else {
        try buffer.append(allocator, ',');
    }
    try buffer.append(allocator, ch);
    first.* = false;
}

fn renderOptionsSummary(allocator: std.mem.Allocator, options: types.FrameOptions) ![]const u8 {
    var buffer: std.ArrayList(u8) = .empty;
    try buffer.append(allocator, ' ');
    var count: usize = 1;
    var first = true;
    if (options.auto_indent) {
        try appendDisplayOption(allocator, &buffer, 'I', &first);
        count += 2;
    }
    if (options.auto_wrap) {
        try appendDisplayOption(allocator, &buffer, 'W', &first);
        count += 2;
    }
    if (options.new_line) {
        try appendDisplayOption(allocator, &buffer, 'N', &first);
        count += 2;
    }
    if (first) {
        try buffer.appendSlice(allocator, "  None    ");
        count += "  None    ".len;
    } else {
        try buffer.append(allocator, ')');
        count += 1;
    }
    if (count < 14) {
        try buffer.appendNTimes(allocator, ' ', 14 - count);
    }
    return buffer.toOwnedSlice(allocator);
}

fn renderMarginsSummary(allocator: std.mem.Allocator, first: isize, second: isize) ![]const u8 {
    const text = try std.fmt.allocPrint(allocator, " ({d},{d})", .{ first, second });
    return padRight(allocator, text, 14);
}

fn padRight(allocator: std.mem.Allocator, text_in: []const u8, width: usize) ![]const u8 {
    if (text_in.len >= width) {
        return allocator.dupe(u8, text_in);
    }
    const out = try allocator.alloc(u8, width);
    @memcpy(out[0..text_in.len], text_in);
    @memset(out[text_in.len..], ' ');
    return out;
}

fn renderCommandIntroducerSummary(editor: *const state.Editor, allocator: std.mem.Allocator) ![]const u8 {
    if (user_ops.userKeyCodeToName(editor, editor.command_introducer)) |name| {
        return allocator.dupe(u8, name);
    }
    if (editor.command_introducer >= 0 and editor.command_introducer <= std.math.maxInt(u8)) {
        return std.fmt.allocPrint(allocator, "{c}", .{@as(u8, @intCast(editor.command_introducer))});
    }
    return std.fmt.allocPrint(allocator, "{d}", .{editor.command_introducer});
}

fn renderInt(allocator: std.mem.Allocator, value: isize, width: usize) ![]const u8 {
    const text = if (value < 0)
        try std.fmt.allocPrint(allocator, "{d}", .{value})
    else
        try std.fmt.allocPrint(allocator, "{d}", .{@as(usize, @intCast(value))});

    if (text.len >= width) {
        return text;
    }

    const out = try allocator.alloc(u8, width);
    const padding = width - text.len;
    @memset(out[0..padding], ' ');
    @memcpy(out[padding..], text);
    return out;
}

fn renderName(allocator: std.mem.Allocator, name: []const u8, width: usize) ![]const u8 {
    if (name.len >= width) {
        return allocator.dupe(u8, name[0..width]);
    }
    const out = try allocator.alloc(u8, width);
    @memcpy(out[0..name.len], name);
    @memset(out[name.len..], ' ');
    return out;
}

fn spaces(allocator: std.mem.Allocator, count: usize) ![]const u8 {
    const out = try allocator.alloc(u8, count);
    @memset(out, ' ');
    return out;
}

fn joinWithIndent(allocator: std.mem.Allocator, prefix: []const u8, indent: usize, suffix: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ prefix, try spaces(allocator, indent), suffix });
}

fn renderTabSettingsLine(allocator: std.mem.Allocator, frame: *const types.FrameObject) ![]const u8 {
    const width: usize = @intCast(@max(frame.scr_width, 1));
    const out = try allocator.alloc(u8, width);
    @memset(out, ' ');
    var idx: usize = 1;
    while (idx <= width) : (idx += 1) {
        if (@as(isize, @intCast(idx)) == frame.margin_left) {
            out[idx - 1] = 'L';
        } else if (@as(isize, @intCast(idx)) == frame.margin_right) {
            out[idx - 1] = 'R';
        } else if (frame.tab_stops[idx]) {
            out[idx - 1] = 'T';
        }
    }
    return out;
}

fn buildInteractiveParameterLines(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !std.ArrayList([]const u8) {
    var lines: std.ArrayList([]const u8) = .empty;
    const frame_name = if (frame.span != null) frame.span.?.name else "";
    const padded_frame_name = try renderName(allocator, frame_name, types.name_len);
    const version_underline = try allocator.alloc(u8, 7 + types.ludwig_reader.len);
    @memset(version_underline, '=');
    const current_options = try renderOptionsSummary(allocator, frame.options);
    const default_options = try renderOptionsSummary(allocator, editor.initial_options);
    const current_h_margins = try renderMarginsSummary(allocator, frame.margin_left, frame.margin_right);
    const default_h_margins = try renderMarginsSummary(allocator, editor.initial_margin_left, editor.initial_margin_right);
    const current_v_margins = try renderMarginsSummary(allocator, frame.margin_top, frame.margin_bottom);
    const default_v_margins = try renderMarginsSummary(allocator, editor.initial_margin_top, editor.initial_margin_bottom);
    const introducer = try renderCommandIntroducerSummary(editor, allocator);
    const unused_memory = try renderInt(allocator, frame.space_left, 9);
    const line_count = try renderInt(allocator, line_ops.lineToNumber(frame.last_group.?.last_line.?) - 1, 9);
    const input_count = try renderInt(allocator, frame.input_count, 9);
    const current_line = try renderInt(allocator, line_ops.lineToNumber(frame.dot.?.line), 9);
    const current_space_limit = try renderInt(allocator, frame.space_limit, 9);
    const default_space_limit = try renderInt(allocator, editor.file_data.space, 9);
    const current_scr_height = try renderInt(allocator, frame.scr_height, 9);
    const default_scr_height = try renderInt(allocator, editor.initial_scr_height, 9);
    const current_scr_width = try renderInt(allocator, frame.scr_width, 9);
    const default_scr_width = try renderInt(allocator, editor.initial_scr_width, 9);

    try lines.append(allocator, try joinWithIndent(
        allocator,
        try std.fmt.allocPrint(allocator, " Ludwig {s}", .{types.ludwig_reader}),
        5,
        try std.fmt.allocPrint(allocator, "Parameters      Frame: {s}", .{padded_frame_name}),
    ));
    try lines.append(allocator, try joinWithIndent(
        allocator,
        try std.fmt.allocPrint(allocator, " {s}", .{version_underline}),
        5,
        "==========      =====",
    ));
    try lines.append(allocator, "");
    try lines.append(allocator, try std.fmt.allocPrint(allocator, "   Unused  memory available in frame    ={s}", .{unused_memory}));
    try lines.append(allocator, try std.fmt.allocPrint(
        allocator,
        "   The number of lines in this frame    ={s}",
        .{line_count},
    ));
    try lines.append(allocator, try std.fmt.allocPrint(allocator, "   Lines read from input file so far    ={s}", .{input_count}));
    try lines.append(allocator, try std.fmt.allocPrint(
        allocator,
        "   Current Line number in this frame    ={s}",
        .{current_line},
    ));
    try lines.append(allocator, "");
    try lines.append(allocator, try joinWithIndent(
        allocator,
        try std.fmt.allocPrint(allocator, "{s}Parameters", .{try spaces(allocator, 9)}),
        41,
        "Defaults",
    ));
    try lines.append(allocator, try joinWithIndent(
        allocator,
        try std.fmt.allocPrint(allocator, "{s}----------", .{try spaces(allocator, 9)}),
        41,
        "--------",
    ));
    try lines.append(allocator, try std.fmt.allocPrint(
        allocator,
        "   Keyboard Mode                      K = {s}",
        .{keyboardModeName(editor.edit_mode)},
    ));
    if (editor.ludwig_mode == .ludwig_screen) {
        try lines.append(allocator, try std.fmt.allocPrint(
            allocator,
            "   Command introducer                 C = {s}",
            .{introducer},
        ));
    }
    try lines.append(allocator, try joinWithIndent(
        allocator,
        try std.fmt.allocPrint(allocator, "   Maximum memory available in frame  S ={s}", .{current_space_limit}),
        5,
        try std.fmt.allocPrint(allocator, "  --  {s}", .{default_space_limit}),
    ));
    try lines.append(allocator, try joinWithIndent(
        allocator,
        try std.fmt.allocPrint(allocator, "   Screen height  (lines displayed)   H ={s}", .{current_scr_height}),
        5,
        try std.fmt.allocPrint(allocator, "  --  {s}", .{default_scr_height}),
    ));
    try lines.append(allocator, try joinWithIndent(
        allocator,
        try std.fmt.allocPrint(allocator, "   Screen width   (characters)        W ={s}", .{current_scr_width}),
        5,
        try std.fmt.allocPrint(allocator, "  --  {s}", .{default_scr_width}),
    ));
    try lines.append(allocator, try std.fmt.allocPrint(
        allocator,
        "   Editing options                    O ={s}  --  {s}",
        .{ current_options, default_options },
    ));
    try lines.append(allocator, try std.fmt.allocPrint(
        allocator,
        "   Horizontal margins                 M ={s}  --  {s}",
        .{ current_h_margins, default_h_margins },
    ));
    try lines.append(allocator, try std.fmt.allocPrint(
        allocator,
        "   Vertical margins                   V ={s}  --  {s}",
        .{ current_v_margins, default_v_margins },
    ));
    try lines.append(allocator, "   Tab settings                       T =");
    try lines.append(allocator, try renderTabSettingsLine(allocator, frame));
    return lines;
}

fn showInteractiveParameters(
    editor: *state.Editor,
    frame: *types.FrameObject,
) !bool {
    while (true) {
        const done = blk: {
            var loop_arena = std.heap.ArenaAllocator.init(editor.base_allocator);
            defer loop_arena.deinit();
            const temp = loop_arena.allocator();

            const lines = try buildInteractiveParameterLines(editor, temp, frame);
            interactive_io.showTemporaryLines(lines.items);

            const response = try interactive_io.readPromptLine(temp, new_values_prompt);
            for (response) |*ch| {
                ch.* = std.ascii.toUpper(ch.*);
            }
            if (response.len == 0) {
                break :blk true;
            }

            var request = types.TParObject{
                .str = try str_object.newStrObjectFrom(temp, response),
                .len = @intCast(response.len),
            };
            if (!try setParam(editor, frame, &request)) {
                interactive_io.beep();
            }
            break :blk false;
        };
        if (done) {
            return true;
        }
    }
}

fn setParam(
    editor: *state.Editor,
    frame: *types.FrameObject,
    request: *types.TParObject,
) !bool {
    var parser = TparParser{
        .editor = editor,
        .allocator = editor.allocator(),
        .request = request,
    };
    var ch = parser.nextChar();
    while (ch != 0) {
        var set_initial = false;
        if (ch == '$') {
            set_initial = true;
            ch = parser.nextChar();
        }
        if (parser.nextChar() != '=') {
            emitFrameMessage(editor, syntax_error_in_options_message);
            return false;
        }

        const ok = switch (ch) {
            'O' => parser.setOptions(frame, set_initial),
            'S' => blk: {
                const mem = parser.toInt() orelse break :blk false;
                break :blk setMemory(editor, frame, mem, set_initial);
            },
            'H' => blk: {
                const height = parser.toInt() orelse break :blk false;
                break :blk frameSetHeight(editor, frame, height, set_initial);
            },
            'W' => blk: {
                const width = parser.toInt() orelse break :blk false;
                break :blk setWidth(editor, frame, width, set_initial);
            },
            'C' => parser.setCmdIntr(),
            'T' => try parser.setTabs(frame, set_initial),
            'M' => parser.setLRMargin(frame, set_initial),
            'V' => parser.setTBMargin(frame, set_initial),
            'K' => parser.setMode(),
            else => blk: {
                emitFrameMessage(editor, invalid_parameter_code_message);
                break :blk false;
            },
        };
        if (!ok) {
            return false;
        }

        ch = parser.nextChar();
        if (ch == ',' or ch == 0) {
            ch = parser.nextChar();
        } else {
            emitFrameMessage(editor, syntax_error_in_param_cmd_message);
            return false;
        }
    }
    return true;
}

pub fn frameParameter(
    editor: *state.Editor,
    frame: *types.FrameObject,
    tpar: ?*types.TParObject,
) !bool {
    var request: types.TParObject = .{};
    if (!try tpar_ops.tparGet1(editor, frame, tpar, .cmd_frame_parameters, &request)) {
        return false;
    }
    if (request.len > 0) {
        return setParam(editor, frame, &request);
    }
    if (editor.ludwig_mode == .ludwig_screen) {
        return showInteractiveParameters(editor, frame);
    }
    return false;
}

test "frame edit creates and reuses named frames" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();

    const origin_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    const origin = origin_fixture.frame;

    const created = (try frameEdit(&editor, origin, "WORK")).?;
    try std.testing.expect(created != origin);
    try std.testing.expect(created.span != null);
    try std.testing.expectEqualStrings("WORK", created.span.?.name);
    try std.testing.expect(created.return_frame == origin);
    try std.testing.expect(created.span.?.frame == created);
    try std.testing.expect(created.first_group == created.last_group);
    try std.testing.expect(created.dot != null);

    const reused = (try frameEdit(&editor, origin, "WORK")).?;
    try std.testing.expect(reused == created);
    try std.testing.expect(reused.return_frame == origin);
}

test "frame kill removes frame span and clears return links" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();

    const origin_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    const origin = origin_fixture.frame;
    const target = (try frameEdit(&editor, origin, "WORK")).?;
    const follower = (try frameEdit(&editor, target, "FOLLOW")).?;
    try std.testing.expect(follower.return_frame == target);

    const span_mark_one = target.span.?.mark_one.?;
    const span_mark_two = target.span.?.mark_two.?;
    try std.testing.expect(try span_ops.spanCreate(&editor, "INNER", span_mark_one, span_mark_two));

    try std.testing.expect(try frameKill(&editor, origin, "WORK"));
    try std.testing.expect(follower.return_frame == null);
    try std.testing.expect((try frameEdit(&editor, origin, "WORK")).? != target);
}

test "frame kill rejects current and special frames" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();

    const origin_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    const origin = origin_fixture.frame;
    const current_named = (try frameEdit(&editor, origin, "CURRENT")).?;
    try std.testing.expect(!try frameKill(&editor, current_named, "CURRENT"));

    const special = (try frameEdit(&editor, origin, "SPECIAL")).?;
    special.options.special_frame = true;
    try std.testing.expect(!try frameKill(&editor, origin, "SPECIAL"));
}

test "frame edit initializes empty frame with end-of-file sentinel" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();

    const frame = (try frameEdit(&editor, null, "WORK")).?;
    try std.testing.expectEqualStrings("<End of File>   WORK", line_ops.getDisplayLineContent(frame.last_group.?.last_line.?));
    try std.testing.expectEqualStrings("", line_ops.getLineContent(frame.last_group.?.last_line.?));
}

test "frame parameter updates batch-safe state values" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();
    editor.terminal_info = .{ .width = 160, .height = 48 };

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"alpha beta"});
    const frame = fixture.frame;

    const request = "K=O,O=(I,-N),S=1200,H=24,W=100,M=(5,80),V=(2,3),T=(4,8,12),$S=2200,$W=120";
    var tpar = types.TParObject{
        .str = try @import("str_object.zig").newStrObjectFrom(allocator, request),
        .len = request.len,
    };
    try std.testing.expect(try frameParameter(&editor, frame, &tpar));
    try std.testing.expectEqual(types.ModeType.mode_overtype, editor.edit_mode);
    try std.testing.expect(frame.options.auto_indent);
    try std.testing.expect(!frame.options.new_line);
    try std.testing.expectEqual(@as(isize, 2200), frame.space_limit);
    try std.testing.expectEqual(@as(isize, 24), frame.scr_height);
    try std.testing.expectEqual(@as(isize, 120), frame.scr_width);
    try std.testing.expectEqual(@as(isize, 5), frame.margin_left);
    try std.testing.expectEqual(@as(isize, 80), frame.margin_right);
    try std.testing.expectEqual(@as(isize, 2), frame.margin_top);
    try std.testing.expectEqual(@as(isize, 3), frame.margin_bottom);
    try std.testing.expectEqual(@as(isize, '\\'), editor.command_introducer);
    try std.testing.expect(frame.tab_stops[4]);
    try std.testing.expect(frame.tab_stops[8]);
    try std.testing.expect(frame.tab_stops[12]);
    try std.testing.expectEqual(@as(isize, 2200), editor.file_data.space);
    try std.testing.expectEqual(@as(isize, 120), editor.initial_scr_width);
}

test "frame parameter accepts named command introducers in screen mode" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();
    editor.ludwig_mode = .ludwig_screen;
    try user_ops.userKeyInitialize(&editor, allocator);
    const function_key = user_ops.userKeyNameToCode(&editor, "FUNCTION-1").?;

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"alpha"});
    var tpar = types.TParObject{
        .str = try @import("str_object.zig").newStrObjectFrom(allocator, "C=FUNCTION-1"),
        .len = "C=FUNCTION-1".len,
    };

    try std.testing.expect(try frameParameter(&editor, fixture.frame, &tpar));
    try std.testing.expectEqual(function_key, editor.command_introducer);
}

test "frame parameter reports unrecognized named introducers" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();
    editor.ludwig_mode = .ludwig_screen;
    try user_ops.userKeyInitialize(&editor, allocator);

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"alpha"});
    var tpar = types.TParObject{
        .str = try @import("str_object.zig").newStrObjectFrom(allocator, "C=BOGUS"),
        .len = "C=BOGUS".len,
    };

    try std.testing.expect(!(try frameParameter(&editor, fixture.frame, &tpar)));
    try std.testing.expectEqualStrings(unrecognized_key_name_message, interactive_io.takeStatusMessage().?);
}

test "frame parameter queues validation messages in screen mode" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();
    editor.ludwig_mode = .ludwig_screen;
    editor.terminal_info = .{ .width = 120, .height = 24 };
    try user_ops.userKeyInitialize(&editor, allocator);

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"alpha"});

    var bad_mode = types.TParObject{
        .str = try @import("str_object.zig").newStrObjectFrom(allocator, "K=X"),
        .len = "K=X".len,
    };
    try std.testing.expect(!(try frameParameter(&editor, fixture.frame, &bad_mode)));
    try std.testing.expectEqualStrings(mode_error_message, interactive_io.takeStatusMessage().?);

    var bad_option = types.TParObject{
        .str = try @import("str_object.zig").newStrObjectFrom(allocator, "O=Z"),
        .len = "O=Z".len,
    };
    try std.testing.expect(!(try frameParameter(&editor, fixture.frame, &bad_option)));
    try std.testing.expectEqualStrings(unknown_option_message, interactive_io.takeStatusMessage().?);

    var bad_height = types.TParObject{
        .str = try @import("str_object.zig").newStrObjectFrom(allocator, "H=999"),
        .len = "H=999".len,
    };
    try std.testing.expect(!(try frameParameter(&editor, fixture.frame, &bad_height)));
    try std.testing.expectEqualStrings(invalid_screen_height_message, interactive_io.takeStatusMessage().?);
}

test "frame parameter tab ruler operations update text and tab stops" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"alpha beta"});
    const frame = fixture.frame;
    try mark_ops.markCreate(allocator, fixture.content_lines[0], 3, &frame.dot);

    var insert = types.TParObject{
        .str = try @import("str_object.zig").newStrObjectFrom(allocator, "T=I"),
        .len = 3,
    };
    try std.testing.expect(try frameParameter(&editor, frame, &insert));
    try std.testing.expect(frame.text_modified);
    const ruler_line = frame.first_group.?.first_line.?;
    try std.testing.expect(ruler_line != fixture.content_lines[0]);
    try std.testing.expect(ruler_line.str.?.get(frame.margin_left) == 'L');
    try std.testing.expect(ruler_line.str.?.get(frame.margin_right) == 'R');

    const current = frame.dot.?.line;
    try line_ops.lineChangeLength(allocator, current, 12);
    try line_ops.setLineContent(current, "L  T   T R");
    current.scr_row_num = 1;
    frame.scr_height = 24;

    var apply = types.TParObject{
        .str = try @import("str_object.zig").newStrObjectFrom(allocator, "T=R"),
        .len = 3,
    };
    try std.testing.expect(try frameParameter(&editor, frame, &apply));
    try std.testing.expect(frame.tab_stops[4]);
    try std.testing.expect(frame.tab_stops[8]);
    try std.testing.expectEqual(@as(isize, 1), frame.margin_left);
    try std.testing.expectEqual(@as(isize, 10), frame.margin_right);
}

test "interactive parameter display lines show current settings summary" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var env = try std.testing.environ.createMap(allocator);
    defer env.deinit();
    var editor = try state.Editor.init(std.testing.io, allocator, env);
    defer editor.deinit();
    editor.ludwig_mode = .ludwig_screen;
    editor.terminal_info = .{ .width = 120, .height = 24 };
    try user_ops.userKeyInitialize(&editor, allocator);

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{ "alpha", "beta" });
    const frame = fixture.frame;
    frame.scr_width = 20;
    frame.scr_height = 12;

    const lines = try buildInteractiveParameterLines(&editor, arena.allocator(), frame);

    var saw_parameters_header = false;
    var saw_frame_heading = false;
    var saw_keyboard_mode = false;
    var saw_command_introducer = false;
    var saw_tab_settings = false;
    var saw_unused_memory = false;
    var saw_max_memory = false;
    var saw_screen_height = false;
    var saw_screen_width = false;
    for (lines.items) |line| {
        saw_parameters_header = saw_parameters_header or std.mem.eql(u8, line, "         Parameters                                         Defaults");
        saw_frame_heading = saw_frame_heading or std.mem.indexOf(u8, line, "Parameters      Frame:") != null;
        saw_keyboard_mode = saw_keyboard_mode or std.mem.indexOf(u8, line, "Keyboard Mode") != null;
        saw_command_introducer = saw_command_introducer or std.mem.indexOf(u8, line, "Command introducer") != null;
        saw_tab_settings = saw_tab_settings or std.mem.indexOf(u8, line, "Tab settings") != null;
        if (std.mem.indexOf(u8, line, "Unused  memory available in frame") != null) {
            saw_unused_memory = true;
            try std.testing.expect(std.mem.indexOfScalar(u8, line, '+') == null);
        }
        if (std.mem.indexOf(u8, line, "Maximum memory available in frame") != null) {
            saw_max_memory = true;
            try std.testing.expect(std.mem.indexOfScalar(u8, line, '+') == null);
        }
        if (std.mem.indexOf(u8, line, "Screen height  (lines displayed)") != null) {
            saw_screen_height = true;
            try std.testing.expect(std.mem.indexOfScalar(u8, line, '+') == null);
        }
        if (std.mem.indexOf(u8, line, "Screen width   (characters)") != null) {
            saw_screen_width = true;
            try std.testing.expect(std.mem.indexOfScalar(u8, line, '+') == null);
        }
    }

    try std.testing.expect(saw_parameters_header);
    try std.testing.expect(saw_frame_heading);
    try std.testing.expect(saw_keyboard_mode);
    try std.testing.expect(saw_command_introducer);
    try std.testing.expect(saw_tab_settings);
    try std.testing.expect(saw_unused_memory);
    try std.testing.expect(saw_max_memory);
    try std.testing.expect(saw_screen_height);
    try std.testing.expect(saw_screen_width);
}
