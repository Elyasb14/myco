const std = @import("std");

const c = @cImport({
    @cInclude("GLFW/glfw3.h");
    @cInclude("cimgui.h");
    @cInclude("imgui_impl_glfw.h");
    @cInclude("imgui_impl_opengl3.h");
});

pub fn main() !void {
    if (c.glfwInit() == 0) return error.GlfwInitFailed;
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);

    const window = c.glfwCreateWindow(800, 600, "ImGui + Zig", null, null) orelse return error.CreateWindowFailed;
    defer c.glfwDestroyWindow(window);

    c.glfwMakeContextCurrent(window);
    c.glfwSwapInterval(1);

    // Setup Dear ImGui context
    const ctx = c.igCreateContext(null);
    defer c.igDestroyContext(ctx);

    const io = c.igGetIO();
    _ = io;

    // Setup ImGui backends
    _ = c.ImGui_ImplGlfw_InitForOpenGL(window, true);
    _ = c.ImGui_ImplOpenGL3_Init("#version 330");

    defer c.ImGui_ImplOpenGL3_Shutdown();
    defer c.ImGui_ImplGlfw_Shutdown();

    // Main loop
    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();

        c.ImGui_ImplOpenGL3_NewFrame();
        c.ImGui_ImplGlfw_NewFrame();
        c.igNewFrame();

        // ---- UI ----
        var show_window: bool = true;
        c.igBegin("Hello from Zig!", &show_window, 0);
        c.igText("This is Dear ImGui running via Zig!");
        if (c.igButton("Click me!", .{ 120, 0 })) {
            std.debug.print("Button clicked!\n", .{});
        }
        c.igEnd();
        // ------------

        c.igRender();
        const display_w = c.glfwGetFramebufferWidth(window);
        const display_h = c.glfwGetFramebufferHeight(window);
        c.glViewport(0, 0, display_w, display_h);
        c.glClearColor(0.1, 0.1, 0.1, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.ImGui_ImplOpenGL3_RenderDrawData(c.igGetDrawData());
        c.glfwSwapBuffers(window);
    }

    c.ImGui_ImplOpenGL3_Shutdown();
    c.ImGui_ImplGlfw_Shutdown();
    c.igDestroyContext(ctx);
}

