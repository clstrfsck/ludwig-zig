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
    if (editor.LudwigMode == .LudwigScreen) {
        interactive_io.queueStatusMessage(message);
    }
}

pub fn FrameEdit(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    return_frame: ?*types.FrameObject,
    frame_name: []const u8,
) !?*types.FrameObject {
    const resolved_name = if (frame_name.len == 0) types.DefaultFrameName else frame_name;

    var span_ptr: ?*types.SpanObject = null;
    var span_prev: ?*types.SpanObject = null;
    if (try span_ops.SpanFind(editor, allocator, resolved_name, &span_ptr, &span_prev)) {
        if (span_ptr.?.Frame) |frame| {
            if (return_frame != null and frame != return_frame.?) {
                frame.ReturnFrame = return_frame;
            }
            return frame;
        }
        return null;
    }

    const frame = try allocator.create(types.FrameObject);
    frame.* = .{
        .Marks = editor.InitialMarks,
        .ScrHeight = editor.InitialScrHeight,
        .ScrWidth = editor.InitialScrWidth,
        .ScrOffset = editor.InitialScrOffset,
        .ScrDotLine = 1,
        .ReturnFrame = return_frame,
        .SpaceLimit = editor.FileData.Space,
        .SpaceLeft = editor.FileData.Space,
        .MarginLeft = editor.InitialMarginLeft,
        .MarginRight = editor.InitialMarginRight,
        .MarginTop = editor.InitialMarginTop,
        .MarginBottom = editor.InitialMarginBottom,
        .TabStops = editor.InitialTabStops,
        .Options = editor.InitialOptions,
    };

    const group = try line_ops.LineEOPCreate(allocator, frame);
    frame.FirstGroup = group;
    frame.LastGroup = group;
    try line_ops.setSentinelDisplayContent(allocator, group.FirstLine.?, end_of_file_prefix, resolved_name);

    const span = try allocator.create(types.SpanObject);
    span.* = .{
        .BLink = span_prev,
        .FLink = span_ptr,
        .Frame = frame,
        .Name = try allocator.dupe(u8, resolved_name),
    };
    if (span_prev) |prev| {
        prev.FLink = span;
    } else {
        editor.FirstSpan = span;
    }
    if (span_ptr) |next| {
        next.BLink = span;
    }

    try mark_ops.MarkCreate(allocator, group.FirstLine.?, 1, &span.MarkOne);
    try mark_ops.MarkCreate(allocator, group.LastLine.?, 1, &span.MarkTwo);
    frame.Span = span;
    try mark_ops.MarkCreate(allocator, group.FirstLine.?, editor.InitialMarginLeft, &frame.Dot);
    return frame;
}

pub fn FrameKill(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    current_frame: *types.FrameObject,
    frame_name: []const u8,
) !bool {
    var span_ptr: ?*types.SpanObject = null;
    var span_prev: ?*types.SpanObject = null;
    if (!try span_ops.SpanFind(editor, allocator, frame_name, &span_ptr, &span_prev)) {
        return false;
    }
    if (span_ptr.?.Frame == null) {
        return false;
    }

    const target_frame = span_ptr.?.Frame.?;
    if (target_frame == current_frame or target_frame == editor.Screen.Frame or types.frameOptionsHas(target_frame.Options, .OptSpecialFrame)) {
        return false;
    }
    if (target_frame.InputFile != 0 or target_frame.OutputFile != 0) {
        return false;
    }

    var iter = editor.FirstSpan;
    while (iter) |span| {
        const next = span.FLink;
        if (span.Frame) |span_frame| {
            if (span_frame.ReturnFrame == target_frame) {
                span_frame.ReturnFrame = null;
            }
        } else if (span.MarkOne != null and span.MarkOne.?.Line.Group.?.Frame == target_frame) {
            var slot = iter;
            if (!span_ops.SpanDestroy(editor, allocator, &slot)) {
                return false;
            }
        }
        iter = next;
    }

    target_frame.Span.?.Frame = null;
    var frame_span = target_frame.Span;
    if (!span_ops.SpanDestroy(editor, allocator, &frame_span)) {
        return false;
    }
    target_frame.Span = null;

    mark_ops.MarkDestroy(allocator, &target_frame.Dot);
    var mark_index: usize = 0;
    while (mark_index < target_frame.Marks.len) : (mark_index += 1) {
        mark_ops.MarkDestroy(allocator, &target_frame.Marks[mark_index]);
    }

    const last_content = target_frame.LastGroup.?.LastLine.?.BLink;
    if (last_content != null) {
        line_ops.LinesExtract(target_frame.FirstGroup.?.FirstLine.?, last_content.?);
    }

    target_frame.FirstGroup = null;
    target_frame.LastGroup = null;

    dfa.PatternDFATableKill(allocator, &target_frame.EqsPatternPtr);
    dfa.PatternDFATableKill(allocator, &target_frame.GetPatternPtr);
    dfa.PatternDFATableKill(allocator, &target_frame.RepPatternPtr);
    return true;
}

