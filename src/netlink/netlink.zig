//! netlink abstraction
//! https://man.archlinux.org/man/rtnetlink.7.en
//! https://man7.org/linux/man-pages/man3/libnetlink.3.html
//! https://www.netfilter.org/projects/libmnl/index.html

const std = @import("std");
const linux = std.os.linux;
const sys = @import("system.zig");

const c = @cImport({
    @cInclude("linux/rtnetlink.h");
    // @cInclude("linux/if.h");
    @cInclude("net/if.h");
    @cInclude("linux/netlink.h");
});

pub const NetlinkError = error{ NEED_SUDO, NO_EXISTS, EXISTS, UNKNOWN, NO_DATA, ADDR_NOT_AVAIL, TOOBIG, OP_NOT_SUPPORTED, NODEV };

const NlMsgErr = extern struct {
    @"error": i32,
    msg: c.nlmsghdr,
};

pub const LinkInfo = struct {
    name: []const u8,
    kind: []const u8,
};

pub const AddrInfo = struct {
    if_index: u32, // interface index
    family: u8 = c.AF_INET,
    prefix_len: u8, // subnet mask
    address: [4]u8, // full address

};

/// oif: output interface index
pub const RouteInfo = struct {
    dst: ?[4]u8 = null,
    gw: ?[4]u8 = null,
    oif: ?u32 = null,
    prefsrc: ?[4]u8 = null,
    metric: ?u32 = null,
};

