const std = @import("std");
const nl = @import("netlink");
const linux = std.os.linux;

pub fn main() !void {
    const nl_sock = try nl.NetlinkSocket.open(linux.NETLINK.ROUTE);
    defer nl_sock.close();

    const addr_bytes: [4]u8 = .{ 10, 225, 139, 7 };
    const addr_info = nl.AddrInfo{
        .if_index = 2,
        .prefix_len = 26,
        .address = addr_bytes,
    };

    std.debug.print("*** NEW ADDR ***\n", .{});
    try nl_sock.add_addr(addr_info);
    const addrs = try nl_sock.dump_addresses();
    for (addrs) |x| {
        std.debug.print("addr: {any}\n", .{x});
    }
    std.debug.print("\n", .{});

    std.debug.print("*** DELETE ADDR ***\n", .{});
    try nl_sock.del_addr(addr_info);
    const addrs_new = try nl_sock.dump_addresses();
    for (addrs_new) |x| {
        std.debug.print("addr: {any}\n", .{x});
    }
}
