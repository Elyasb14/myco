const std = @import("std");
const nl = @import("netlink");
const linux = std.os.linux;

pub fn main() !void {
    const nl_sock = try nl.NetlinkSocket.open(linux.NETLINK.ROUTE);
    defer nl_sock.close();

    const info = nl.LinkInfo{ .kind = "wireguard", .name = "night" };
    const info2 = nl.LinkInfo{ .kind = "night", .name = "blah" };

    var buf: [24]nl.LinkInfo = undefined;

    try nl_sock.add_link(info);
    try nl_sock.dump_links(&buf);
    try nl_sock.del_link(info2);
}
