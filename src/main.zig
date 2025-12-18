const std = @import("std");
const nl = @import("netlink");
const dsl = @import("dsl");
const linux = std.os.linux;
const Allocator = std.mem.Allocator;

pub fn apply_config(allocator: Allocator, path: []const u8) !void {
    var buf: [8192]u8 = undefined;
    const contents = try std.fs.cwd().readFile(path, &buf);

    var lexer = dsl.Lexer.init(allocator, contents);
    const tokens = try lexer.tokenize();

    const blocks = try dsl.parse_tokens(allocator, tokens);

    const nl_sock = try nl.NetlinkSocket.open(allocator, linux.NETLINK.ROUTE);
    defer nl_sock.close();

    for (blocks) |block| {
        switch (block.type) {
            .LINK => {
                const info = nl.LinkInfo{ .ifname = block.name, .kind = "wireguard", .mtu = 12 };

                for (block.pairs) |pair| {
                    switch (pair.value) {
                        .Addr => {
                            try nl_sock.add_link(info);

                            // linux stores the name as null terminated
                            // we need to cast our name to be null terminated
                            const c_block_name = try allocator.dupeZ(u8, info.ifname);
                            const ifindex = try nl.c_nametoifindex(allocator, c_block_name);
                            if (ifindex == 0) return error.InterfaceNotFound;

                            const addr = nl.AddrInfo{
                                .if_index = ifindex,
                                .prefix_len = pair.value.Addr[8].Number,
                                .address = .{
                                    pair.value.Addr[0].Number,
                                    pair.value.Addr[2].Number,
                                    pair.value.Addr[4].Number,
                                    pair.value.Addr[6].Number,
                                },
                            };

                            try nl_sock.assign_idx_ip(ifindex, addr);
                            try nl_sock.enable_link(info);
                        },
                        // .Ident => {
                        //     if (std.mem.eql(pair.key, "type")) {}
                        // },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
}
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try apply_config(allocator, "src/dsl/config.myco");
}
