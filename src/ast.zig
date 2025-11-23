const std = @import("std");
const ArrayList = std.ArrayList;
const Processor = @This();

const assert = std.debug.assert;

const Parser = @import("parser.zig");

const Value = union(TValue) {
    Str: []u8,
    Int: i32,
    Arr: ArrayList(Value),
    Undefined,
};

const TValue = enum {
    Str,
    Int,
    Arr,
    Undefined,
};

const none = .{};

const Variable = struct {
    name: []const u8,
    value: *Expr,
};

/// small utility function that can run at comptime to with `srcL(@src())`
pub inline fn srcL(src: std.builtin.SourceLocation) []const u8 {
    return std.fmt.comptimePrint("{d}", .{src.line});
}

const Expr = union(enum) {
    // TODO: Change operator to be less generic
    // FIXME: Make use of `Expr.Bin` for actual working math!
    Bin: struct { left: *Expr, op: Parser.TokenType, right: *Expr },
    val: Value,
    FnCall: struct { ident: []const u8, callArgs: ?*[]Expr },
    // TODO: Think about a better way to do this
    VarRef: []const u8,
    // FIXME: Do this a better way!!!
    NSVarRef: [][]const u8,
    Bool: BoolExpr,
};

const BoolExpr = union(enum) {
    BoolBin: struct { left: *Expr, op: Parser.TokenType, right: *Expr },
    Expr: *Expr,
};

const Scope = []AstNode;

const DynNode = ArrayList(AstNode);

const ConstStr = []const u8;

const AstNode = union(enum) {
    varDecl: Variable,
    fun: struct { ident: []const u8, args: ?[]Variable, Scope: *Scope },
    If: struct { cond: []BoolExpr, Scope: *Scope },
    When: struct { cond: []BoolExpr, Scope: *Scope },
    Expr: Expr,
    RootNode: *Scope,
    Return: Expr,
};

source: Parser.ParsedSource,
currentNumber: u16 = 0,
currentIdent: u16 = 0,
currentStr: u16 = 0,
currentToken: u16 = 0,
allocator: std.mem.Allocator,

fn getCurrentIdent(this: *Processor) ConstStr {
    return this.source.idents[this.currentIdent];
}

fn getCurrentStr(this: *Processor) ConstStr {
    return this.source.strings[this.currentStr];
}

fn getCurrentNumber(this: *Processor) i32 {
    return this.source.numbers[this.currentNumber];
}

/// increments string count, returns the index of the current string
fn nextStr(this: *Processor) u32 {
    this.currentStr += 1;
    return this.currentStr - 1;
}

/// increments the string count and returns the string
fn nextStrV(this: *Processor) []const u8 {
    return this.source.strings[this.nextStr()];
}

/// increments number count, returns the index of the current number
fn nextNumber(this: *Processor) u16 {
    this.currentNumber += 1;
    return this.currentNumber - 1;
}

/// increments the number count and returns the number
fn nextNumberV(this: *Processor) i32 {
    return this.source.numbers[this.nextNumber()];
}

/// increments ident count, returns the index of the current ident
fn nextIdent(this: *Processor) u16 {
    this.currentIdent += 1;
    return this.currentIdent - 1;
}

/// increments the ident count and return the ident
fn nextIdentV(this: *Processor) []const u8 {
    return this.source.idents[this.nextIdent()];
}

fn nextToken(this: *Processor, expectedToken: ?Parser.TokenType) !Parser.TokenType {
    try incrementToken(this, expectedToken);
    return this.source.tokens[this.currentToken].type;
}

fn peekToken(this: *Processor, expectedToken: ?Parser.TokenType) !Parser.TokenType {
    const token = this.source.tokens[this.currentToken + 1].type;
    if (expectedToken) |t| {
        if (t != token) {
            @branchHint(.cold);
            std.log.err("unexpected token: {any}, expected: {any}", .{ this.getTokenAtRelative(1), t });
            return error.WrongToken;
        }
    }
    return token;
}

