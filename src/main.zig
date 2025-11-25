const std = @import("std");
const nl = @import("netlink");
const linux = std.os.linux;

pub fn main() !void {
    const nl_sock = try nl.NetlinkSocket.open(linux.NETLINK.ROUTE);
    defer nl_sock.close();

    const info = nl.LinkInfo{ .ifname = "wg0", .kind = "wireguard", .mtu = 12, .index = 12 };
    var addr = nl.AddrInfo{ .if_index = info.index.?, .prefix_len = 24, .address = .{ 192, 168, 33, 1 } };

    try nl_sock.add_link(info);

    try nl_sock.enable_link(info.index.?);
    try nl_sock.assign_link_ip(info, &addr);
}
