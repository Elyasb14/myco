const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

// const c = @cImport(@cInclude("linux/rtnetlink.h"));

pub fn main() !void {
    const fd = linux.socket(linux.AF.NETLINK, linux.SOCK.RAW, linux.NETLINK.ROUTE);
    defer _ = linux.close(@intCast(fd));

    const addr: linux.sockaddr.nl = .{
        .family = linux.AF.NETLINK,
        .pid = @intCast(linux.getpid()),
        .groups = 0,
    };

    const kern_addr = linux.sockaddr_nl{
        .nl_family = linux.AF.NETLINK,
        .nl_pid = 0, // destination: kernel
        .nl_groups = 0,
    };

    _ = kern_addr;

    if (linux.bind(@intCast(fd), @ptrCast(&addr), @sizeOf(@TypeOf(addr))) < 0) {
        return error.CantBind;
    }
    linux.NetlinkMessageType.RTM_GETROUTE
    std.debug.print("addr: {any}\n", .{addr});
}
