const std = @import("std");
const nl = @import("netlink");

pub fn read_script(file_path: []const u8) !void {
    var buf: [8192]u8 = undefined;

    const file = try std.fs.cwd().readFile(file_path, &buf);

    var lines = std.mem.splitAny(u8, file, "\n");

    while (lines.next()) |line| {
        std.debug.print("line: {s}\n", .{line});
    }
}