pub const NetlinkSocket = struct {
    nl_sock: i32,
    kern_addr: linux.sockaddr.nl,

    pub fn open(protocol: u32) !NetlinkSocket {
        const sock: i32 = @intCast(linux.socket(linux.AF.NETLINK, linux.SOCK.RAW, protocol));

        const kern_addr = linux.sockaddr.nl{
            .family = linux.AF.NETLINK,
            .pid = 0, // destination: kernel
            .groups = 0,
        };

        const addr: linux.sockaddr.nl = .{
            .family = linux.AF.NETLINK,
            .pid = @intCast(linux.getpid()),
            .groups = 0,
        };

        if (linux.bind(@intCast(sock), @ptrCast(&addr), @sizeOf(@TypeOf(addr))) < 0) {
            return error.CantBind;
        }
        return NetlinkSocket{ .nl_sock = sock, .kern_addr = kern_addr };
    }

    pub fn close(sock: NetlinkSocket) void {
        _ = linux.close(@intCast(sock.nl_sock));
    }

    pub fn add_link(nl_sock: NetlinkSocket, info: LinkInfo) !void {
        var buf: [512]u8 = undefined;
        var offset: usize = 0;

        var nlh = c.nlmsghdr{
            .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_NEWLINK)),
            .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_CREATE | c.NLM_F_ACK,
            .nlmsg_len = @sizeOf(c.nlmsghdr) + @sizeOf(c.ifinfomsg),
            .nlmsg_seq = @intCast(std.time.timestamp()),
        };

        const ifimsg = c.ifinfomsg{}; // default zero values are fine for now

        @memcpy(buf[offset .. offset + @sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));
        offset += @sizeOf(c.nlmsghdr);

        @memcpy(buf[offset .. offset + @sizeOf(c.ifinfomsg)], std.mem.asBytes(&ifimsg));
        offset += @sizeOf(c.ifinfomsg);

        add_rtattr(&buf, &offset, c.IFLA_IFNAME, info.name); // interface name

        const nested_start = add_rtattr_nested_start(&buf, &offset, c.IFLA_LINKINFO);
        add_rtattr(&buf, &offset, c.IFLA_INFO_KIND, info.kind);
        add_rtattr_nested_end(&buf, nested_start, &offset);

        nlh.nlmsg_len = @intCast(offset);
        @memcpy(buf[0..@sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));

        try sys.send(@intCast(nl_sock.nl_sock), buf[0..offset], &nl_sock.kern_addr);
        recv_ack(nl_sock.nl_sock, &nl_sock.kern_addr) catch |err| switch (err) {
            NetlinkError.OP_NOT_SUPPORTED => {
                std.log.err("\x1b[31mlink type not supported\x1b[0m: {s}", .{info.kind});
                return err;
            },
            else => return err,
        };
    }

    pub fn del_link(nl_sock: NetlinkSocket, info: LinkInfo) !void {
        var buf: [512]u8 = undefined;
        var offset: usize = 0;

        var nlh = c.nlmsghdr{
            .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_DELLINK)),
            .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_ACK,
            .nlmsg_len = @sizeOf(c.nlmsghdr) + @sizeOf(c.ifinfomsg),
            .nlmsg_seq = @intCast(std.time.timestamp()),
        };

        const ifimsg = c.ifinfomsg{}; // default zero values are fine for now

        @memcpy(buf[offset .. offset + @sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));
        offset += @sizeOf(c.nlmsghdr);

        @memcpy(buf[offset .. offset + @sizeOf(c.ifinfomsg)], std.mem.asBytes(&ifimsg));
        offset += @sizeOf(c.ifinfomsg);

        add_rtattr(&buf, &offset, c.IFLA_IFNAME, info.name); // interface name

        const nested_start = add_rtattr_nested_start(&buf, &offset, c.IFLA_LINKINFO);
        add_rtattr(&buf, &offset, c.IFLA_INFO_KIND, info.kind);
        add_rtattr_nested_end(&buf, nested_start, &offset);

        nlh.nlmsg_len = @intCast(offset);
        @memcpy(buf[0..@sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));

        try sys.send(@intCast(nl_sock.nl_sock), buf[0..offset], &nl_sock.kern_addr);
        recv_ack(nl_sock.nl_sock, &nl_sock.kern_addr) catch |err| switch (err) {
            NetlinkError.NODEV => {
                std.log.err("\x1b[31mno such device name\x1b[0m: {s}", .{info.name});
                return err;
            },
            else => return err,
        };
    }

    pub fn dump_links(nl_sock: NetlinkSocket, out: []u8) void {
        _ = out;
        var buf: [@sizeOf(c.nlmsghdr) + @sizeOf(c.ifinfomsg)]u8 = undefined;
        var offset: usize = 0;

        const nlh = c.nlmsghdr{
            .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_GETLINK)),
            .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_DUMP,
            .nlmsg_len = @sizeOf(c.nlmsghdr) + @sizeOf(c.rtmsg),
            .nlmsg_seq = @intCast(std.time.timestamp()),
            .nlmsg_pid = 0,
        };
        const ifimsg = c.ifinfomsg{};

        @memcpy(buf[0..@sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));
        offset += @sizeOf(c.nlmsghdr);

        @memcpy(buf[offset .. offset + @sizeOf(c.ifinfomsg)], std.mem.asBytes(&ifimsg));
        offset += @sizeOf(c.ifinfomsg);

        try sys.send(@intCast(nl_sock.nl_sock), buf[0..offset], @ptrCast(&nl_sock.kern_addr));
    }

    pub fn add_route(nl_sock: NetlinkSocket, info: RouteInfo) !void {
        var offset: usize = 0;
        var buf: [512]u8 = undefined;

        var nlh = c.nlmsghdr{
            .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_NEWROUTE)),
            .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_CREATE | c.NLM_F_ACK,
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

        try sys.send(@intCast(nl_sock.nl_sock), buf[0..offset], &nl_sock.kern_addr);
        recv_ack(nl_sock.nl_sock, &nl_sock.kern_addr) catch |err| switch (err) {
            NetlinkError.ADDR_NOT_AVAIL => {
                std.log.err("\x1b[31mgateway or dst addr not availabe to add route...\x1b[0m gw: {any}, dst: {any}", .{ info.gw.?, info.dst.? });
                return err;
            },
            else => return err,
        };
    }

    /// need to add proper error handling here for when we delete a route we don't need to delete
    pub fn del_route(nl_sock: NetlinkSocket, info: RouteInfo) !void {
        var offset: usize = 0;
        var buf: [512]u8 = undefined;

        var nlh = c.nlmsghdr{
            .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_DELROUTE)),
            .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_ACK,
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

        try sys.send(@intCast(nl_sock.nl_sock), buf[0..offset], @ptrCast(&nl_sock.kern_addr));
        recv_ack(nl_sock.nl_sock, &nl_sock.kern_addr) catch |err| switch (err) {
            NetlinkError.ADDR_NOT_AVAIL => {
                std.log.err("\x1b[31mgateway or dst addr not availabe to del route...\x1b[0m gw: {any}, dst: {any}", .{ info.gw.?, info.dst.? });
                return err;
            },

            NetlinkError.NO_EXISTS => {
                std.log.err("\x1b[31mno such route exists to delete...\x1b[0m gw: {any}, dst: {any}", .{ info.gw.?, info.dst.? });
                return err;
            },
            else => return err,
        };
    }

    pub fn dump_routing_table(nl_sock: NetlinkSocket, out: []RouteInfo) !usize {
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

        try sys.send(@intCast(nl_sock.nl_sock), buf[0..offset], @ptrCast(&nl_sock.kern_addr));
        return try fill_route_buf(nl_sock.nl_sock, &nl_sock.kern_addr, out);
    }

    pub fn dump_addresses(nl_sock: NetlinkSocket, out: []AddrInfo) !usize {
        var buf: [8192]u8 = undefined;
        var count: usize = 0;

        // Prepare the netlink header
        var nlh = c.nlmsghdr{
            .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_GETADDR)),
            .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_DUMP,
            .nlmsg_len = @sizeOf(c.nlmsghdr) + @sizeOf(c.ifaddrmsg),
            .nlmsg_seq = @intCast(std.time.timestamp()),
            .nlmsg_pid = 0,
        };

        var ifa = c.ifaddrmsg{
            .ifa_family = c.AF_INET,
            .ifa_prefixlen = 0,
            .ifa_flags = 0,
            .ifa_scope = 0,
            .ifa_index = 0,
        };

        var offset: usize = 0;
        @memcpy(buf[offset .. offset + @sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));
        offset += @sizeOf(c.nlmsghdr);
        @memcpy(buf[offset .. offset + @sizeOf(c.ifaddrmsg)], std.mem.asBytes(&ifa));
        offset += @sizeOf(c.ifaddrmsg);

        try sys.send(@intCast(nl_sock.nl_sock), buf[0..offset], @ptrCast(&nl_sock.kern_addr));

        while (true) {
            const len = try sys.recv(nl_sock.nl_sock, &buf, &nl_sock.kern_addr);
            if (len == 0) break;

            var off: usize = 0;
            while (off < len) {
                const hdr: *const c.nlmsghdr = @ptrCast(@alignCast(&buf[off]));

                if (hdr.nlmsg_type == c.NLMSG_DONE) return count;
                if (hdr.nlmsg_type == c.NLMSG_ERROR) return error.UnknownNetlinkError;
                if (hdr.nlmsg_type == c.RTM_NEWADDR) {
                    const if_addr_buf_ptr: *const anyopaque = @ptrFromInt(@intFromPtr(hdr) + @sizeOf(c.nlmsghdr));
                    const ifa_msg: *const c.ifaddrmsg = @ptrCast(@alignCast(if_addr_buf_ptr));

                    const attr_start = @intFromPtr(ifa_msg) + @sizeOf(c.ifaddrmsg);
                    const attr_len = hdr.nlmsg_len - @sizeOf(c.nlmsghdr) - @sizeOf(c.ifaddrmsg);
                    const attr_buf = buf[@intCast(attr_start - @intFromPtr(&buf))..@intCast(attr_start - @intFromPtr(&buf) + attr_len)];

                    var addr = parse_addr_attrs(attr_buf);
                    addr.if_index = ifa_msg.ifa_index;
                    addr.family = ifa_msg.ifa_family;
                    addr.prefix_len = ifa_msg.ifa_prefixlen;

                    out[count] = addr;
                    count += 1;
                }

                off += @intCast(c.NLMSG_ALIGN(hdr.nlmsg_len));
            }
        }
        return count;
    }

    pub fn add_addr(nl_sock: NetlinkSocket, addr: AddrInfo) !void {
        var offset: usize = 0;
        var buf: [512]u8 = undefined;

        var nlh = c.nlmsghdr{
            .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_NEWADDR)),
            .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_ACK | c.NLM_F_CREATE | c.NLM_F_REPLACE,
            .nlmsg_len = @sizeOf(c.nlmsghdr) + @sizeOf(c.ifaddrmsg),
            .nlmsg_seq = @intCast(std.time.timestamp()),
        };

        const ifa = c.ifaddrmsg{
            .ifa_family = addr.family,
            .ifa_prefixlen = addr.prefix_len,
            .ifa_flags = 0,
            .ifa_scope = c.RT_SCOPE_UNIVERSE,
            .ifa_index = addr.if_index,
        };

        @memcpy(buf[offset .. offset + @sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));
        offset += @sizeOf(c.nlmsghdr);

        @memcpy(buf[offset .. offset + @sizeOf(c.ifaddrmsg)], std.mem.asBytes(&ifa));
        offset += @sizeOf(c.ifaddrmsg);

        add_rtattr(&buf, &offset, c.IFA_LOCAL, &addr.address);
        add_rtattr(&buf, &offset, c.IFA_ADDRESS, &addr.address);

        nlh.nlmsg_len = @intCast(offset);
        @memcpy(buf[0..@sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));

        try sys.send(@intCast(nl_sock.nl_sock), buf[0..offset], @ptrCast(&nl_sock.kern_addr));
        try recv_ack(nl_sock.nl_sock, &nl_sock.kern_addr);
    }

    pub fn del_addr(nl_sock: NetlinkSocket, addr: AddrInfo) !void {
        var offset: usize = 0;
        var buf: [512]u8 = undefined;

        var nlh = c.nlmsghdr{
            .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_DELADDR)),
            .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_ACK,
            .nlmsg_len = @sizeOf(c.nlmsghdr) + @sizeOf(c.ifaddrmsg),
            .nlmsg_seq = @intCast(std.time.timestamp()),
        };

        const ifa = c.ifaddrmsg{
            .ifa_family = addr.family,
            .ifa_prefixlen = addr.prefix_len,
            .ifa_flags = 0,
            .ifa_scope = c.RT_SCOPE_UNIVERSE,
            .ifa_index = addr.if_index,
        };

        @memcpy(buf[offset .. offset + @sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));
        offset += @sizeOf(c.nlmsghdr);

        @memcpy(buf[offset .. offset + @sizeOf(c.ifaddrmsg)], std.mem.asBytes(&ifa));
        offset += @sizeOf(c.ifaddrmsg);

        add_rtattr(&buf, &offset, c.IFA_LOCAL, &addr.address);
        add_rtattr(&buf, &offset, c.IFA_ADDRESS, &addr.address);

        nlh.nlmsg_len = @intCast(offset);
        @memcpy(buf[0..@sizeOf(c.nlmsghdr)], std.mem.asBytes(&nlh));

        try sys.send(@intCast(nl_sock.nl_sock), buf[0..offset], @ptrCast(&nl_sock.kern_addr));
        try recv_ack(nl_sock.nl_sock, &nl_sock.kern_addr);
    }
};

