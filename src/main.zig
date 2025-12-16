const std = @import("std");
const nl = @import("netlink");
const conf = @import("config");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try conf.apply_config(allocator, "src/configure/config.myco");
}