const TparParser = struct {
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    request: *types.TParObject,
    pos: isize = 1,

    fn nextChar(self: *TparParser) u8 {
        while (self.pos < self.request.Len and self.request.Str.?.Get(self.pos) == ' ') {
            self.pos += 1;
        }
        var ch: u8 = 0;
        if (self.pos > self.request.Len or self.request.Str.?.Get(self.pos) == ' ') {
            ch = 0;
        } else {
            ch = self.request.Str.?.Get(self.pos);
        }
        if (self.pos <= self.request.Len) {
            self.pos += 1;
        }
        return ch;
    }

    fn toInt(self: *TparParser) ?isize {
        return tpar_ops.TparToIntMessage(self.editor, self.request, &self.pos);
    }

    fn setMode(self: *TparParser) bool {
        switch (self.nextChar()) {
            'I' => self.editor.EditMode = .ModeInsert,
            'O' => self.editor.EditMode = .ModeOvertype,
            'C' => self.editor.EditMode = .ModeCommand,
            else => {
                emitFrameMessage(self.editor, mode_error_message);
                return false;
            },
        }
        return true;
    }

    fn setCmdIntr(self: *TparParser) bool {
        if (self.editor.LudwigMode != .LudwigScreen) {
            emitFrameMessage(self.editor, screen_mode_only_message);
            return false;
        }

        while (self.pos <= self.request.Len and self.request.Str.?.Get(self.pos) == ' ') {
            self.pos += 1;
        }
        const start = self.pos;
        while (self.pos <= self.request.Len and self.request.Str.?.Get(self.pos) != ',') {
            self.pos += 1;
        }
        const end = self.pos - 1;
        if (end < start) {
            emitFrameMessage(self.editor, invalid_cmd_introducer_message);
            return false;
        }
        const len: usize = @intCast(end - start + 1);
        const key_name = std.mem.trim(u8, self.request.Str.?.Slice(start, @intCast(len)), " ");
        if (key_name.len == 0) {
            emitFrameMessage(self.editor, invalid_cmd_introducer_message);
            return false;
        }

        if (key_name.len == 1) {
            const ch = key_name[0];
            if (!chars.ChIsPunctuation(ch)) {
                emitFrameMessage(self.editor, invalid_cmd_introducer_message);
                return false;
            }
            self.editor.CommandIntroducer = ch;
            return true;
        }

        const key_code = user_ops.UserKeyNameToCode(self.editor, key_name) orelse {
            emitFrameMessage(self.editor, unrecognized_key_name_message);
            return false;
        };
        if (key_code >= 0 and key_code < types.LookupCount and self.editor.KeyIntroducers.isSet(@intCast(key_code))) {
            emitFrameMessage(self.editor, invalid_cmd_introducer_message);
            return false;
        }

        self.editor.CommandIntroducer = key_code;
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
                if (set_initial and !setOpt(frame, ch, set_on, &self.editor.InitialOptions)) {
                    emitFrameMessage(self.editor, unknown_option_message);
                    return false;
                }
                ok = setOpt(frame, ch, set_on, &frame.Options);
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
            if (set_initial and !setOpt(frame, ch, set_on, &self.editor.InitialOptions)) {
                emitFrameMessage(self.editor, unknown_option_message);
                return false;
            }
            ok = setOpt(frame, ch, set_on, &frame.Options);
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
            lower.* = if (lr) frame.Dot.?.Col else frame.Dot.?.Line.ScrRowNr;
            ch = self.nextChar();
        } else if (!self.getMar(&ch, lo_bnd, hi_bnd, lower)) {
            return false;
        }
        if (ch == ',') {
            ch = self.nextChar();
            if (ch == '.') {
                upper.* = if (lr) frame.Dot.?.Col else frame.ScrHeight - frame.Dot.?.Line.ScrRowNr;
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
        var left = if (set_initial) self.editor.InitialMarginLeft else frame.MarginLeft;
        var right = if (set_initial) self.editor.InitialMarginRight else frame.MarginRight;
        if (!self.getMargins(frame, 1, types.MaxStrLen, &left, &right, true)) {
            return false;
        }
        if (left >= right) {
            emitFrameMessage(self.editor, left_margin_ge_right_message);
            return false;
        }
        if (set_initial) {
            self.editor.InitialMarginLeft = left;
            self.editor.InitialMarginRight = right;
        }
        frame.MarginLeft = left;
        frame.MarginRight = right;
        return true;
    }

    fn setTBMargin(self: *TparParser, frame: *types.FrameObject, set_initial: bool) bool {
        var top = if (set_initial) self.editor.InitialMarginTop else frame.MarginTop;
        var bottom = if (set_initial) self.editor.InitialMarginBottom else frame.MarginBottom;
        if (!self.getMargins(frame, 0, frame.ScrHeight, &top, &bottom, false)) {
            return false;
        }
        if (top + bottom >= frame.ScrHeight) {
            emitFrameMessage(self.editor, margin_out_of_range_message);
            return false;
        }
        if (set_initial) {
            self.editor.InitialMarginTop = top;
            self.editor.InitialMarginBottom = bottom;
        }
        frame.MarginTop = top;
        frame.MarginBottom = bottom;
        return true;
    }

    fn setTabs(self: *TparParser, frame: *types.FrameObject, set_initial: bool) !bool {
        const ch = self.nextChar();
        switch (ch) {
            'D' => {
                if (set_initial) {
                    self.editor.InitialTabStops = self.editor.DefaultTabStops;
                }
                frame.TabStops = self.editor.DefaultTabStops;
            },
            'T' => {
                if (frame.Dot.?.Line.Used > 0) {
                    const ts = frame.Dot.?.Line.Str.?.Get(1) != ' ';
                    if (set_initial) self.editor.InitialTabStops[1] = ts;
                    frame.TabStops[1] = ts;
                }
                var i: isize = 2;
                while (i <= frame.Dot.?.Line.Used) : (i += 1) {
                    const chi = frame.Dot.?.Line.Str.?.Get(i);
                    const chim1 = frame.Dot.?.Line.Str.?.Get(i - 1);
                    const value = (chi != ' ') and (chim1 == ' ');
                    if (set_initial) self.editor.InitialTabStops[@intCast(i)] = value;
                    frame.TabStops[@intCast(i)] = value;
                }
                i = frame.Dot.?.Line.Used + 1;
                while (i <= types.MaxStrLen) : (i += 1) {
                    if (set_initial) self.editor.InitialTabStops[@intCast(i)] = false;
                    frame.TabStops[@intCast(i)] = false;
                }
            },
            'I' => {
                const range = try line_ops.LinesCreate(self.allocator, 1);
                const first_line = range.first;
                try line_ops.LineChangeLength(self.allocator, first_line, types.MaxStrLen);
                var i: isize = 1;
                if (set_initial) {
                    while (i <= types.MaxStrLen) : (i += 1) {
                        if (self.editor.InitialTabStops[@intCast(i)]) {
                            first_line.Str.?.Set(i, 'T');
                        }
                    }
                    first_line.Str.?.Set(self.editor.InitialMarginLeft, 'L');
                    first_line.Str.?.Set(self.editor.InitialMarginRight, 'R');
                } else {
                    while (i <= types.MaxStrLen) : (i += 1) {
                        if (frame.TabStops[@intCast(i)]) {
                            first_line.Str.?.Set(i, 'T');
                        }
                    }
                    first_line.Str.?.Set(frame.MarginLeft, 'L');
                    first_line.Str.?.Set(frame.MarginRight, 'R');
                }
                first_line.Used = first_line.Str.?.TrimmedLen(' ', types.MaxStrLen);
                try line_ops.LinesInject(self.allocator, first_line, range.last, frame.Dot.?.Line);
                try mark_ops.MarkCreate(self.allocator, first_line, frame.Dot.?.Col, &frame.Dot);
                frame.TextModified = true;
                try mark_ops.MarkCreate(self.allocator, first_line, frame.Dot.?.Col, &frame.Marks[types.MarkModified]);
            },
            'R' => {
                var i: isize = 1;
                var legal = true;
                const MarginState = enum { none, left, right };
                var last_margin: MarginState = .none;
                while (i <= frame.Dot.?.Line.Used and legal) : (i += 1) {
                    const chi = chars.ChToUpper(frame.Dot.?.Line.Str.?.Get(i));
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
                while (i <= frame.Dot.?.Line.Used) : (i += 1) {
                    const chi = chars.ChToUpper(frame.Dot.?.Line.Str.?.Get(i));
                    const value = chi != ' ';
                    if (set_initial) {
                        self.editor.InitialTabStops[@intCast(i)] = value;
                    }
                    frame.TabStops[@intCast(i)] = value;
                    switch (chi) {
                        'L' => {
                            if (set_initial) self.editor.InitialMarginLeft = i;
                            frame.MarginLeft = i;
                        },
                        'R' => {
                            if (set_initial) self.editor.InitialMarginRight = i;
                            frame.MarginRight = i;
                        },
                        else => {},
                    }
                }
                var j = frame.Dot.?.Line.Used + 1;
                while (j <= types.MaxStrLen) : (j += 1) {
                    if (set_initial) self.editor.InitialTabStops[@intCast(j)] = false;
                    frame.TabStops[@intCast(j)] = false;
                }

                const first_line = frame.Dot.?.Line;
                const dot_col = frame.Dot.?.Col;
                try mark_ops.MarksSqueeze(self.allocator, first_line, 1, first_line.FLink.?, 1);
                line_ops.LinesExtract(first_line, first_line);
                frame.Dot.?.Col = dot_col;
            },
            'S' => {
                if (frame.Dot.?.Col == types.MaxStrLenP) {
                    emitFrameMessage(self.editor, out_of_range_tab_value_message);
                    return false;
                }
                if (set_initial) self.editor.InitialTabStops[@intCast(frame.Dot.?.Col)] = true;
                frame.TabStops[@intCast(frame.Dot.?.Col)] = true;
            },
            'C' => {
                if (frame.Dot.?.Col == types.MaxStrLenP) {
                    emitFrameMessage(self.editor, out_of_range_tab_value_message);
                    return false;
                }
                if (set_initial) self.editor.InitialTabStops[@intCast(frame.Dot.?.Col)] = false;
                frame.TabStops[@intCast(frame.Dot.?.Col)] = false;
            },
            'W' => {
                const width = self.toInt() orelse return false;
                if (width <= 1) {
                    return false;
                }
                var tabs: types.TabArray = [_]bool{false} ** (types.MaxStrLenP + 1);
                tabs[0] = true;
                tabs[types.MaxStrLenP] = true;
                var i: isize = 1;
                while (i <= types.MaxStrLen) : (i += 1) {
                    if (@mod(i, width) == 1) {
                        tabs[@intCast(i)] = true;
                    }
                }
                if (set_initial) self.editor.InitialTabStops = tabs;
                frame.TabStops = tabs;
            },
            '(' => {
                var tabs: types.TabArray = [_]bool{false} ** (types.MaxStrLenP + 1);
                tabs[0] = true;
                tabs[types.MaxStrLenP] = true;
                while (true) {
                    const n = self.toInt() orelse {
                        emitFrameMessage(self.editor, bad_format_in_tab_table_message);
                        return false;
                    };
                    if (n < 1 or n > types.MaxStrLen) {
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
                if (set_initial) self.editor.InitialTabStops = tabs;
                frame.TabStops = tabs;
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
    if (sz >= types.MaxSpace) {
        sz = types.MaxSpace;
    }
    if (set_initial) {
        editor.FileData.Space = sz;
    }

    const used_storage = frame.SpaceLimit - frame.SpaceLeft;
    const min_size = @min(used_storage + 800, frame.SpaceLimit);
    if (sz < min_size) {
        sz = min_size;
    }
    frame.SpaceLimit = sz;
    frame.SpaceLeft = sz - used_storage;
    return true;
}

pub fn FrameSetHeight(editor: *state.Editor, frame: *types.FrameObject, height: isize, set_initial: bool) bool {
    if (height >= 1 and height <= editor.TerminalInfo.Height) {
        if (set_initial) {
            editor.InitialScrHeight = height;
        }
        frame.ScrHeight = height;
        const band = @divTrunc(height, 6);
        if (set_initial) {
            editor.InitialMarginTop = band;
            editor.InitialMarginBottom = band;
        }
        frame.MarginTop = band;
        frame.MarginBottom = band;
        return true;
    }
    emitFrameMessage(editor, invalid_screen_height_message);
    return false;
}

fn setWidth(editor: *state.Editor, frame: *types.FrameObject, width: isize, set_initial: bool) bool {
    if (width >= 10 and width <= editor.TerminalInfo.Width) {
        if (set_initial) {
            editor.InitialScrWidth = width;
        }
        frame.ScrWidth = width;
        return true;
    }
    emitFrameMessage(editor, screen_width_invalid_message);
    return false;
}

fn setOpt(frame: *types.FrameObject, ch: u8, set_on: bool, options: *types.FrameOptions) bool {
    _ = frame;
    switch (ch) {
        'S' => return true,
        'I' => if (set_on) types.frameOptionsSet(options, .OptAutoIndent) else types.frameOptionsClear(options, .OptAutoIndent),
        'W' => if (set_on) types.frameOptionsSet(options, .OptAutoWrap) else types.frameOptionsClear(options, .OptAutoWrap),
        'N' => if (set_on) types.frameOptionsSet(options, .OptNewLine) else types.frameOptionsClear(options, .OptNewLine),
        else => return false,
    }
    return true;
}

fn keyboardModeName(mode: types.ModeType) []const u8 {
    return switch (mode) {
        .ModeOvertype => "Overtype Mode",
        .ModeInsert => "Insert Mode",
        .ModeCommand => "Command Mode",
    };
}

fn appendDisplayOption(
    allocator: std.mem.Allocator,
    buffer: *std.ArrayListUnmanaged(u8),
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
    var buffer: std.ArrayListUnmanaged(u8) = .{};
    try buffer.append(allocator, ' ');
    var count: usize = 1;
    var first = true;
    if (types.frameOptionsHas(options, .OptAutoIndent)) {
        try appendDisplayOption(allocator, &buffer, 'I', &first);
        count += 2;
    }
    if (types.frameOptionsHas(options, .OptAutoWrap)) {
        try appendDisplayOption(allocator, &buffer, 'W', &first);
        count += 2;
    }
    if (types.frameOptionsHas(options, .OptNewLine)) {
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
    if (user_ops.UserKeyCodeToName(editor, editor.CommandIntroducer)) |name| {
        return allocator.dupe(u8, name);
    }
    if (editor.CommandIntroducer >= 0 and editor.CommandIntroducer <= std.math.maxInt(u8)) {
        return std.fmt.allocPrint(allocator, "{c}", .{@as(u8, @intCast(editor.CommandIntroducer))});
    }
    return std.fmt.allocPrint(allocator, "{d}", .{editor.CommandIntroducer});
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
    const width: usize = @intCast(@max(frame.ScrWidth, 1));
    const out = try allocator.alloc(u8, width);
    @memset(out, ' ');
    var idx: usize = 1;
    while (idx <= width) : (idx += 1) {
        if (@as(isize, @intCast(idx)) == frame.MarginLeft) {
            out[idx - 1] = 'L';
        } else if (@as(isize, @intCast(idx)) == frame.MarginRight) {
            out[idx - 1] = 'R';
        } else if (frame.TabStops[idx]) {
            out[idx - 1] = 'T';
        }
    }
    return out;
}

fn buildInteractiveParameterLines(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !std.ArrayListUnmanaged([]const u8) {
    var lines: std.ArrayListUnmanaged([]const u8) = .{};
    const frame_name = if (frame.Span != null) frame.Span.?.Name else "";
    const padded_frame_name = try renderName(allocator, frame_name, types.NameLen);
    const version_underline = try allocator.alloc(u8, 7 + types.LudwigVersion.len);
    @memset(version_underline, '=');
    const current_options = try renderOptionsSummary(allocator, frame.Options);
    const default_options = try renderOptionsSummary(allocator, editor.InitialOptions);
    const current_h_margins = try renderMarginsSummary(allocator, frame.MarginLeft, frame.MarginRight);
    const default_h_margins = try renderMarginsSummary(allocator, editor.InitialMarginLeft, editor.InitialMarginRight);
    const current_v_margins = try renderMarginsSummary(allocator, frame.MarginTop, frame.MarginBottom);
    const default_v_margins = try renderMarginsSummary(allocator, editor.InitialMarginTop, editor.InitialMarginBottom);
    const introducer = try renderCommandIntroducerSummary(editor, allocator);
    const unused_memory = try renderInt(allocator, frame.SpaceLeft, 9);
    const line_count = try renderInt(allocator, line_ops.LineToNumber(frame.LastGroup.?.LastLine.?) - 1, 9);
    const input_count = try renderInt(allocator, frame.InputCount, 9);
    const current_line = try renderInt(allocator, line_ops.LineToNumber(frame.Dot.?.Line), 9);
    const current_space_limit = try renderInt(allocator, frame.SpaceLimit, 9);
    const default_space_limit = try renderInt(allocator, editor.FileData.Space, 9);
    const current_scr_height = try renderInt(allocator, frame.ScrHeight, 9);
    const default_scr_height = try renderInt(allocator, editor.InitialScrHeight, 9);
    const current_scr_width = try renderInt(allocator, frame.ScrWidth, 9);
    const default_scr_width = try renderInt(allocator, editor.InitialScrWidth, 9);

    try lines.append(allocator, try joinWithIndent(
        allocator,
        try std.fmt.allocPrint(allocator, " Ludwig {s}", .{types.LudwigVersion}),
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
        .{keyboardModeName(editor.EditMode)},
    ));
    if (editor.LudwigMode == .LudwigScreen) {
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
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
) !bool {
    _ = allocator;
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
                .Str = try str_object.NewStrObjectFrom(temp, response),
                .Len = @intCast(response.len),
            };
            if (!try setParam(editor, temp, frame, &request)) {
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
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    request: *types.TParObject,
) !bool {
    var parser = TparParser{
        .editor = editor,
        .allocator = allocator,
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
                break :blk FrameSetHeight(editor, frame, height, set_initial);
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

pub fn FrameParameter(
    editor: *state.Editor,
    allocator: std.mem.Allocator,
    frame: *types.FrameObject,
    tpar: ?*types.TParObject,
) !bool {
    var request: types.TParObject = .{};
    if (!try tpar_ops.TparGet1(allocator, editor, frame, tpar, .CmdFrameParameters, &request)) {
        return false;
    }
    if (request.Len > 0) {
        return setParam(editor, allocator, frame, &request);
    }
    if (editor.LudwigMode == .LudwigScreen) {
        return showInteractiveParameters(editor, allocator, frame);
    }
    return false;
}

test "frame edit creates and reuses named frames" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const origin_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    const origin = origin_fixture.frame;

    const created = (try FrameEdit(&editor, allocator, origin, "WORK")).?;
    try std.testing.expect(created != origin);
    try std.testing.expect(created.Span != null);
    try std.testing.expectEqualStrings("WORK", created.Span.?.Name);
    try std.testing.expect(created.ReturnFrame == origin);
    try std.testing.expect(created.Span.?.Frame == created);
    try std.testing.expect(created.FirstGroup == created.LastGroup);
    try std.testing.expect(created.Dot != null);

    const reused = (try FrameEdit(&editor, allocator, origin, "WORK")).?;
    try std.testing.expect(reused == created);
    try std.testing.expect(reused.ReturnFrame == origin);
}

test "frame kill removes frame span and clears return links" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const origin_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    const origin = origin_fixture.frame;
    const target = (try FrameEdit(&editor, allocator, origin, "WORK")).?;
    const follower = (try FrameEdit(&editor, allocator, target, "FOLLOW")).?;
    try std.testing.expect(follower.ReturnFrame == target);

    const span_mark_one = target.Span.?.MarkOne.?;
    const span_mark_two = target.Span.?.MarkTwo.?;
    try std.testing.expect(try span_ops.SpanCreate(&editor, allocator, "INNER", span_mark_one, span_mark_two));

    try std.testing.expect(try FrameKill(&editor, allocator, origin, "WORK"));
    try std.testing.expect(follower.ReturnFrame == null);
    try std.testing.expect((try FrameEdit(&editor, allocator, origin, "WORK")).? != target);
}

test "frame kill rejects current and special frames" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const origin_fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"origin"});
    const origin = origin_fixture.frame;
    const current_named = (try FrameEdit(&editor, allocator, origin, "CURRENT")).?;
    try std.testing.expect(!try FrameKill(&editor, allocator, current_named, "CURRENT"));

    const special = (try FrameEdit(&editor, allocator, origin, "SPECIAL")).?;
    types.frameOptionsSet(&special.Options, .OptSpecialFrame);
    try std.testing.expect(!try FrameKill(&editor, allocator, origin, "SPECIAL"));
}

test "frame edit initializes empty frame with end-of-file sentinel" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const frame = (try FrameEdit(&editor, allocator, null, "WORK")).?;
    try std.testing.expectEqualStrings("<End of File>   WORK", line_ops.getDisplayLineContent(frame.LastGroup.?.LastLine.?));
    try std.testing.expectEqualStrings("", line_ops.getLineContent(frame.LastGroup.?.LastLine.?));
}

test "frame parameter updates batch-safe state values" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.TerminalInfo = .{ .Width = 160, .Height = 48 };

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"alpha beta"});
    const frame = fixture.frame;

    const request = "K=O,O=(I,-N),S=1200,H=24,W=100,M=(5,80),V=(2,3),T=(4,8,12),$S=2200,$W=120";
    var tpar = types.TParObject{
        .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, request),
        .Len = request.len,
    };
    try std.testing.expect(try FrameParameter(&editor, allocator, frame, &tpar));
    try std.testing.expectEqual(types.ModeType.ModeOvertype, editor.EditMode);
    try std.testing.expect(types.frameOptionsHas(frame.Options, .OptAutoIndent));
    try std.testing.expect(!types.frameOptionsHas(frame.Options, .OptNewLine));
    try std.testing.expectEqual(@as(isize, 2200), frame.SpaceLimit);
    try std.testing.expectEqual(@as(isize, 24), frame.ScrHeight);
    try std.testing.expectEqual(@as(isize, 120), frame.ScrWidth);
    try std.testing.expectEqual(@as(isize, 5), frame.MarginLeft);
    try std.testing.expectEqual(@as(isize, 80), frame.MarginRight);
    try std.testing.expectEqual(@as(isize, 2), frame.MarginTop);
    try std.testing.expectEqual(@as(isize, 3), frame.MarginBottom);
    try std.testing.expectEqual(@as(isize, '\\'), editor.CommandIntroducer);
    try std.testing.expect(frame.TabStops[4]);
    try std.testing.expect(frame.TabStops[8]);
    try std.testing.expect(frame.TabStops[12]);
    try std.testing.expectEqual(@as(isize, 2200), editor.FileData.Space);
    try std.testing.expectEqual(@as(isize, 120), editor.InitialScrWidth);
}

test "frame parameter accepts named command introducers in screen mode" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.LudwigMode = .LudwigScreen;
    try user_ops.UserKeyInitialize(&editor, allocator);
    const function_key = user_ops.UserKeyNameToCode(&editor, "FUNCTION-1").?;

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"alpha"});
    var tpar = types.TParObject{
        .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, "C=FUNCTION-1"),
        .Len = "C=FUNCTION-1".len,
    };

    try std.testing.expect(try FrameParameter(&editor, allocator, fixture.frame, &tpar));
    try std.testing.expectEqual(function_key, editor.CommandIntroducer);
}

