const std = @import("std");
const nl = @import("netlink");
const linux = std.os.linux;

pub fn main() !void {
    const nl_sock = try nl.NetlinkSocket.open(linux.NETLINK.ROUTE);
    defer nl_sock.close();

    const addr = nl.AddrInfo{ .address = .{ 10, 227, 6, 3 }, .if_index = 3, .prefix_len = 24 };

    const info = nl.LinkInfo{ .kind = "wireguard", .name = "night", .index = 3, .addrs = &[_]nl.AddrInfo{addr} };
    const info2 = nl.LinkInfo{ .kind = "wireguard", .name = "night", .index = 3, .addrs = &[_]nl.AddrInfo{addr} };

    std.debug.print("*** NEW LINK ***\n", .{});
    var pre_buf: [24]nl.LinkInfo = undefined;
    try nl_sock.add_link(info);
    const n = try nl_sock.dump_links(&pre_buf);
    const links = pre_buf[0..n];
    for (links) |x| {
        std.debug.print("{any}\n", .{x});
    }

    std.debug.print("\n", .{});

    std.debug.print("*** DELETED LINK ***\n", .{});
    var post_buf: [24]nl.LinkInfo = undefined;
    try nl_sock.del_link(info2);
    const m = try nl_sock.dump_links(&post_buf);
    const links_new = post_buf[0..m];
    for (links_new) |x| {
        std.debug.print("{any}\n", .{x});
    }
}