fn getCurrentToken(this: *Processor) Parser.Token {
    return this.source.tokens[this.currentToken];
}
fn getCurrentTokenT(this: *Processor) Parser.TokenType {
    return this.source.tokens[this.currentToken].type;
}

fn getTokenAtRelative(this: *Processor, offsetSigned: i8) Parser.Token {
    assert(offsetSigned != 0);
    if (offsetSigned > 0) {
        const offset: u16 = @intCast(offsetSigned);
        return this.source.tokens[this.currentToken + offset];
    } else {
        const adjandtruncoffset: u16 = @intCast(-offsetSigned);
        return this.source.tokens[this.currentToken - adjandtruncoffset];
    }
}

fn printCurrentToken(this: *Processor) void {
    const currentToken = this.getCurrentToken();
    std.log.info("current token {any} on {d}:{d}", .{ currentToken.type, currentToken.line, currentToken.column });
}
fn printTokenAt(this: *Processor, i: u16) void {
    const tk = this.source.tokens[i];
    std.log.info("current token {any} on line: {d}:{d}", .{ tk.type, tk.line, tk.column });
}

fn printTokenAtRelative(this: *Processor, offset: i8) void {
    const currentToken = this.getTokenAtRelative(offset);
    std.log.info("current token {any} on line: {d}:{d}", .{ currentToken.type, currentToken.line, currentToken.column });
}

/// increments the currenttoken
/// params: (?expectedtoken: TokenType)
/// !=> if provided returns an error when it does not match with the received token
/// -> void
fn incrementToken(this: *Processor, expectedToken: ?Parser.TokenType) !void {
    this.currentToken += 1;
    if (expectedToken) |t| {
        if (t != this.source.tokens[this.currentToken].type) {
            @branchHint(.cold);
            std.log.err("unexpected token: {any}, expected: {any}", .{ this.getCurrentTokenT(), t });
            return error.WrongToken;
        }
    }
}

pub fn init(from: Parser.ParsedSource, allocator: std.mem.Allocator) Processor {
    return .{ .source = from, .allocator = allocator };
}

fn computeBExprSimple(a: i32, b: i32, op: Parser.TokenType) i32 {
    return switch (op) {
        .Plus => a + b,
        .Minus => a - b,
        .Mult => a * b,
        .Div => @divTrunc(a, b), // TODO: Check if this is okay (probably not) but not a priority now
        else => unreachable,
    };
}

fn computeMathQuickAndDirty(this: *Processor) !Value { // FIXME: replace with proper math functionality!
    var nums: [2]?i32 = .{ null, null };
    var op: ?Parser.TokenType = null;
    while (this.nextToken(null) catch null) |nt| {
        if (nums[0] != null and nums[1] != null and op != null) {
            defer nums[1] = null;
            defer op = null;
            const a = nums[0].?;
            const b = nums[1].?;
            nums[0] = computeBExprSimple(a, b, op.?);
        }
        switch (nt) {
            .Number => {
                if (nums[0] == null) {
                    nums[0] = this.nextNumberV();
                } else if (nums[1] == null) {
                    nums[1] = this.nextNumberV();
                } else unreachable;
            },
            .Plus, .Minus, .Mult, .Div => |o| {
                if (op == null) {
                    op = o;
                } else unreachable;
            },
            else => {
                // TODO: check if this works!
                return .{ .Int = nums[0].? };
            },
        }
    }
    unreachable;
}

fn printDiagnostic(this: *Processor, token: Parser.Token) !void {
    this.source.splitIter.reset();
    var stdioBuf: [1000]u8 = undefined;

    const stdout = std.fs.File.stdout();
    var stdoutWriter = stdout.writer(&stdioBuf);

    for (0..token.line - 1) |_| {
        _ = this.source.splitIter.next();
    }
    const line = this.source.splitIter.next().?;

    try stdoutWriter.interface.print("ERROR:\n", none);

    try stdoutWriter.interface.writeAll(line);
    try stdoutWriter.interface.writeByte('\n');

    for (0..token.column - 1) |_| {
        try stdoutWriter.interface.print("-", none);
    }

    try stdoutWriter.interface.print("^", none);
    for (token.column..line.len) |_| {
        try stdoutWriter.interface.print("-", none);
    }
    try stdoutWriter.interface.print("\n", none);

    try stdoutWriter.interface.print("PROBLEM HERE\n", none);

    try stdoutWriter.interface.flush();
}

