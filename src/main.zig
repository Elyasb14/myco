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
                var link = nl.LinkInfo{ .ifname = block.name };

                for (block.pairs) |pair| {
                    if (std.mem.eql(u8, pair.key, "kind") and pair.value == dsl.Value.Ident) {
                        link.kind = pair.value.Ident;
                    }
                }

                try nl_sock.add_link(link);

                const c_name = try allocator.dupeZ(u8, link.ifname);
                const ifindex = try nl.c_nametoifindex(allocator, c_name);
                if (ifindex == 0) return error.InterfaceNotFound;

                try nl_sock.enable_link(ifindex);

                // 5. Assign IPs
                for (block.pairs) |pair| {
                    switch (pair.value) {
                        .Addr => {
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
                        },
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
