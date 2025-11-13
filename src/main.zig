const std = @import("std");
const nl = @import("netlink.zig");
const linux = std.os.linux;

pub fn main() !void {
    const fd = try nl.open_netlink();
    defer _ = linux.close(@intCast(fd));

    // TODO: why is this var and addr is const
    var kern_addr = linux.sockaddr.nl{
        .family = linux.AF.NETLINK,
        .pid = 0, // destination: kernel
        .groups = 0,
    };

    const route_info = nl.RouteInfo{
        .dst = .{ 1, 1, 1, 1 },
        .gw = .{ 10, 225, 139, 1 },
        .oif = 2,
        .metric = 100,
    };

    try nl.send_route_add_req(fd, kern_addr, route_info);

    try nl.send_route_dump_req(fd, kern_addr);
    nl.recv_route_dump_resp(fd, &kern_addr);

    try nl.send_route_del_req(fd, kern_addr, route_info);

    try nl.send_route_dump_req(fd, kern_addr);
    nl.recv_route_dump_resp(fd, &kern_addr);
}
