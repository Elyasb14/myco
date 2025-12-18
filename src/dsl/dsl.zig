const std = @import("std");
const Allocator = std.mem.Allocator;
const linux = std.os.linux;

const Token = union(enum) {
    Ident: []const u8,
    String: []const u8,
    Number: u8,

    Dot,
    Slash,
    LBrace,
    RBrace,
    Eof,
};

pub const Lexer = struct {
    input: []const u8,
    index: usize = 0,
    allocator: Allocator,

    pub fn init(allocator: Allocator, input: []const u8) Lexer {
        return .{
            .input = input,
            .allocator = allocator,
        };
    }

    pub fn tokenize(self: *Lexer) ![]Token {
        var tokens = try std.ArrayList(Token).initCapacity(self.allocator, 1024);

        while (true) {
            const tok = try self.next();
            try tokens.append(self.allocator, tok);
            if (@intFromEnum(tok) == @intFromEnum(Token.Eof))
                break;
        }
        return try tokens.toOwnedSlice(self.allocator);
    }

    fn peek(self: *Lexer) ?u8 {
        if (self.index >= self.input.len) return null;
        return self.input[self.index];
    }

    fn advance(self: *Lexer) void {
        self.index += 1;
    }

    fn skip_whitespace(self: *Lexer) void {
        while (self.peek()) |c| {
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.advance();
            } else break;
        }
    }

    fn skip_comment(self: *Lexer) void {
        while (self.peek()) |c| {
            if (c == '\n') break;
            self.advance();
        }
    }

    fn read_ident(self: *Lexer) ![]const u8 {
        const start = self.index;

        while (self.peek()) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '_' or c == '-' or c == '.') {
                self.advance();
            } else break;
        }

        return self.input[start..self.index];
    }

    fn read_number(self: *Lexer) !u8 {
        const start = self.index;

        while (self.peek()) |c| {
            if (c >= '0' and c <= '9') {
                self.advance();
            } else break;
        }

        const slice = self.input[start..self.index];
        return try std.fmt.parseInt(u8, slice, 10);
    }

    pub fn next(self: *Lexer) !Token {
        self.skip_whitespace();

        if (self.peek() == null)
            return Token.Eof;

        const c = self.peek().?;

        if (c == '#') {
            self.advance();
            self.skip_comment();
            return self.next();
        }

        switch (c) {
            '{' => {
                self.advance();
                return Token.LBrace;
            },
            '}' => {
                self.advance();
                return Token.RBrace;
            },
            '.' => {
                self.advance();
                return Token.Dot;
            },
            '/' => {
                self.advance();
                return Token.Slash;
            },

            else => {},
        }

        if (std.ascii.isAlphabetic(c) or c == '_' or c == '-') {
            return Token{ .Ident = try self.read_ident() };
        }

        if (c >= '0' and c <= '9') {
            return Token{ .Number = try self.read_number() };
        }

        std.log.err("INVALID CHAR: {c}\n", .{c});
        return error.InvalidCharacter;
    }
};

pub const Value = union(enum) {
    String: []const u8,
    Number: i64,
    Ident: []const u8,
    Addr: []Token,
};

pub const Pair = struct {
    key: []const u8,
    value: Value,
};

pub const BlockType = enum(u8) { LINK, FW_RULE, ADDR };

/// e.g.
/// # type and name
/// link wg0 {
///    # pairs
///    address 192.168.1.1/24
///    up true
///    kind wireguard
/// }
pub const Block = struct {
    type: BlockType,
    name: []const u8,

    pairs: []Pair,
};

fn parse_block_type(token: Token) !BlockType {
    if (token != Token.Ident) {
        return error.TypeNEIdent;
    } else {
        if (std.mem.eql(u8, token.Ident, "link")) {
            return BlockType.LINK;
        } else if (std.mem.eql(u8, token.Ident, "fw_rule")) {
            return BlockType.FW_RULE;
        } else if (std.mem.eql(u8, token.Ident, "addr")) {
            return BlockType.ADDR;
        } else {
            std.log.err("invalid block type: {s}\n", .{token.Ident});
            return error.UnsupportedBlockType;
        }
    }
}

fn parse_block_name(token: Token) ![]const u8 {
    if (token != Token.Ident) {
        return error.TypeNEIdent;
    } else {
        return token.Ident;
    }
}

fn parse_pairs(allocator: Allocator, tokens: []Token) ![]Pair {
    var pairs = try std.ArrayList(Pair).initCapacity(allocator, 16);

    var i: usize = 0;
    while (i < tokens.len) {
        const key_tok = tokens[i];

        if (key_tok == .RBrace) break;
        if (i + 1 >= tokens.len) return error.UnexpectedEnd;

        // TODO: why do we do this
        if (tokens[i + 1] == .Number and tokens[i + 2] == .Dot) {
            const p = Pair{ .key = key_tok.Ident, .value = Value{ .Addr = tokens[i + 1 .. i + 10] } };
            try pairs.append(allocator, p);

            i += 10;
            continue;
        }

        const val_tok = tokens[i + 1];

        if (key_tok != .Ident) return error.ExpectedIdent;

        const value: Value = switch (val_tok) {
            .Number => Value{ .Number = val_tok.Number },
            .Ident => Value{ .Ident = val_tok.Ident },
            .String => Value{ .String = val_tok.String },
            else => return error.ExpectedIdentStringNumber,
        };

        const p = Pair{ .key = key_tok.Ident, .value = value };
        try pairs.append(allocator, p);

        i += 2;
    }

    return try pairs.toOwnedSlice(allocator);
}

fn parse_block(allocator: Allocator, tokens: []Token) !Block {
    var block = Block{ .type = .LINK, .name = "", .pairs = undefined };
    const blk_type = try parse_block_type(tokens[0]);
    const blk_name = try parse_block_name(tokens[1]);

    if (tokens[2] != .LBrace) {
        return error.ExpectedLBrace;
    }

    const pairs = try parse_pairs(allocator, tokens[3..]);

    block.name = blk_name;
    block.type = blk_type;
    block.pairs = pairs;
    return block;
}

fn split_blocks(allocator: Allocator, tokens: []Token) ![][]Token {
    var buf = try std.ArrayList([]Token).initCapacity(allocator, 1024);

    var start: usize = 0;

    for (tokens, 0..) |token, i| {
        switch (token) {
            .LBrace => {
                continue;
            },
            .RBrace => {
                try buf.append(allocator, tokens[start .. i + 1]);

                start = i + 1;
                continue;
            },
            else => {
                continue;
            },
        }
    }
    return buf.toOwnedSlice(allocator);
}

pub fn parse_tokens(allocator: Allocator, tokens: []Token) ![]Block {
    var block_container = try std.ArrayList(Block).initCapacity(allocator, 1024);

    const splitted = try split_blocks(allocator, tokens);

    for (splitted) |x| {
        const block = try parse_block(allocator, x);
        try block_container.append(allocator, block);
    }
    return block_container.toOwnedSlice(allocator);
}
