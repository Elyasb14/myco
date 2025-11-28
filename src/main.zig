const std = @import("std");
const nl = @import("netlink");
const dsl = @import("dsl");

pub fn main() !void {
    try dsl.read_script("src/config.myco");
}
