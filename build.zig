const std = @import("std");
const zlinter = @import("zlinter");

fn configureLudwigExecutable(
    exe: *std.Build.Step.Compile,
    help_assets_module: *std.Build.Module,
    syntax_data_module: *std.Build.Module,
    syntax_data_types_module: *std.Build.Module,
) void {
    exe.root_module.addImport("generated_help_assets", help_assets_module);
    exe.root_module.addImport("generated_syntax_data", syntax_data_module);
    exe.root_module.addImport("syntax_data_types", syntax_data_types_module);
    exe.root_module.link_libc = true;
    exe.root_module.linkSystemLibrary("ncurses", .{ .preferred_link_mode = .static });
    exe.root_module.linkSystemLibrary("pcre2-8", .{ .preferred_link_mode = .static });
}

pub fn build(b: *std.Build) void {
    const host = b.graph.host;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const help_builder_tool = b.addExecutable(.{
        .name = "ludwighlpbld-tool",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/help_builder.zig"),
            .target = host,
            .optimize = optimize,
        }),
    });
    const install_help_builder_host = b.addInstallArtifact(help_builder_tool, .{
        .dest_sub_path = "ludwighlpbld",
    });

    const help_builder_release = b.addExecutable(.{
        .name = "ludwighlpbld-release",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/help_builder.zig"),
            .target = host,
            .optimize = .ReleaseFast,
        }),
    });
    const install_help_builder_release = b.addInstallArtifact(help_builder_release, .{
        .dest_sub_path = "ludwighlpbld",
    });

    const generate_old_help = b.addRunArtifact(help_builder_tool);
    generate_old_help.addFileArg(b.path("ludwighlp.txt"));
    const old_help_index = generate_old_help.addOutputFileArg("ludwighlp.idx");

    const generate_new_help = b.addRunArtifact(help_builder_tool);
    generate_new_help.addFileArg(b.path("ludwignewhlp.txt"));
    const new_help_index = generate_new_help.addOutputFileArg("ludwignewhlp.idx");

    const install_old_help = b.addInstallFileWithDir(old_help_index, .bin, "ludwighlp.idx");
    const install_new_help = b.addInstallFileWithDir(new_help_index, .bin, "ludwignewhlp.idx");

    const generated_files = b.addWriteFiles();
    _ = generated_files.addCopyFile(old_help_index, "ludwighlp.idx");
    _ = generated_files.addCopyFile(new_help_index, "ludwignewhlp.idx");
    const generated_help_assets = generated_files.add("generated_help_assets.zig",
        \\pub const old_help_index = @embedFile("ludwighlp.idx");
        \\pub const new_help_index = @embedFile("ludwignewhlp.idx");
        \\pub const old_help_index_name = "ludwighlp.idx";
        \\pub const new_help_index_name = "ludwignewhlp.idx";
        \\
    );
    const target_help_assets_module = b.createModule(.{
        .root_source_file = generated_help_assets,
        .target = target,
        .optimize = optimize,
    });
    const host_help_assets_module = b.createModule(.{
        .root_source_file = generated_help_assets,
        .target = host,
        .optimize = optimize,
    });
    const target_syntax_data_types_module = b.createModule(.{
        .root_source_file = b.path("src/highlight/data_types.zig"),
        .target = target,
        .optimize = optimize,
    });
    const host_syntax_data_types_module = b.createModule(.{
        .root_source_file = b.path("src/highlight/data_types.zig"),
        .target = host,
        .optimize = optimize,
    });

    const syntax_gen_tool = b.addExecutable(.{
        .name = "ludwig-syntax-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/syntax_gen.zig"),
            .target = host,
            .optimize = optimize,
        }),
    });
    syntax_gen_tool.root_module.addImport("syntax_data_types", host_syntax_data_types_module);

    const generate_syntax_data = b.addRunArtifact(syntax_gen_tool);
    generate_syntax_data.addDirectoryArg(b.path("highlight/syntax"));
    const generated_syntax_data = generate_syntax_data.addOutputFileArg("generated_syntax_data.zig");
    const target_syntax_data_module = b.createModule(.{
        .root_source_file = generated_syntax_data,
        .target = target,
        .optimize = optimize,
    });
    target_syntax_data_module.addImport("syntax_data_types", target_syntax_data_types_module);
    const host_syntax_data_module = b.createModule(.{
        .root_source_file = generated_syntax_data,
        .target = host,
        .optimize = optimize,
    });
    host_syntax_data_module.addImport("syntax_data_types", host_syntax_data_types_module);

    const ludwig = b.addExecutable(.{
        .name = "ludwig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    configureLudwigExecutable(
        ludwig,
        target_help_assets_module,
        target_syntax_data_module,
        target_syntax_data_types_module,
    );
    const install_ludwig = b.addInstallArtifact(ludwig, .{});

    const ludwig_debug = b.addExecutable(.{
        .name = "ludwig-debug",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });
    configureLudwigExecutable(
        ludwig_debug,
        target_help_assets_module,
        target_syntax_data_module,
        target_syntax_data_types_module,
    );
    const install_ludwig_debug = b.addInstallArtifact(ludwig_debug, .{
        .dest_sub_path = "ludwig-debug",
    });

    const ludwig_release = b.addExecutable(.{
        .name = "ludwig-release",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    configureLudwigExecutable(
        ludwig_release,
        target_help_assets_module,
        target_syntax_data_module,
        target_syntax_data_types_module,
    );
    const install_ludwig_release = b.addInstallArtifact(ludwig_release, .{
        .dest_sub_path = "ludwig",
    });

    // `zig build` should install the primary Zig binaries plus the generated
    // help assets needed for packaging and local developer flows.
    b.getInstallStep().dependOn(&install_ludwig.step);
    b.getInstallStep().dependOn(&install_help_builder_host.step);
    b.getInstallStep().dependOn(&install_old_help.step);
    b.getInstallStep().dependOn(&install_new_help.step);

    const help_builder_step = b.step("ludwighlpbld", "Build the Zig help-index builder");
    help_builder_step.dependOn(&install_help_builder_host.step);

    const ludwig_step = b.step("ludwig", "Build the Zig ludwig editor bootstrap");
    ludwig_step.dependOn(&install_ludwig.step);

    const help_assets_step = b.step("help-assets", "Generate indexed help assets");
    help_assets_step.dependOn(&install_old_help.step);
    help_assets_step.dependOn(&install_new_help.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = host,
            .optimize = optimize,
        }),
    });
    unit_tests.root_module.link_libc = true;
    unit_tests.root_module.linkSystemLibrary("ncurses", .{ .preferred_link_mode = .static });
    unit_tests.root_module.linkSystemLibrary("pcre2-8", .{ .preferred_link_mode = .static });
    unit_tests.root_module.addImport("generated_help_assets", host_help_assets_module);
    unit_tests.root_module.addImport("generated_syntax_data", host_syntax_data_module);
    unit_tests.root_module.addImport("syntax_data_types", host_syntax_data_types_module);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.skip_foreign_checks = true;

    const setup_step = b.step("setup", "No-op; Zig creates output directories automatically");

    const build_hlpbld_step = b.step("build-hlpbld", "Build release help documentation builder");
    build_hlpbld_step.dependOn(setup_step);
    build_hlpbld_step.dependOn(&install_help_builder_release.step);

    const build_help_step = b.step("build-help", "Build help documentation");
    build_help_step.dependOn(build_hlpbld_step);
    build_help_step.dependOn(&install_old_help.step);
    build_help_step.dependOn(&install_new_help.step);

    const build_step = b.step("build", "Build debug binary");
    build_step.dependOn(setup_step);
    build_step.dependOn(build_help_step);
    build_step.dependOn(&install_ludwig_debug.step);

    const build_release_step = b.step("build-release", "Build release binary");
    build_release_step.dependOn(setup_step);
    build_release_step.dependOn(build_help_step);
    build_release_step.dependOn(&install_ludwig_release.step);

    const test_step = b.step("test", "Run Zig unit tests");
    test_step.dependOn(build_help_step);
    test_step.dependOn(&run_unit_tests.step);

    const system_test_run = b.addSystemCommand(&.{
        "sh",
        "-c",
        "if [ -x ./system-test/run-system-test.sh ]; then ./system-test/run-system-test.sh --showlocals; else echo 'system-test/run-system-test.sh not found; skipping'; fi",
    });
    system_test_run.step.dependOn(build_release_step);
    system_test_run.setCwd(b.path("."));
    system_test_run.setEnvironmentVariable("LUDWIG_EXE", b.getInstallPath(.bin, "ludwig"));
    const system_test_step = b.step("system-test", "Run system tests if present");
    system_test_step.dependOn(&system_test_run.step);

    const check_step = b.step("check", "Run all checks");
    check_step.dependOn(build_step);
    check_step.dependOn(build_release_step);
    check_step.dependOn(test_step);
    check_step.dependOn(system_test_step);

    const clean_run = b.addSystemCommand(&.{
        "sh",
        "-c",
        "rm -rf zig-out .zig-cache",
    });
    clean_run.setCwd(b.path("."));
    const clean_step = b.step("clean", "Remove built binaries and generated outputs");
    clean_step.dependOn(&clean_run.step);

    const lint_cmd = b.step("lint", "Lint source code.");
    lint_cmd.dependOn(step: {
        // Swap in and out whatever rules you see fit from RULES.md
        var builder = zlinter.builder(b, .{});
        builder.addRule(.{ .builtin = .field_naming }, .{
            .struct_field_min_len = .{ .len = 0, .severity = .warning },
            .struct_field_max_len = .{ .len = 80, .severity = .warning },
        });
        builder.addRule(.{ .builtin = .declaration_naming }, .{
            .decl_name_min_len = .{ .len = 0, .severity = .warning },
            .decl_name_max_len = .{ .len = 80, .severity = .warning },
        });
        builder.addRule(.{ .builtin = .function_naming }, .{});
        builder.addRule(.{ .builtin = .file_naming }, .{});
        builder.addRule(.{ .builtin = .switch_case_ordering }, .{});
        builder.addRule(.{ .builtin = .no_unused }, .{});
        builder.addRule(.{ .builtin = .no_deprecated }, .{});
        builder.addRule(.{ .builtin = .no_orelse_unreachable }, .{});
        break :step builder.build();
    });
}