fn illegalToken(this: *Processor, token: Parser.Token, calledby: []const u8) noreturn {
    std.log.err("illegal token {any} on line: {d} called by: {s}", .{ token.type, token.line, calledby });
    this.printDiagnostic(token) catch unreachable;
    unreachable; // TODO: make recoverable?
}

fn parseFnCallArgs(this: *Processor) anyerror![]Expr {
    var args = ArrayList(Expr).empty;
    try this.incrementToken(.OpenB);
    while (this.peekToken(null) catch null) |tk| {
        if (tk == .CloseB) break;
        const arg = try this.parseExpr();
        try args.append(this.allocator, arg);
    }
    try this.incrementToken(.CloseB);
    try this.incrementToken(.Endl);
    return try args.toOwnedSlice(this.allocator);
}

fn parseIdent(this: *Processor) !Expr {
    try this.incrementToken(.Ident);
    var expr: Expr = undefined;
    const ident = this.nextIdentV(); // FIXME: Do this a better way!!!

    switch (try this.peekToken(null)) {
        .OpenB => {
            var fnCallArgs = try this.parseFnCallArgs();
            // FIXME: DON'T have a pointer to the stack!!!
            expr = .{ .FnCall = .{ .callArgs = &fnCallArgs, .ident = ident } };
            return expr;
        },
        .Endl => {
            try this.incrementToken(.Endl);
            expr = .{ .VarRef = ident };
            return expr;
        },
        .NSAccess => {
            try this.incrementToken(.NSAccess);
            const next = try this.nextToken(null);
            var nsAccessL = ArrayList([]const u8).empty;
            try nsAccessL.append(this.allocator, ident);
            sw: switch (next) {
                .Ident => {
                    try nsAccessL.append(this.allocator, this.nextIdentV());
                    continue :sw try this.nextToken(null);
                },
                .NSAccess => {
                    continue :sw try this.nextToken(null);
                },
                .OpenB => {
                    // FIXME: Support
                    @panic("Namespaced functions not supported yet!");
                },
                else => {
                    this.currentToken -= 1;
                    break :sw;
                },
            }
            return .{ .NSVarRef = try nsAccessL.toOwnedSlice(this.allocator) };
        },
        else => {
            expr = .{ .VarRef = ident };
            return expr;
        },
    }
}

fn parseExpr(this: *Processor) !Expr {
    defer {
        if (this.getCurrentTokenT() == .Endl) {
            this.currentToken += 1;
        }
    }
    switch (try this.peekToken(null)) {
        .Number, .Minus => {
            const expr: Expr = .{ .val = try this.computeMathQuickAndDirty() };
            return expr;
        },
        .Fn => {
            @panic("Functions as expressions aren't supported yet!");
        },
        .String => {
            try this.incrementToken(.String);
            const str: []u8 = @constCast(this.nextStrV());
            const expr: Expr = .{ .val = .{ .Str = str } };
            try this.incrementToken(.Endl);
            return expr;
        },
        .Ident => {
            return try this.parseIdent();
        },
        else => |tk| {
            std.log.err("Token: {any}", .{tk});
            this.illegalToken(this.getCurrentToken(), "parseExpr — In else part of switch line" ++ std.fmt.comptimePrint("{d}", .{@src().line}));
        },
    }
}

