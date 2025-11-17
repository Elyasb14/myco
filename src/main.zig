const std = @import("std");
const nl = @import("netlink/netlink.zig");
const linux = std.os.linux;

pub fn main() !void {
    const nl_sock = try nl.NetlinkSocket.open(linux.NETLINK.ROUTE);
    defer nl_sock.close();

    const route_info = nl.RouteInfo{
        .dst = .{ 1, 1, 1, 2 },
        .gw = .{ 10, 225, 139, 1 },
        .oif = 2,
        .metric = 100,
    };

    try nl_sock.add_route(route_info);
    const routes = try nl_sock.dump_routing_table();
    std.debug.print("routes: {any}\n", .{routes});

    try nl_sock.del_route(route_info);
    const routes_new = try nl_sock.dump_routing_table();
    std.debug.print("routes new: {any}\n", .{routes_new});
}