test "frame parameter reports unrecognized named introducers" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.LudwigMode = .LudwigScreen;
    try user_ops.UserKeyInitialize(&editor, allocator);

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"alpha"});
    var tpar = types.TParObject{
        .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, "C=BOGUS"),
        .Len = "C=BOGUS".len,
    };

    try std.testing.expect(!(try FrameParameter(&editor, allocator, fixture.frame, &tpar)));
    try std.testing.expectEqualStrings(unrecognized_key_name_message, interactive_io.takeStatusMessage().?);
}

test "frame parameter queues validation messages in screen mode" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.LudwigMode = .LudwigScreen;
    editor.TerminalInfo = .{ .Width = 120, .Height = 24 };
    try user_ops.UserKeyInitialize(&editor, allocator);

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"alpha"});

    var bad_mode = types.TParObject{
        .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, "K=X"),
        .Len = "K=X".len,
    };
    try std.testing.expect(!(try FrameParameter(&editor, allocator, fixture.frame, &bad_mode)));
    try std.testing.expectEqualStrings(mode_error_message, interactive_io.takeStatusMessage().?);

    var bad_option = types.TParObject{
        .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, "O=Z"),
        .Len = "O=Z".len,
    };
    try std.testing.expect(!(try FrameParameter(&editor, allocator, fixture.frame, &bad_option)));
    try std.testing.expectEqualStrings(unknown_option_message, interactive_io.takeStatusMessage().?);

    var bad_height = types.TParObject{
        .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, "H=999"),
        .Len = "H=999".len,
    };
    try std.testing.expect(!(try FrameParameter(&editor, allocator, fixture.frame, &bad_height)));
    try std.testing.expectEqualStrings(invalid_screen_height_message, interactive_io.takeStatusMessage().?);
}

