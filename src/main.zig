const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const c = @cImport(@cInclude("linux/rtnetlink.h"));

const nl_request = struct {
    nlh: c.nlmsghdr,
    rtm: c.rtmsg,
};

fn get_route_dump_resp(fd: i32, kern_addr: *linux.sockaddr.nl) !void {
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
        if (len < 0) return error.RecvFailed;
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
                const rtm: *const c.rtmsg = @ptrCast(@alignCast(@as(*const anyopaque, @ptrFromInt(@intFromPtr(hdr) + @sizeOf(c.nlmsghdr)))));
                const attr_start = @intFromPtr(rtm) + @sizeOf(c.rtmsg);
                const attr_len = hdr.nlmsg_len - @sizeOf(c.nlmsghdr) - @sizeOf(c.rtmsg);

                const attr_buf = buf[@intCast(attr_start - @intFromPtr(&buf))..@intCast(attr_start - @intFromPtr(&buf) + attr_len)];

                parse_rtattrs(attr_buf);
            }

            offset += @intCast(c.NLMSG_ALIGN(hdr.nlmsg_len));
        }
    }
}

fn parse_rtattrs(buf: []const u8) void {
    var offset: usize = 0;
    const attr_align = @sizeOf(u32); // usually 4
    while (offset + @sizeOf(c.rtattr) <= buf.len) {
        const rta: *const c.rtattr = @ptrCast(@alignCast(&buf[offset]));
        if (rta.rta_len == 0) break;

        const data_len: usize = @as(usize, @intCast(rta.rta_len)) - @sizeOf(c.rtattr);
        const data = buf[offset + @sizeOf(c.rtattr) .. offset + @sizeOf(c.rtattr) + data_len];

        switch (rta.rta_type) {
            c.RTA_DST => {
                if (data_len == 4) {
                    const ip: *const [4]u8 = @as(*const [4]u8, @ptrCast(data.ptr));
                    std.debug.print("  dst: {d}.{d}.{d}.{d}\n", .{ ip[0], ip[1], ip[2], ip[3] });
                }
            },
            c.RTA_GATEWAY => {
                if (data_len == 4) {
                    const ip: *const [4]u8 = @as(*const [4]u8, @ptrCast(data.ptr));
                    std.debug.print("  gw:  {d}.{d}.{d}.{d}\n", .{ ip[0], ip[1], ip[2], ip[3] });
                }
            },
            c.RTA_OIF => {
                if (data_len >= 4) {
                    const ifindex = std.mem.readInt(u32, @ptrCast(data), .little);
                    std.debug.print("  oif: {d}\n", .{ifindex});
                }
            },
            else => {},
        }

        const aligned_len = (@as(usize, rta.rta_len) + attr_align - 1) & ~(@as(usize, attr_align - 1));
        offset += aligned_len;
    }
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

fn do_route_dump_req(fd: i32, kern_addr: linux.sockaddr.nl) void {
    const req = nl_request{ .nlh = .{
        .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_GETROUTE)),
        .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_DUMP,
        .nlmsg_len = @sizeOf(nl_request),
        .nlmsg_seq = @intCast(std.time.timestamp()),
    }, .rtm = .{ .rtm_family = linux.AF.INET, .rtm_table = c.RT_TABLE_MAIN } };

    const sent = linux.sendto(@intCast(fd), std.mem.asBytes(&req), req.nlh.nlmsg_len, 0, @ptrCast(&kern_addr), @sizeOf(@TypeOf(kern_addr)));
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

    do_route_dump_req(fd, kern_addr);

    try get_route_dump_resp(fd, &kern_addr);
}
