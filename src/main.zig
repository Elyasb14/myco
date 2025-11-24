const std = @import("std");
const nl = @import("netlink");
const linux = std.os.linux;

pub fn main() !void {
    const nl_sock = try nl.NetlinkSocket.open(linux.NETLINK.ROUTE);
    defer nl_sock.close();

    const info = nl.LinkInfo{ .kind = "wireguard", .name = "night", .index = 370 };
    const info2 = nl.LinkInfo{ .kind = "wireguard", .name = "night", .index = 370 };

    var buf: [24]nl.LinkInfo = undefined;

    try nl_sock.add_link(info);
    const n = try nl_sock.dump_links(&buf);
    const links = buf[0..n];
    for (links) |x| {
        std.debug.print("LINK NAME: {s}\n", .{x.name});
        if (x.kind) |kind| std.debug.print("LINK KIND: {s}\n", .{kind});
        std.debug.print("INDEX: {d}\n", .{x.index});
    }
    try nl_sock.del_link(info2);
}
