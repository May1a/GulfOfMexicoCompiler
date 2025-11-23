const std = @import("std");
const ArrayList = std.ArrayList;

const Ident = []const u8;
const IdentList = std.ArrayList(Ident);
const LineIter = std.mem.SplitIterator(u8, std.mem.DelimiterType.scalar);

const Parser = @This();

arena: std.mem.Allocator,
currentLine: u16 = 1,
lineIter: LineIter,
numbers: ArrayList(i32),
strings: ArrayList([]const u8),
idents: ArrayList([]const u8),

pub fn init(arena: std.mem.Allocator) Parser {
    return .{
        .arena = arena,
        .lineIter = undefined,
        .numbers = .empty,
        .strings = .empty,
        .idents = .empty,
    };
}

/// Returns null if char is not special or number, returns coresponding Token otherwise
fn checkChar(char: u8) ?TokenType {
    return switch (char) {
        '0'...'9' => .Number,
        // charCode 33-47, 58-64, 91-94 and 96
        '!'...'/', ':'...'@', '['...'^', '`' => |c| blk: {
            break :blk switch (c) {
                '!' => .Endl,
                '*' => .Mult,
                '/' => .Div,
                '+' => .Plus,
                '%' => .Mod,
                '-' => .Minus,
                ',' => .Comma,
                '[' => .OpenSquareB,
                ']' => .CloseSquareB,
                '>' => .MoreThan,
                '<' => .LessThan,
                '=' => .Eq,
                ':' => .Colon,
                '{' => .OpenSquirly,
                '}' => .CloseSquirly,
                ';' => .Not,
                '.' => .NSAccess,
                '(' => .OpenB,
                ')' => .CloseB,

                else => .Illegal,
            };
        },
        else => null,
    };
}

pub const TokenType = enum(u8) {
    Illegal,
    Const,
    Var,
    Eq,
    NotEq,
    OpenSquirly,
    CloseSquirly,
    OpenSquareB,
    CloseSquareB,
    Colon,
    When,
    If,
    Endl,
    EndlPrint,
    Fn,
    Number,
    String,
    Arrow,
    Minus,
    Plus,
    Mult,
    Div,
    Comment,
    Ident,
    MoreThan,
    LessThan,
    MoreThanOrEq,
    LessThanOrEq,
    And,
    Or,
    Not,
    Mod,
    Comma,
    NSAccess,
    Return,
    OpenB,
    CloseB,

    pub fn fromStr(str: []const u8) ?TokenType {
        return TokenMap.get(str);
    }
};

const TokenMap = std.StaticStringMap(TokenType).initComptime(.{
    .{ "const", .Const },
    .{ "var", .Var },
    .{ "=", .Eq },
    .{ ">", .MoreThan },
    .{ "<", .LessThan },
    .{ ">=", .MoreThanOrEq },
    .{ "<=", .LessThanOrEq },
    .{ "return", .Return },
    .{ "%", .Mod },
    .{ "&&", .And },
    .{ "and", .And },
    .{ "||", .Or },
    .{ "or", .Or },
    .{ ";", .Not },
    .{ "{", .OpenSquirly },
    .{ "}", .CloseSquirly },
    .{ "[", .OpenSquareB },
    .{ "]", .CloseSquareB },
    .{ "(", .OpenB },
    .{ ")", .CloseB },
    .{ ":", .Colon },
    .{ "when", .When },
    .{ "if", .If },
    .{ "!", .Endl },
    .{ "?", .EndlPrint },
    .{ "fn", .Fn },
    .{ "=>", .Arrow },
    .{ "-", .Minus },
    .{ "+", .Plus },
    .{ "*", .Mult },
    .{ "/", .Div },
    .{ "%", .Mod },
    .{ "//", .Comment },
    .{ ",", .Comma },
});

pub const ParsedSource = struct {
    numbers: []const i32,
    strings: [][]const u8,
    tokens: []Token,
    idents: [][]const u8,
    splitIter: *std.mem.SplitIterator(u8, std.mem.DelimiterType.scalar),
};

pub fn parseStrNoStartingQuote(strToParse: []const u8) ![]const u8 {
    for (0.., strToParse) |i, s| {
        if (s == '"') return strToParse[0..i];
    }
    return error.noDelemiter;
}

pub fn parseStrMultiline() ![]const u8 {
    // TODO:
    @panic("TODO: Implement multiline parsing for strings!");
}

pub fn parseStr(strToParse: []const u8) ![]const u8 {
    var start: ?u16 = null;
    var i: u16 = 0;
    while (i < strToParse.len) : (i += 1) {
        const char = strToParse[i];
        if (char == '"') {
            if (start) |s| {
                return strToParse[s..i];
            } else {
                start = i + 1;
            }
        }
    }
    return error.couldNotParseStr;
}

