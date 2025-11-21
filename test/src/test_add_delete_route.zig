const std = @import("std");
const nl = @import("netlink");
const linux = std.os.linux;

pub fn main() !void {
    const nl_sock = try nl.NetlinkSocket.open(linux.NETLINK.ROUTE);
    defer nl_sock.close();

    const route_info = nl.RouteInfo{
        .dst = .{ 1, 1, 1, 2 },
        .gw = .{ 10, 1, 2, 1 },
        .oif = 2,
        .metric = 100,
    };

    // var route_buf_pre: [24]nl.RouteInfo = undefined;
    var route_buf_post: [24]nl.RouteInfo = undefined;

    // try nl_sock.add_route(route_info);
    // const n = try nl_sock.dump_routing_table(&route_buf_pre);
    // const routes = route_buf_pre[0..n];
    // for (routes) |x| {
    //     std.debug.print("{any}\n", .{x});
    // }

    try nl_sock.del_route(route_info);
    const m = try nl_sock.dump_routing_table(&route_buf_post);
    const routes_new = route_buf_post[0..m];
    for (routes_new) |x| {
        std.debug.print("{any}\n", .{x});
    }
}
