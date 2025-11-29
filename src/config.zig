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

    pub fn init(input: []const u8, allocator: Allocator) Lexer {
        return .{
            .input = input,
            .allocator = allocator,
        };
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

        // Comments
        if (c == '#') {
            self.advance();
            self.skip_comment();
            return self.next();
        }

        // Single-character tokens
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
            const ident = try self.read_ident();
            return Token{ .Ident = ident };
        }

        if (c >= '0' and c <= '9') {
            return Token{ .Number = try self.read_number() };
        }

        std.log.err("INVALID CHAR: {c}\n", .{c});
        return error.InvalidCharacter;
    }
};

pub fn read_script(allocator: Allocator, file_path: []const u8) !void {
    var buf: [8192]u8 = undefined;
    const file_contents = try std.fs.cwd().readFile(file_path, &buf);

    var lexer = Lexer.init(file_contents, allocator);

    while (true) {
        const tok = try lexer.next();
        if (tok == Token.Ident) {
            std.debug.print("TOKEN: {s}\n", .{tok.Ident});
        } else {
            std.debug.print("TOKEN: {any}\n", .{tok});
        }

        if (@intFromEnum(tok) == @intFromEnum(Token.Eof))
            break;
    }
}

