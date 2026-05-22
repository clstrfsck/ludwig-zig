const state = @import("state.zig");
const types = @import("types.zig");

pub fn codeDiscard(editor: *state.Editor, code_head: *?*types.CodeHeader) void {
    if (code_head.* == null) {
        return;
    }

    code_head.*.?.ref -= 1;
    if (code_head.*.?.ref == 0) {
        const start = code_head.*.?.code;
        const size = code_head.*.?.len;

        var source = start;
        while (source < start + size) : (source += 1) {
            if (editor.compiler_code[@intCast(source)].code != null) {
                codeDiscard(editor, &editor.compiler_code[@intCast(source)].code);
            }
            editor.compiler_code[@intCast(source)].tpar = null;
        }

        source = start + size;
        while (source <= editor.code_top) : (source += 1) {
            editor.compiler_code[@intCast(source - size)] = editor.compiler_code[@intCast(source)];
        }
        editor.code_top -= size;

        var link = code_head.*.?.b_link;
        while (link != editor.code_list) {
            link.?.code -= size;
            link = link.?.b_link;
        }

        code_head.*.?.f_link.?.b_link = code_head.*.?.b_link;
        code_head.*.?.b_link.?.f_link = code_head.*.?.f_link;
        code_head.* = null;
    }
}
