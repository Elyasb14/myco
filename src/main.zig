const std = @import("std");
const nl = @import("netlink");
const linux = std.os.linux;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

}
