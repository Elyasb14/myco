const std = @import("std");
const nl = @import("netlink");
const conf = @import("config");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // const tokens = try conf.Config.tokenize(allocator, "src/config.myco");
    var buf: []u8 = undefined;
    const contents = try std.fs.cwd().readFile("src/config.myco", &buf);

    const tokens = conf.Lexer.init(allocator, contents).tokenize();
    try conf.Config.parse(allocator, tokens);
}
