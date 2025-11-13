const std = @import("std");
const nl = @import("netlink/route.zig");
const linux = std.os.linux;

pub fn main() !void {
    const sock = try nl.NetlinkSocket.open();
    defer sock.close();

    var kern_addr = linux.sockaddr.nl{
        .family = linux.AF.NETLINK,
        .pid = 0, // destination: kernel
        .groups = 0,
    };

    const route_info = nl.RouteInfo{
        .dst = .{ 1, 1, 1, 2 },
        .gw = .{ 10, 225, 139, 1 },
        .oif = 2,
        .metric = 100,
    };

    try nl.send_route_add_req(sock.sock, &kern_addr, route_info);

    try nl.send_route_dump_req(sock.sock, &kern_addr);
    try nl.recv_route_dump_resp(sock.sock, &kern_addr);

    try nl.send_route_del_req(sock.sock, &kern_addr, route_info);

    try nl.send_route_dump_req(sock.sock, &kern_addr);
    try nl.recv_route_dump_resp(sock.sock, &kern_addr);
}
