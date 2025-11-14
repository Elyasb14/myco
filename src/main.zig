const std = @import("std");
const nl = @import("netlink/route.zig");
const linux = std.os.linux;

pub fn main() !void {
    const nl_sock = try nl.NetlinkSocket.open();
    defer nl_sock.close();

    const route_info = nl.RouteInfo{
        .dst = .{ 1, 1, 1, 2 },
        .gw = .{ 10, 225, 139, 1 },
        .oif = 2,
        .metric = 100,
    };

    try nl_sock.add_route(route_info);
    try nl_sock.dump_routing_table();
    try nl_sock.del_route(route_info);
    try nl_sock.dump_routing_table();
}