/// if ack is successful, we return void
/// else, return NetlinkError
fn recv_ack(sock: i32, kern_addr: *const linux.sockaddr.nl) NetlinkError!void {
    var buf: [8192]u8 = undefined;
    const len = try sys.recv(sock, &buf, kern_addr);
    if (len == 0) return NetlinkError.NO_DATA;

    var offset: usize = 0;

    while (offset < len) {
        const hdr: *const c.nlmsghdr = @ptrCast(@alignCast(&buf));

        switch (hdr.nlmsg_type) {
            c.NLMSG_ERROR => {
                const err_buf_ptr: *const anyopaque = @ptrFromInt(@intFromPtr(hdr) + @sizeOf(c.nlmsghdr));
                const err_ptr: *const NlMsgErr = @ptrCast(@alignCast(err_buf_ptr));

                if (err_ptr.@"error" == 0) return;
                try sys.map_err(err_ptr.@"error");

                return NetlinkError.UNKNOWN;
            },
            c.NLMSG_DONE => return,
            else => {},
        }

        offset += c.NLMSG_ALIGN(hdr.nlmsg_len);
    }
    return NetlinkError.UNKNOWN;
}

fn fill_route_buf(sock: i32, kern_addr: *const linux.sockaddr.nl, out: []RouteInfo) NetlinkError!usize {
    var buf: [8192]u8 = undefined;
    var route_count: usize = 0;

    while (true) {
        const len = try sys.recv(sock, &buf, kern_addr);
        if (len == 0) break;

        var offset: usize = 0;
        while (offset < len) {
            const hdr: *const c.nlmsghdr = @ptrCast(@alignCast(&buf[offset]));

            if (hdr.nlmsg_type == c.NLMSG_DONE) {
                return route_count;
            } else if (hdr.nlmsg_type == c.NLMSG_ERROR) {
                const err_buf_ptr: *const anyopaque = @ptrFromInt(@intFromPtr(hdr) + @sizeOf(c.nlmsghdr));
                const err_ptr: *const NlMsgErr = @ptrCast(@alignCast(err_buf_ptr));
                if (err_ptr.@"error" == 0) return route_count;
                try sys.map_err(err_ptr.@"error");
                return NetlinkError.UNKNOWN;
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
                const route_info = parse_route_attrs(attr_buf);
                out[route_count] = route_info;
                route_count += 1;
            }

            offset += @intCast(c.NLMSG_ALIGN(hdr.nlmsg_len));
        }
    }
    return route_count;
}

