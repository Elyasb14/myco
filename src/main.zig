const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

const c = @cImport(@cInclude("linux/rtnetlink.h"));

const nl_request = struct {
    nlh: c.nlmsghdr,
    rtm: c.rtmsg,
};

pub fn main() !void {
    const fd = linux.socket(linux.AF.NETLINK, linux.SOCK.RAW, linux.NETLINK.ROUTE);
    defer _ = linux.close(@intCast(fd));

    const addr: linux.sockaddr.nl = .{
        .family = linux.AF.NETLINK,
        .pid = @intCast(linux.getpid()),
        .groups = 0,
    };

    const kern_addr = linux.sockaddr.nl{
        .family = linux.AF.NETLINK,
        .pid = 0, // destination: kernel
        .groups = 0,
    };

    if (linux.bind(@intCast(fd), @ptrCast(&addr), @sizeOf(@TypeOf(addr))) < 0) {
        return error.CantBind;
    }
    // linux.NetlinkMessageType.RTM_GETROUTE

    const req = nl_request{ .nlh = .{
        .nlmsg_type = @intCast(@intFromEnum(linux.NetlinkMessageType.RTM_GETROUTE)),
        .nlmsg_flags = c.NLM_F_REQUEST | c.NLM_F_DUMP,
        .nlmsg_len = @sizeOf(nl_request),
        .nlmsg_seq = @intCast(std.time.timestamp()),
    }, .rtm = .{ .rtm_family = linux.AF.INET, .rtm_table = c.RT_TABLE_MAIN } };

    const sent = linux.sendto(@intCast(fd), std.mem.asBytes(&req), req.nlh.nlmsg_len, 0, @ptrCast(&kern_addr), @sizeOf(@TypeOf(kern_addr)));

    std.debug.print("sent: {d}\n", .{sent});
}
