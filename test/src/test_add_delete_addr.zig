const std = @import("std");
const nl = @import("netlink");
const linux = std.os.linux;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nl_sock = try nl.NetlinkSocket.open(allocator, linux.NETLINK.ROUTE);
    defer nl_sock.close();

    const addr_bytes: [4]u8 = .{ 10, 225, 139, 7 };
    const addr_info = nl.AddrInfo{
        .if_index = 2,
        .prefix_len = 26,
        .address = addr_bytes,
    };

    var addr_buf_pre: [24]nl.AddrInfo = undefined;
    var addr_buf_post: [24]nl.AddrInfo = undefined;

    std.debug.print("*** NEW ADDR ***\n", .{});
    try nl_sock.add_addr(addr_info);
    const n = try nl_sock.dump_addresses(&addr_buf_pre);
    const addrs = addr_buf_pre[0..n];

    for (addrs) |x| {
        std.debug.print("addr: {any}\n", .{x});
    }
    std.debug.print("\n", .{});

    std.debug.print("*** DELETE ADDR ***\n", .{});
    try nl_sock.del_addr(addr_info);
    const m = try nl_sock.dump_addresses(&addr_buf_post);
    const addrs_new = addr_buf_post[0..m];

    for (addrs_new) |x| {
        std.debug.print("addr: {any}\n", .{x});
    }
}
