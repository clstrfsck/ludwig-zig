const state = @import("state.zig");
const types = @import("types.zig");

pub fn CodeDiscard(editor: *state.Editor, code_head: *?*types.CodeHeader) void {
    if (code_head.* == null) {
        return;
    }

    code_head.*.?.Ref -= 1;
    if (code_head.*.?.Ref == 0) {
        const start = code_head.*.?.Code;
        const size = code_head.*.?.Len;

        var source = start;
        while (source < start + size) : (source += 1) {
            if (editor.CompilerCode[@intCast(source)].Code != null) {
                CodeDiscard(editor, &editor.CompilerCode[@intCast(source)].Code);
            }
            editor.CompilerCode[@intCast(source)].Tpar = null;
        }

        source = start + size;
        while (source <= editor.CodeTop) : (source += 1) {
            editor.CompilerCode[@intCast(source - size)] = editor.CompilerCode[@intCast(source)];
        }
        editor.CodeTop -= size;

        var link = code_head.*.?.BLink;
        while (link != editor.CodeList) {
            link.?.Code -= size;
            link = link.?.BLink;
        }

        code_head.*.?.FLink.?.BLink = code_head.*.?.BLink;
        code_head.*.?.BLink.?.FLink = code_head.*.?.FLink;
        code_head.* = null;
    }
}
