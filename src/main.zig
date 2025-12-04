const std = @import("std");
const nl = @import("netlink");
const conf = @import("config");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buf: [8192]u8 = undefined;
    const contents = try std.fs.cwd().readFile("src/config.myco", &buf);

    var lexer = conf.Lexer.init(allocator, contents);
    const tokens = try lexer.tokenize();

    const block = try conf.parse_block(tokens);
    std.debug.print("BLOCK: {any}\n", .{block});
}
