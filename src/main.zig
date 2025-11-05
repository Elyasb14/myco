const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const c = @cImport(@cInclude("linux/rtnetlink.h"));

const nl_request = struct {
    nlh: c.nlmsghdr,
    rtm: c.rtmsg,
};

fn get_route_dump_resp(fd: i32, buf: []u8, kern_addr: *linux.sockaddr) !void {
    var from_len: linux.socklen_t = @sizeOf(linux.sockaddr.nl);
    while (true) {
        const len = linux.recvfrom(
            fd,
            @ptrCast(buf),
            buf.len,
            0,
            kern_addr,
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
                std.debug.print("Got RTM_NEWROUTE message (len {d})\n", .{hdr.nlmsg_len});
            }

            offset += @intCast(c.NLMSG_ALIGN(hdr.nlmsg_len));
        }
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

    var buf: [8192]u8 = undefined;
    try get_route_dump_resp(fd, &buf, @ptrCast(&kern_addr));
}