fn parse_route_attrs(buf: []u8) RouteInfo {
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

fn add_rtattr(buf: []u8, offset: *usize, rta_type: c_ushort, data: []const u8) void {
    const rta = c.rtattr{
        .rta_type = rta_type,
        .rta_len = @intCast(@sizeOf(c.rtattr) + data.len),
    };

    @memcpy(buf[offset.* .. offset.* + @sizeOf(c.rtattr)], std.mem.asBytes(&rta));
    offset.* += @sizeOf(c.rtattr);

    @memcpy(buf[offset.* .. offset.* + data.len], data);
    offset.* += data.len;

    offset.* = std.mem.alignForward(usize, offset.*, 4);
}

fn parse_addr_attrs(buf: []u8) AddrInfo {
    var offset: usize = 0;
    var info = AddrInfo{
        .if_index = 0,
        .prefix_len = 0,
        .address = .{ 0, 0, 0, 0 },
    };

    while (offset + @sizeOf(c.rtattr) <= buf.len) {
        const rta: *const c.rtattr = @ptrCast(@alignCast(&buf[offset]));
        if (rta.rta_len == 0) break;

        const data_len = @as(usize, @intCast(rta.rta_len)) - @sizeOf(c.rtattr);
        const data = buf[offset + @sizeOf(c.rtattr) .. offset + @sizeOf(c.rtattr) + data_len];

        switch (rta.rta_type) {
            c.IFA_ADDRESS, c.IFA_LOCAL => {
                if (data_len == 4)
                    info.address = @as(*const [4]u8, @ptrCast(data.ptr)).*;
            },
            else => {},
        }

        offset += @intCast(c.RTA_ALIGN(rta.rta_len));
    }
    return info;
}

fn add_rtattr_nested_start(buf: []u8, offset: *usize, rta_type: c.ushort) usize {
    const start = offset.*;
    const rta = c.rtattr{
        .rta_len = @intCast(@sizeOf(c.rtattr)), // temp, will patch later
        .rta_type = rta_type | @as(c.ushort, @intCast(c.NLA_F_NESTED)),
    };
    @memcpy(buf[offset.* .. offset.* + @sizeOf(c.rtattr)], std.mem.asBytes(&rta));
    offset.* += @sizeOf(c.rtattr);
    return start;
}

fn add_rtattr_nested_end(buf: []u8, start: usize, offset: *usize) void {
    const len = offset.* - start;
    const rta: *c.rtattr = @ptrCast(@alignCast(&buf[start]));
    rta.rta_len = @intCast(len);
}
