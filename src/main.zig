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
    try nl_sock.add_addr(addr_info);
    const addrs = try nl_sock.dump_addresses();
    std.debug.print("addrs: {any}\n", .{addrs});
}
