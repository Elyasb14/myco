const std = @import("std");
const nl = @import("netlink");
const linux = std.os.linux;

pub fn main() !void {
    const nl_sock = try nl.NetlinkSocket.open(linux.NETLINK.ROUTE);
    defer nl_sock.close();

    const info = nl.LinkInfo{ .ifname = "night", .kind = "wireguard", .mtu = 12 };

    std.debug.print("*** NEW LINK ***\n", .{});
    var pre_buf: [24]nl.LinkInfo = undefined;
    try nl_sock.add_link(info);
    const n = try nl_sock.dump_links(&pre_buf);
    const links = pre_buf[0..n];
    for (links) |x| {
        std.debug.print("{any}\n", .{x});
    }
}
