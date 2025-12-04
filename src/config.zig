const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Token = union(enum) {
    Ident: []const u8,
    String: []const u8,
    Number: i64,

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

    fn read_number(self: *Lexer) !i64 {
        const start = self.index;

        while (self.peek()) |c| {
            if (c >= '0' and c <= '9') {
                self.advance();
            } else break;
        }

        const slice = self.input[start..self.index];
        return try std.fmt.parseInt(i64, slice, 10);
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
};

pub const Pair = struct {
    key: []const u8,
    value: Value,
};

pub const BlockType = enum(u8) { LINK, FW_RULE };

/// e.g.
/// # type and name
/// link wg0 {
///    # pairs
///    address 192.168.1.1/24
///    up true
/// }
pub const Block = struct {
    type: BlockType,
    name: []const u8,

    pairs: ?[]Pair = null,
};

fn parse_block_type(token: Token) !BlockType {
    if (token != Token.Ident)
        return error.TypeNEIdent;

    if (std.mem.eql(u8, token.Ident, "link")) {
        return BlockType.LINK;
    } else if (std.mem.eql(u8, token.Ident, "fw_rule")) {
        return BlockType.FW_RULE;
    } else {
        return error.UnsupportedBlockType;
    }
}

fn parse_block(tokens: []Token) void {
    var block = Block{ .type = .LINK, .name = "" };
    for (tokens) |token| {
        const blk_type = parse_block_type(token);
        block.type = blk_type;
    }
}

pub fn parse_config_tokens(allocator: Allocator, tokens: []Token) ![]Block {
    var blocks = try std.ArrayList(Block).initCapacity(allocator, 1024);

    const block = parse_block(tokens);
}
