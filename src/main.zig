const std = @import("std");
const linux = std.os.linux;

const c = @cImport({
    @cInclude("linux/rtnetlink.h");
});

/// this struct gets packed as bytes and sent over a socket
/// be careful adding fields
/// see usage in send_route_dump_request
const RouteInfo = struct {
    dst: ?[4]u8 = null,
    gw: ?[4]u8 = null,
    oif: ?u32 = null,
    prefsrc: ?[4]u8 = null,
    metric: ?u32 = null,
};

fn recv_route_dump_resp(fd: i32, kern_addr: *linux.sockaddr.nl) void {
    var buf: [8192]u8 = undefined;
    var from_len: linux.socklen_t = @sizeOf(linux.sockaddr.nl);
    while (true) {
        const len = linux.recvfrom(
            fd,
            &buf,
            buf.len,
            0,
            @ptrCast(kern_addr),
            &from_len,
        );
        if (len < 0) break;
        if (len == 0) break;

        var offset: usize = 0;
        while (offset < len) {
            const hdr: *const c.nlmsghdr = @ptrCast(@alignCast(&buf[offset]));

            if (hdr.nlmsg_type == c.NLMSG_DONE) {
                std.debug.print("End of dump\n", .{});
                return;
            } else if (hdr.nlmsg_type == c.NLMSG_ERROR) {
                std.debug.print("Netlink error\n", .{});
                return;
            } else if (hdr.nlmsg_type == c.RTM_NEWROUTE) {
                // get address immediately after the nlmsghdr
                // need to cast to *anyopaque because @ptrFromInt produces a typeless pointer (same as void * in C)
                const rtm_buf_ptr: *const anyopaque = @ptrFromInt(@intFromPtr(hdr) + @sizeOf(c.nlmsghdr));

                // reinterpret the above pointer as a *const c.rtmsg
                // @alignCast ensures correct alignment before casting to the specific type
                const rtmsg: *const c.rtmsg = @ptrCast(@alignCast(rtm_buf_ptr));

                // compute start and length of the attribute section following rtmsg
                const attr_start = @intFromPtr(rtmsg) + @sizeOf(c.rtmsg);
                const attr_len = hdr.nlmsg_len - @sizeOf(c.nlmsghdr) - @sizeOf(c.rtmsg);

                // create a slice of buf that covers just the attributes section
                const attr_buf = buf[@intCast(attr_start - @intFromPtr(&buf))..@intCast(attr_start - @intFromPtr(&buf) + attr_len)];

                // parse the attribute buffer
                const route_info = parse_rtattrs(attr_buf);
                std.debug.print("ROUTE INFO: {any}\n", .{route_info});
            }

            offset += @intCast(c.NLMSG_ALIGN(hdr.nlmsg_len));
        }
    }
}

fn parse_rtattrs(buf: []u8) RouteInfo {
    var offset: usize = 0;

    var route = RouteInfo{};

    while (offset + @sizeOf(c.rtattr) <= buf.len) {
        const rta: *const c.rtattr = @ptrCast(@alignCast(&buf[offset]));
        if (rta.rta_len == 0) break;

        const data_len: usize = @as(usize, @intCast(rta.rta_len)) - @sizeOf(c.rtattr);
        const data = buf[offset + @sizeOf(c.rtattr) .. offset + @sizeOf(c.rtattr) + data_len];

        switch (rta.rta_type) {
            c.RTA_DST => {
                if (data_len == 4)
                    route.dst = @as(*const [4]u8, @ptrCast(data.ptr)).*;
            },
            c.RTA_GATEWAY => {
                if (data_len == 4)
                    route.gw = @as(*const [4]u8, @ptrCast(data.ptr)).*;
            },
            c.RTA_PREFSRC => {
                if (data_len == 4)
                    route.prefsrc = @as(*const [4]u8, @ptrCast(data.ptr)).*;
            },
            c.RTA_PRIORITY => {
                if (data_len >= 4)
                    route.metric = std.mem.readInt(u32, @ptrCast(data), .little);
            },
            c.RTA_OIF => {
                if (data_len >= 4)
                    route.oif = std.mem.readInt(u32, @ptrCast(data), .little);
            },
            else => {},
        }

        offset += @intCast(c.RTA_ALIGN(rta.rta_len));
    }
    return route;
}
fn open_netlink() !i32 {
    const fd: i32 = @intCast(linux.socket(linux.AF.NETLINK, linux.SOCK.RAW, linux.NETLINK.ROUTE));

    const addr: linux.sockaddr.nl = .{
        .family = linux.AF.NETLINK,
        .pid = @intCast(linux.getpid()),
        .groups = 0,
    };

    if (linux.bind(@intCast(fd), @ptrCast(&addr), @sizeOf(@TypeOf(addr))) < 0) {
        return error.CantBind;
    }
    return fd;
}

const nl_request = struct { nlh: c.nlmsghdr, rtm: c.rtmsg, rtattr: ?[]c.rtattr = null };
fn send_route_add_req(fd: i32, kern_addr: linux.sockaddr.nl, info: RouteInfo) !void {
    _ = info;
    const req = nl_request{ .nlh = .{
        .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_NEWROUTE)),
        .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_CREATE | c.NLM_F_EXCL,
        .nlmsg_len = @sizeOf(nl_request),
        .nlmsg_seq = @intCast(std.time.timestamp()),
    }, .rtm = .{ .rtm_family = linux.AF.INET, .rtm_table = c.RT_TABLE_MAIN, .rtm_protocol = c.RTPROT_STATIC, .rtm_scope = c.RT_SCOPE_UNIVERSE, .rtm_type = c.RTN_UNICAST } };

    const sent = linux.sendto(@intCast(fd), std.mem.asBytes(&req), req.nlh.nlmsg_len, 0, @ptrCast(&kern_addr), @sizeOf(@TypeOf(kern_addr)));
    if (sent < 0) return error.SendFailed;
}

/// sendto takes ?*const sockaddr
/// recvfrom takes ?* sockaddr
/// this is why we pass by value not by pointer
fn send_route_dump_req(fd: i32, kern_addr: linux.sockaddr.nl) !void {
    const nlh = c.nlmsghdr{
        .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_GETROUTE)),
        .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_DUMP,
        .nlmsg_len = @sizeOf(nl_request), //TODO: need to get rid of this calculation to get rid of the nl_request struct
        .nlmsg_seq = @intCast(std.time.timestamp()),
    };
    const rtm = c.rtmsg{ .rtm_family = linux.AF.INET, .rtm_table = c.RT_TABLE_MAIN };

    const req = std.mem.asBytes(&nlh) ++ std.mem.asBytes(&rtm);

    const sent = linux.sendto(@intCast(fd), req, nlh.nlmsg_len, 0, @ptrCast(&kern_addr), @sizeOf(@TypeOf(kern_addr)));
    if (sent < 0) return error.SendFailed;
}

pub fn main() !void {
    const fd = try open_netlink();
    defer _ = linux.close(@intCast(fd));

    // TODO: why is this var and addr is const
    var kern_addr = linux.sockaddr.nl{
        .family = linux.AF.NETLINK,
        .pid = 0, // destination: kernel
        .groups = 0,
    };

    try send_route_dump_req(fd, kern_addr);
    recv_route_dump_resp(fd, &kern_addr);
    // const route_info = RouteInfo{};
    // try send_route_add_req(fd, kern_addr, route_info);
}
