const std = @import("std");
const ArrayList = std.ArrayList;

const Ident = []const u8;
const IdentList = std.ArrayList(Ident);
const LineIter = std.mem.SplitIterator(u8, std.mem.DelimiterType.scalar);

const Parser = @This();

unit: ParserUnit = .root,
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
        // charCode 33-47, 58-64 and 91-96
        '!'...'/', ':'...'@', '['...'`' => |c| blk: {
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

                else => .Illegal,
            };
        },
        else => null,
    };
}

const TokenType = enum(u8) {
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

const ParsedSource = struct {
    numbers: []const i32,
    strings: [][]const u8,
    Tokens: []Token,
    idents: [][]const u8,
};

const ParserUnit = union(enum) {
    root,
    child: u8,
};

pub fn parseStrNoStartingQuote(strToParse: []const u8) ![]const u8 {
    for (0.., strToParse) |i, s| {
        if (s == '"') return strToParse[0..i];
    }
    return error.noDelemiter;
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

const Token = struct {
    type: TokenType,
    line: u16,
};

pub fn parse(this: *Parser, source: []const u8) !ParsedSource {
    this.lineIter = std.mem.splitScalar(u8, source, '\n');
    var tokens = std.ArrayList(Token).empty;

    while (this.lineIter.next()) |line| : (this.currentLine += 1) {
        var tokenIter = std.mem.tokenizeAny(u8, line, " ()");
        while (tokenIter.next()) |tk| {
            if (TokenType.fromStr(tk)) |tt| {
                try tokens.append(this.arena, .{ .type = tt, .line = this.currentLine });
                if (tt == .Comment) break else continue;
            }

            switch (tk[0]) {
                '-' => {
                    var i: u16 = 1;
                    while (tk.len > 1 and switch (tk[i]) {
                        '0'...'9' => true,
                        else => false,
                    }) : (i += 1) {}
                    std.log.info("Num to parse: {s}, line: {d} - ctx: {s}", .{ tk[0..i], this.currentLine, tk });
                    const num = std.fmt.parseInt(i32, tk[0..i], 10) catch unreachable;
                    try this.numbers.append(this.arena, num);
                    try tokens.append(this.arena, .{ .type = .Number, .line = this.currentLine });
                },
                '"' => {
                    try this.strings.append(this.arena, parseStr(tokenIter.buffer) catch blk: {
                        break :blk parseStrNoStartingQuote(tk) catch {
                            @branchHint(.cold);
                            std.log.err("line {d} - Could not parse String!", .{this.currentLine});
                            @panic("");
                        };
                    });
                    try tokens.append(this.arena, .{ .type = .String, .line = this.currentLine });
                    break;
                },
                '!' => try tokens.append(this.arena, .{
                    .line = this.currentLine,
                    .type = .Endl,
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
                        std.debug.print("|{c}|", .{currentChar});
                        if (checkChar(currentChar)) |tt| {
                            switch (tt) {
                                .Number => {
                                    const start = i;
                                    while (i < tk.len and std.ascii.isDigit(tk[i])) : (i += 1) {}
                                    const int = try std.fmt.parseInt(i32, tk[start..i], 10);
                                    try this.numbers.append(this.arena, int);
                                    try tokens.append(this.arena, .{ .line = this.currentLine, .type = .Number });
                                },
                                else => try tokens.append(this.arena, .{ .line = this.currentLine, .type = tt }),
                            }
                        } else {
                            const start = i;
                            while (i < tk.len and std.ascii.isAlphanumeric(tk[i])) : (i += 1) {}
                            try this.idents.append(this.arena, tk[start..i]);
                            try tokens.append(this.arena, .{ .line = this.currentLine, .type = .Ident });
                        }
                    }
                    std.debug.print("\n ^ On line: {d} ^ \n", .{this.currentLine});
                },
                else => {},
            }
            if (tk[tk.len - 1] == '!') {
                try tokens.append(this.arena, .{ .line = this.currentLine, .type = .Endl });
            }
        }
    }
    return .{
        .Tokens = tokens.items,
        .numbers = this.numbers.items,
        .strings = this.strings.items,
        .idents = this.idents.items,
    };
}
