const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const netlink_mod = b.addModule("netlink", .{
        .root_source_file = b.path("../src/netlink/netlink.zig"),
    });

    const test_add_delete = b.addExecutable(.{ .name = "test_add_delete", .root_module = b.createModule(.{ .root_source_file = b.path("src/test_add_delete.zig"), .target = target, .optimize = optimize }) });
    test_add_delete.root_module.addImport("netlink", netlink_mod);
    test_add_delete.linkLibC();

    b.installArtifact(test_add_delete);
}
