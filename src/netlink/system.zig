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
    switch (rc) {
        -1 => return nl.NetlinkError.NEED_SUDO,
        -3 => return nl.NetlinkError.NO_EXISTS,
        -17 => return nl.NetlinkError.EXISTS,
        -34 => return nl.NetlinkError.TOOBIG,
        -95 => return nl.NetlinkError.OP_NOT_SUPPORTED,
        -101 => return nl.NetlinkError.ADDR_NOT_AVAIL,
        else => {
            std.debug.print("ERROR: {any}\n", .{rc});
            return nl.NetlinkError.UNKNOWN;
        },
    }
}
