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

    const dsl_mod = b.addModule("dsl", .{
        .root_source_file = b.path("src/dsl/dsl.zig"),
    });

    dsl_mod.addImport("netlink", netlink_mod);

    myco_exe.root_module.addImport("netlink", netlink_mod);
    myco_exe.root_module.addImport("dsl", dsl_mod);
    myco_exe.linkLibC();

    b.installArtifact(myco_exe);
}