test "frame parameter tab ruler operations update text and tab stops" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{"alpha beta"});
    const frame = fixture.frame;
    try mark_ops.MarkCreate(allocator, fixture.content_lines[0], 3, &frame.Dot);

    var insert = types.TParObject{
        .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, "T=I"),
        .Len = 3,
    };
    try std.testing.expect(try FrameParameter(&editor, allocator, frame, &insert));
    try std.testing.expect(frame.TextModified);
    const ruler_line = frame.FirstGroup.?.FirstLine.?;
    try std.testing.expect(ruler_line != fixture.content_lines[0]);
    try std.testing.expect(ruler_line.Str.?.Get(frame.MarginLeft) == 'L');
    try std.testing.expect(ruler_line.Str.?.Get(frame.MarginRight) == 'R');

    const current = frame.Dot.?.Line;
    try line_ops.LineChangeLength(allocator, current, 12);
    try line_ops.setLineContent(current, "L  T   T R");
    current.ScrRowNr = 1;
    frame.ScrHeight = 24;

    var apply = types.TParObject{
        .Str = try @import("str_object.zig").NewStrObjectFrom(allocator, "T=R"),
        .Len = 3,
    };
    try std.testing.expect(try FrameParameter(&editor, allocator, frame, &apply));
    try std.testing.expect(frame.TabStops[4]);
    try std.testing.expect(frame.TabStops[8]);
    try std.testing.expectEqual(@as(isize, 1), frame.MarginLeft);
    try std.testing.expectEqual(@as(isize, 10), frame.MarginRight);
}

test "interactive parameter display lines show current settings summary" {
    var editor = try state.Editor.init(std.testing.allocator);
    defer editor.deinit();
    const allocator = editor.allocator();
    editor.LudwigMode = .LudwigScreen;
    editor.TerminalInfo = .{ .Width = 120, .Height = 24 };
    try user_ops.UserKeyInitialize(&editor, allocator);

    const fixture = try line_ops.createContentFrame(allocator, &[_][]const u8{ "alpha", "beta" });
    const frame = fixture.frame;
    frame.ScrWidth = 20;
    frame.ScrHeight = 12;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
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
