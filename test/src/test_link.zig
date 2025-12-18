const std = @import("std");
const nl = @import("netlink");
const linux = std.os.linux;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const nl_sock = try nl.NetlinkSocket.open(allocator, linux.NETLINK.ROUTE);
    defer nl_sock.close();

    const info = nl.LinkInfo{ .ifname = "wg0", .kind = "wireguard", .mtu = 12 };
    var addr = nl.AddrInfo{ .if_index = try nl.c_nametoifindex(allocator, "wg0"), .prefix_len = 24, .address = .{ 192, 168, 33, 1 } };

    try nl_sock.add_link(info);

    try nl_sock.enable_link(info);
    try nl_sock.assign_idx_ip(addr.if_index, &addr);

    try nl_sock.disable_link(info);
    try nl_sock.del_link(info);
}
