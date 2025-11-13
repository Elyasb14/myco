const std = @import("std");
const linux = std.os.linux;

pub fn send(fd: i32, msg: []const u8, addr: *const linux.sockaddr.nl) !void {
    if (linux.sendto(fd, msg.ptr, msg.len, 0, @ptrCast(addr), @sizeOf(@TypeOf(addr.*))) < 0)
        return error.SendFailed;
}

pub fn recv(fd: i32, buf: []u8, addr: *linux.sockaddr.nl) !usize {
    var len: linux.socklen_t = @sizeOf(linux.sockaddr.nl);
    const n = linux.recvfrom(fd, buf.ptr, buf.len, 0, @ptrCast(addr), &len);
    if (n < 0) return error.RecvFailed;
    return @intCast(n);
}
