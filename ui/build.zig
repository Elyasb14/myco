const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "myco-ui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.linkLibC();
    exe.linkLibCpp();
    exe.linkSystemLibrary("glfw");
    exe.linkSystemLibrary("GL"); // On Linux; use "OpenGL" on macOS
    exe.linkSystemLibrary("dl");
    exe.linkSystemLibrary("pthread");
    exe.addIncludePath(b.path("deps/cimgui"));
    exe.addIncludePath(b.path("deps/cimgui/imgui"));
    exe.addIncludePath(b.path("deps/cimgui/backends"));
    exe.addCSourceFiles(.{
        .files = &.{
            "deps/cimgui/imgui/imgui.cpp",
            "deps/cimgui/imgui/imgui_draw.cpp",
            "deps/cimgui/imgui/imgui_widgets.cpp",
            "deps/cimgui/imgui/imgui_tables.cpp",
            "deps/cimgui/imgui/imgui_demo.cpp",
            "deps/cimgui/cimgui.cpp",
            "deps/cimgui/imgui/backends/imgui_impl_glfw.cpp",
            "deps/cimgui/imgui/backends/imgui_impl_opengl3.cpp",
        },
        .flags = &.{
            "-std=c++17",
            "-DIMGUI_IMPL_OPENGL_LOADER_GLAD",
        },
    });

    b.installArtifact(exe);
}
