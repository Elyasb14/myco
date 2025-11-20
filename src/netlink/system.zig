const std = @import("std");
const linux = std.os.linux;
const nl = @import("netlink.zig");

pub fn send(fd: i32, msg: []const u8, addr: *const linux.sockaddr.nl) !void {
    if (linux.sendto(fd, msg.ptr, msg.len, 0, @ptrCast(addr), @sizeOf(@TypeOf(addr.*))) < 0)
        return error.SendFailed;
}

pub fn recv(fd: i32, buf: []u8, addr: *const linux.sockaddr.nl) !usize {
    var len: linux.socklen_t = @sizeOf(linux.sockaddr.nl);
    const n = linux.recvfrom(fd, buf.ptr, buf.len, 0, @ptrCast(@constCast(addr)), &len);
    if (n < 0) return error.RecvFailed;
    return @intCast(n);
}

pub fn map_err(rc: i32) nl.NetlinkError!void {
    const e = std.posix.errno(rc);

    switch (e) {
        .PERM => return nl.NetlinkError.NEED_SUDO,
        .NOENT => return nl.NetlinkError.NO_EXISTS,
        .EXIST => return nl.NetlinkError.EXISTS,
        .ADDRNOTAVAIL => return nl.NetlinkError.ADDR_NOT_AVAIL,
        .RANGE => return nl.NetlinkError.TOOBIG,
        else => {
            std.debug.print("ERROR: {d}\n", .{rc});
            return nl.NetlinkError.UNKNOWN;
        },
    }
}