fn parseVarDecl(this: *Processor) !AstNode {
    var node: AstNode = .{ .varDecl = undefined };

    // TODO: Make this check for validity
    // TODO: Implement different Variable types (e.g.: `const const`, `var const`, etc.)
    const firstToken = this.getCurrentTokenT();
    const secondToken = try this.incrementToken(.Const);
    _ = firstToken;
    _ = secondToken;

    try this.incrementToken(.Ident);

    node.varDecl.name = this.nextIdentV();

    // NOTE: An exception for *implicitly* unitialized variables is not required,
    // since they don't exist, so this is fine.
    try this.incrementToken(.Eq);

    std.debug.print("parsing expression\n", .{});
    const expr = try this.allocator.create(Expr);
    expr.* = try this.parseExpr();

    node.varDecl.value = expr;
    std.log.info("parsed var decl successfully! {any}", .{expr.*});
    try this.incrementToken(null);
    return node;
}

fn parseFnArgs(this: *Processor) ![]Variable {
    var params = ArrayList(Variable).empty;
    try this.incrementToken(.OpenB);

    while (this.nextToken(null) catch null) |tk| {
        if (tk == .Arrow) {
            this.currentToken -= 1; // TODO: Do this another way??? Or is this fine?
            return params.toOwnedSlice(this.allocator);
        }
        switch (tk) {
            .Ident => {
                const ident = this.nextIdentV();
                const param: Variable = .{ .name = ident, .value = undefined };
                try params.append(this.allocator, param);
            },
            .Comma => {
                continue;
            },
            else => continue,
        }
    }
    unreachable;
}

fn tokenIsUnitaryOperator(tk: Parser.TokenType) bool {
    return switch (tk) {
        .Eq,
        .NotEq,
        .LessThan,
        .LessThanOrEq,
        .Or,
        .And,
        .MoreThan,
        .MoreThanOrEq,
        .Not,
        => true,
        else => false,
    };
}

fn parseBoolExprUntilDelimiter(this: *Processor, delimiter: Parser.TokenType) ![]BoolExpr {
    var boolExpressions = ArrayList(BoolExpr).empty;

    // FIXME: Consider doing this another way
    while (try this.peekToken(null) != delimiter) {
        var boolExpr: BoolExpr = undefined;
        switch (try this.peekToken(null)) {
            .Number, .Ident => |t| {
                const val: Expr = val: {
                    if (t == .Number) {
                        break :val .{ .val = try this.computeMathQuickAndDirty() };
                    } else {
                        break :val try this.parseIdent();
                    }
                };
                const nextTk = try this.peekToken(null);
                const exprPtr = try this.allocator.create(Expr);
                exprPtr.* = val;
                if (!tokenIsUnitaryOperator(nextTk)) {
                    boolExpr = .{ .Expr = exprPtr };
                } else {
                    try this.incrementToken(null);
                    const tokenAfterUnary = try this.peekToken(null);
                    switch (tokenAfterUnary) {
                        .Number, .Ident => {
                            const val2: Expr = val: {
                                if (t == .Number) {
                                    break :val .{ .val = try this.computeMathQuickAndDirty() };
                                } else {
                                    break :val try this.parseIdent();
                                }
                            };
                            const exprPtr2 = try this.allocator.create(Expr);
                            exprPtr2.* = val2;
                            boolExpr = .{ .BoolBin = .{ .left = exprPtr, .op = nextTk, .right = exprPtr2 } };
                        },
                        .String => {
                            this.printCurrentToken();
                            this.illegalToken(this.getTokenAtRelative(1), "parseBoolExprUntilDelimiter — Compared string with number, line " ++ std.fmt.comptimePrint("{d}", .{@src().line}));
                        },
                        else => {
                            this.printCurrentToken();
                            this.illegalToken(this.getCurrentToken(), "parseBoolExprUntilDelimiter, — Nested catch-all, line " ++ std.fmt.comptimePrint("{d}", .{@src().line}));
                        },
                    }
                }
            },
            .String => {
                this.illegalToken(this.getTokenAtRelative(1), "parseBoolExprUntilDelimiter — Cannot compare strings, line: " ++ std.fmt.comptimePrint("{d}", .{@src().line}));
            },
            else => {
                this.illegalToken(this.getTokenAtRelative(1), "parseBoolExprUntilDelimiter — Else; catch-all, line " ++ std.fmt.comptimePrint("{d}", .{@src().line}));
            },
        }

        try boolExpressions.append(this.allocator, boolExpr);
    }
    return try boolExpressions.toOwnedSlice(this.allocator);
}

