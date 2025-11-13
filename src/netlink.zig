const std = @import("std");
const linux = std.os.linux;

const c = @cImport({
    @cInclude("linux/rtnetlink.h");
});

pub const RouteInfo = struct {
    dst: ?[4]u8 = null,
    gw: ?[4]u8 = null,
    oif: ?u32 = null,
    prefsrc: ?[4]u8 = null,
    metric: ?u32 = null,
};

pub fn recv_route_dump_resp(fd: i32, kern_addr: *linux.sockaddr.nl) void {
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

pub fn parse_rtattrs(buf: []u8) RouteInfo {
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

pub fn open_netlink() !i32 {
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

pub fn send_route_del_req(fd: i32, kern_addr: linux.sockaddr.nl, info: RouteInfo) !void {
    var offset: usize = 0;
    var buf: [512]u8 = undefined;

    var nlh = c.nlmsghdr{
        .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_DELROUTE)),
        .nlmsg_flags = c.NLM_F_REQUEST,
        .nlmsg_len = @sizeOf(c.nlmsghdr) + @sizeOf(c.rtmsg),
        .nlmsg_seq = @intCast(std.time.timestamp()),
    };
    const rtm = c.rtmsg{ .rtm_family = linux.AF.INET, .rtm_table = c.RT_TABLE_MAIN, .rtm_protocol = c.RTPROT_STATIC, .rtm_scope = c.RT_SCOPE_UNIVERSE, .rtm_type = c.RTN_UNICAST, .rtm_dst_len = 32 };

    @memcpy(buf[offset .. offset + @sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));
    offset += @sizeOf(c.nlmsghdr);

    @memcpy(buf[offset .. offset + @sizeOf(c.rtmsg)], std.mem.asBytes(&rtm));
    offset += @sizeOf(c.rtmsg);

    if (info.dst) |dst| add_rtattr(&buf, &offset, c.RTA_DST, std.mem.asBytes(&dst));
    if (info.gw) |gw| add_rtattr(&buf, &offset, c.RTA_GATEWAY, std.mem.asBytes(&gw));
    if (info.oif) |oif| add_rtattr(&buf, &offset, c.RTA_OIF, std.mem.asBytes(&oif));
    if (info.metric) |metric| add_rtattr(&buf, &offset, c.RTA_PRIORITY, std.mem.asBytes(&metric));

    // need to do this because the memcpy above was just a dummy header to reserver space
    // this gives the real size
    nlh.nlmsg_len = @intCast(offset);
    @memcpy(buf[0..@sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));

    const sent = linux.sendto(@intCast(fd), &buf, offset, 0, @ptrCast(&kern_addr), @sizeOf(@TypeOf(kern_addr)));
    if (sent < 0) return error.SendFailed;
}

pub fn send_route_add_req(fd: i32, kern_addr: linux.sockaddr.nl, info: RouteInfo) !void {
    var offset: usize = 0;
    var buf: [512]u8 = undefined;

    var nlh = c.nlmsghdr{
        .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_NEWROUTE)),
        .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_CREATE | c.NLM_F_EXCL,
        .nlmsg_len = @sizeOf(c.nlmsghdr) + @sizeOf(c.rtmsg),
        .nlmsg_seq = @intCast(std.time.timestamp()),
    };
    const rtm = c.rtmsg{ .rtm_family = linux.AF.INET, .rtm_table = c.RT_TABLE_MAIN, .rtm_protocol = c.RTPROT_STATIC, .rtm_scope = c.RT_SCOPE_UNIVERSE, .rtm_type = c.RTN_UNICAST, .rtm_dst_len = 32 };

    @memcpy(buf[offset .. offset + @sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));
    offset += @sizeOf(c.nlmsghdr);

    @memcpy(buf[offset .. offset + @sizeOf(c.rtmsg)], std.mem.asBytes(&rtm));
    offset += @sizeOf(c.rtmsg);

    if (info.dst) |dst| add_rtattr(&buf, &offset, c.RTA_DST, std.mem.asBytes(&dst));
    if (info.gw) |gw| add_rtattr(&buf, &offset, c.RTA_GATEWAY, std.mem.asBytes(&gw));
    if (info.oif) |oif| add_rtattr(&buf, &offset, c.RTA_OIF, std.mem.asBytes(&oif));
    if (info.metric) |metric| add_rtattr(&buf, &offset, c.RTA_PRIORITY, std.mem.asBytes(&metric));

    // need to do this because the memcpy above was just a dummy header to reserver space
    // this gives the real size
    nlh.nlmsg_len = @intCast(offset);
    @memcpy(buf[0..@sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));

    const sent = linux.sendto(@intCast(fd), &buf, offset, 0, @ptrCast(&kern_addr), @sizeOf(@TypeOf(kern_addr)));
    if (sent < 0) return error.SendFailed;
}

fn add_rtattr(buf: []u8, offset: *usize, rta_type: c_ushort, data: []const u8) void {
    const rta = c.rtattr{
        .rta_type = rta_type,
        .rta_len = @intCast(@sizeOf(c.rtattr) + data.len),
    };

    @memcpy(buf[offset.* .. offset.* + @sizeOf(c.rtattr)], std.mem.asBytes(&rta));
    offset.* += @sizeOf(c.rtattr);

    @memcpy(buf[offset.* .. offset.* + data.len], data);
    offset.* += data.len;

    // TODO: do we need to do this?
    offset.* = std.mem.alignForward(usize, offset.*, 4);
}

/// sendto takes ?*const sockaddr
/// recvfrom takes ?* sockaddr
/// this is why we pass by value not by pointer
pub fn send_route_dump_req(fd: i32, kern_addr: linux.sockaddr.nl) !void {
    var buf: [@sizeOf(c.nlmsghdr) + @sizeOf(c.rtmsg)]u8 = undefined;
    var offset: usize = 0;

    const nlh = c.nlmsghdr{
        .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_GETROUTE)),
        .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_DUMP,
        .nlmsg_len = @sizeOf(c.nlmsghdr) + @sizeOf(c.rtmsg),
        .nlmsg_seq = @intCast(std.time.timestamp()),
        .nlmsg_pid = 0,
    };
    const rtm = c.rtmsg{ .rtm_family = linux.AF.INET, .rtm_table = c.RT_TABLE_MAIN };

    @memcpy(buf[offset .. offset + @sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));
    offset += @sizeOf(c.nlmsghdr);

    @memcpy(buf[offset .. offset + @sizeOf(c.rtmsg)], std.mem.asBytes(&rtm));
    offset += @sizeOf(c.rtmsg);

    const sent = linux.sendto(@intCast(fd), &buf, buf.len, 0, @ptrCast(&kern_addr), @sizeOf(@TypeOf(kern_addr)));
    if (sent < 0) return error.SendFailed;
}
