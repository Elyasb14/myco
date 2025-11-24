const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const myco_exe = b.addExecutable(.{
        .name = "myco",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const netlink_mod = b.addModule("netlink", .{
        .root_source_file = b.path("src/netlink/netlink.zig"),
    });

    myco_exe.root_module.addImport("netlink", netlink_mod);
    myco_exe.linkLibC();
    b.installArtifact(myco_exe);

    const tests = b.addTest(.{ .name = "netlink", .root_module = b.createModule(.{ .root_source_file = b.path("src/netlink/netlink.zig"), .optimize = optimize, .target = target }) });

    // add modules for the test runner too
    tests.root_module.addImport("netlink", netlink_mod);
    tests.linkLibC();

    const run_tests = b.addRunArtifact(tests);

    // "zig build test" will execute tests
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_tests.step);
}