fn parseBoolExpr(this: *Processor) ![]BoolExpr {
    return parseBoolExprUntilDelimiter(this, .CloseB);
}

fn parseWhen(this: *Processor) anyerror!AstNode {
    var node: AstNode = .{ .When = undefined };

    var scopeL = ArrayList(AstNode).empty;
    try this.incrementToken(.OpenB);
    node.When.cond = try this.parseBoolExpr();
    try this.incrementToken(.CloseB);

    const scope = try this.parseScope(false);
    try scopeL.appendSlice(this.allocator, scope);

    node.When.Scope = &scopeL.items;
    return node;
}

fn parseIf(this: *Processor) anyerror!AstNode {
    var node: AstNode = .{ .If = undefined };

    var scopeL = ArrayList(AstNode).empty;

    node.If.cond = try this.parseBoolExpr();
    const scope = try this.parseScope(false);
    try scopeL.appendSlice(this.allocator, scope);

    node.If.Scope = &scopeL.items;
    return node;
}

/// utility function for parsing a scope
/// NOTE: should not be used on it's own instead statement parsing which has scopes attached shall call it
fn parseScope(this: *Processor, root: bool) !Scope {
    var scope = ArrayList(AstNode).empty;
    if (!root) {
        std.log.info("Starting to parse Scope", .{});
        this.printCurrentToken();

        try this.incrementToken(.OpenSquirly);
    }
    this.printCurrentToken();

    defer if (!root) {
        if (this.getCurrentTokenT() != .CloseSquirly) {
            this.illegalToken(this.getCurrentToken(), "parseScope — In defer line " ++ srcL(@src()));
        }
    };
    var i: u6 = 0;
    while (try this.peekToken(null) != .CloseSquirly) : (i += 1) {
        const tk = this.getCurrentTokenT();
        var statement: AstNode = undefined;
        std.log.info("In statement loop current Token: {any} at line: {d} and idx: {d}", .{
            this.getCurrentTokenT(),
            this.getCurrentToken().line,
            this.currentToken,
        });
        switch (tk) {
            .Fn => {
                std.log.info("Parsing fn!", .{});
                this.printCurrentToken();
                const fun = try this.parseFn();
                this.printCurrentToken();
                statement = fun;
            },
            .Const, .Var => {
                std.log.info("Parsing var!", .{});
                this.printCurrentToken();
                const varDecl = try this.parseVarDecl();
                statement = varDecl;
                this.printCurrentToken();
            },
            .When => {
                statement = try this.parseWhen();
            },
            .Return => {
                std.log.info("Parsing return statement!", .{});
                const ret = try this.parseExpr();
                const retNode: AstNode = .{ .Return = ret };
                statement = retNode;
            },
            .OpenSquirly => {
                try this.incrementToken(null);
                continue;
            },
            else => {
                std.log.info("Token idx: {d}, on iter: {d}", .{ this.currentToken, i });
                this.illegalToken(this.getCurrentToken(), "parseScope — In switch inside of else, line: " ++ srcL(@src()));
            },
        }

        try scope.append(this.allocator, statement);
    }

    return try scope.toOwnedSlice(this.allocator);
}

fn parseFn(this: *Processor) anyerror!AstNode {
    var node: AstNode = .{ .fun = undefined };
    if (this.getCurrentTokenT() != .Fn) unreachable;
    try this.incrementToken(.Ident);
    node.fun.ident = this.nextIdentV();
    node.fun.args = if (try this.peekToken(null) == .Arrow) null else try this.parseFnArgs();
    try this.incrementToken(.Arrow);
    var scope = try this.parseScope(false);
    node.fun.Scope = &scope;
    try this.incrementToken(.CloseSquirly);
    return node;
}

pub fn parseRoot(this: *Processor) !AstNode {
    var rootNode = try this.allocator.create(AstNode);
    var node = try this.parseScope(true);
    rootNode.RootNode = &node;
    return rootNode.*;
}
