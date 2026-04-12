const state = @import("state.zig");
const types = @import("types.zig");

pub fn codeDiscard(editor: *state.Editor, code_head: *?*types.CodeHeader) void {
    if (code_head.* == null) {
        return;
    }

    code_head.*.?.Ref -= 1;
    if (code_head.*.?.Ref == 0) {
        const start = code_head.*.?.Code;
        const size = code_head.*.?.Len;

        var source = start;
        while (source < start + size) : (source += 1) {
            if (editor.compiler_code[@intCast(source)].Code != null) {
                codeDiscard(editor, &editor.compiler_code[@intCast(source)].Code);
            }
            editor.compiler_code[@intCast(source)].Tpar = null;
        }

        source = start + size;
        while (source <= editor.code_top) : (source += 1) {
            editor.compiler_code[@intCast(source - size)] = editor.compiler_code[@intCast(source)];
        }
        editor.code_top -= size;

        var link = code_head.*.?.BLink;
        while (link != editor.code_list) {
            link.?.Code -= size;
            link = link.?.BLink;
        }

        code_head.*.?.FLink.?.BLink = code_head.*.?.BLink;
        code_head.*.?.BLink.?.FLink = code_head.*.?.FLink;
        code_head.* = null;
    }
}
