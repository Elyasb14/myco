const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const netlink_mod = b.addModule("netlink", .{
        .root_source_file = b.path("../src/netlink/netlink.zig"),
    });

    const test_add_delete_route = b.addExecutable(.{ .name = "test_add_delete_route", .root_module = b.createModule(.{ .root_source_file = b.path("src/test_add_delete_route.zig"), .target = target, .optimize = optimize }) });
    test_add_delete_route.root_module.addImport("netlink", netlink_mod);

    const test_add_delete_addr = b.addExecutable(.{ .name = "test_add_delete_addr", .root_module = b.createModule(.{ .root_source_file = b.path("src/test_add_delete_addr.zig"), .target = target, .optimize = optimize }) });
    test_add_delete_addr.root_module.addImport("netlink", netlink_mod);

    const test_add_delete_link = b.addExecutable(.{ .name = "test_add_delete_link", .root_module = b.createModule(.{ .root_source_file = b.path("src/test_add_delete_link.zig"), .target = target, .optimize = optimize }) });
    test_add_delete_link.root_module.addImport("netlink", netlink_mod);

    test_add_delete_link.linkLibC();
    test_add_delete_route.linkLibC();
    test_add_delete_addr.linkLibC();
    b.installArtifact(test_add_delete_route);
    b.installArtifact(test_add_delete_addr);
    b.installArtifact(test_add_delete_link);
}