pub const Token = struct {
    type: TokenType,
    line: u16,
    column: u16,
};

pub fn parse(this: *Parser, source: []const u8) !ParsedSource {
    this.lineIter = std.mem.splitScalar(u8, source, '\n');
    defer this.lineIter.reset();
    var tokens = std.ArrayList(Token).empty;

    while (this.lineIter.next()) |line| : (this.currentLine += 1) {
        var tokenIter = std.mem.tokenizeAny(u8, line, " ");
        while (tokenIter.next()) |tk| {
            if (TokenType.fromStr(tk)) |tt| {
                try tokens.append(this.arena, .{
                    .type = tt,
                    .line = this.currentLine,
                    .column = @intCast(tokenIter.index),
                });
                if (tt == .Comment) break else continue;
            }

            switch (tk[0]) {
                '-' => {
                    var i: u16 = 1;
                    while (tk.len > 1 and switch (tk[i]) {
                        '0'...'9' => true,
                        else => false,
                    }) : (i += 1) {}
                    const num = std.fmt.parseInt(i32, tk[0..i], 10) catch unreachable;
                    try this.numbers.append(this.arena, num);
                    try tokens.append(this.arena, .{
                        .type = .Number,
                        .line = this.currentLine,
                        .column = @intCast(tokenIter.index),
                    });
                },
                '"' => {
                    try this.strings.append(this.arena, parseStr(tokenIter.buffer) catch blk: {
                        break :blk parseStrNoStartingQuote(tk) catch {
                            @branchHint(.cold);
                            std.log.err("line {d} - Could not parse String!", .{this.currentLine});
                            @panic("");
                        };
                    });
                    try tokens.append(this.arena, .{
                        .type = .String,
                        .line = this.currentLine,
                        .column = @intCast(tokenIter.index),
                    });
                    break;
                },
                '!' => try tokens.append(this.arena, .{
                    .type = .Endl,
                    .line = this.currentLine,
                    .column = @intCast(tokenIter.index),
                }),
                '/' => {
                    if (tk.len <= 1) {
                        @branchHint(.cold);
                        std.log.err("'/' found in unexpected location - on line {d}", .{this.currentLine});
                        @panic("Unrecoverable Error!");
                    } else if (tk[1] == '/') break else {
                        @branchHint(.cold);
                        std.log.err("'/' found in unexpected location - on line {d}", .{this.currentLine});
                        @panic("Unrecoverable Error!");
                    }
                },
                'a'...'z', 'A'...'Z', '0'...'9' => {
                    var i: u16 = 0;
                    while (i < tk.len) : (i += 1) {
                        const currentChar = tk[i];
                        if (checkChar(currentChar)) |tt| {
                            switch (tt) {
                                .Number => {
                                    const start = i;
                                    while (i < tk.len and std.ascii.isDigit(tk[i])) : (i += 1) {}
                                    const int = try std.fmt.parseInt(i32, tk[start..i], 10);
                                    try this.numbers.append(this.arena, int);
                                    try tokens.append(this.arena, .{
                                        .type = .Number,
                                        .line = this.currentLine,
                                        .column = @intCast(tokenIter.index),
                                    });
                                    if (i > 0) i -= 1;
                                },
                                else => try tokens.append(this.arena, .{
                                    .type = tt,
                                    .line = this.currentLine,
                                    .column = @intCast(tokenIter.index),
                                }),
                            }
                        } else {
                            const start = i;
                            while (i < tk.len and (std.ascii.isAlphanumeric(tk[i]) or tk[i] == '_')) : (i += 1) {}
                            if (TokenMap.get(tk[start..i])) |t| {
                                try tokens.append(this.arena, .{
                                    .type = t,
                                    .line = this.currentLine,
                                    .column = @intCast(tokenIter.index),
                                });
                            } else {
                                try this.idents.append(this.arena, tk[start..i]);
                                try tokens.append(this.arena, .{
                                    .type = .Ident,
                                    .line = this.currentLine,
                                    .column = @intCast(tokenIter.index),
                                });
                            }
                            // Not sure why this is here?
                            if (i > 0) i -= 1;
                        }
                    }
                },
                else => {},
            }
            if (tk[tk.len - 1] == '!' and tokens.getLast().type != .Endl) {
                try tokens.append(this.arena, .{
                    .type = .Endl,
                    .line = this.currentLine,
                    .column = @intCast(tokenIter.index),
                });
            }
        }
    }
    return .{
        .tokens = tokens.items,
        .numbers = this.numbers.items,
        .strings = this.strings.items,
        .idents = this.idents.items,
        .splitIter = &this.lineIter,
    };
}
