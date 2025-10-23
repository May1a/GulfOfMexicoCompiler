//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const print = std.debug.print;

const Token = enum {
    function,
    @"fn",
    when,
    @"const",
    @"var",
    @":",
    @"=",
    @"=>",
    @"+",
    @"-",
    @"*",
    @"/",
    @"%",
    @"^",
    @"&",
    @"|",
    @"~",
    @"!",
    @"(",
    @")",
    @"[",
    @"]",
    @"{",
    @"}",
    @".",
    @",",
    @"<",
    @">",
    @"<=",
    @">=",
    @"==",
    @"!=",
    @"&&",
    @"||",
    @"if",
    @"else",
    @"return",
    undefined,
    class,
    className,
    new,
};
/// `Scope(null) => local Scope w/ global Scope as parent`
///
/// `Scope(false) => local Scope w/ local Scope as parent`
///
/// `Scope(true) => global Scope`
fn Scope(comptime global: ?bool) type {
    if (global == null or !global.?) return struct {
        type: enum {
            function,
            local,
        },
        name: []const u8,
        parent: if (global == null) *Scope(true) else *Scope(false),
        variables: std.ArrayList(Variable),
        children: std.ArrayList(*Scope(false)),
    } else return struct {
        variables: std.ArrayList(Variable),
        children: std.ArrayList(*Scope(false)),
    };
}
const Variable = struct {
    name: []const u8,
    value: union(enum) {
        Int: i32,
        str: []const u8,
        bool: bool,
        array: []const u8,
        undefined,
    },
};

const Function = struct {
    name: []const u8,
    parameters: []const Variable,
    body: []const u8,
};
pub fn handleVariableDecl(
    comptime global: ?bool,
    scope: *Scope(global),
    inputIterator: *std.mem.SplitIterator(u8, std.mem.DelimiterType.any),
    declBegin: Token,
    alloc: std.mem.Allocator,
) !void {
    _ = declBegin;
    while (std.meta.stringToEnum(Token, inputIterator.peek().?) != null) {
        _ = inputIterator.next();
    }
    print("\n\n\nNAME!!! {s}\n\n\n\n", .{inputIterator.peek().?});
    var variable = Variable{
        .name = inputIterator.next().?,
        .value = undefined,
    };
    defer scope.variables.append(alloc, variable) catch unreachable;
    if (std.meta.stringToEnum(Token, inputIterator.peek().?) == .@"=") _ = inputIterator.next() else @panic("Expected `=` after variable declaration!");
    const decl = inputIterator.next().?;
    switch (decl[0]) {
        '0'...'9', '-' => {
            variable.value = .{ .Int = std.fmt.parseInt(i32, std.mem.trim(u8, decl, "! "), 10) catch @panic("failed to parse Int!") };
        },
        '\'', '"' => {
            variable.value = .{ .str = decl[1..decl.len] };
        },
        else => {},
    }
    print("\n{s} \n", .{inputIterator.peek().?});
    for (scope.variables.items) |v|
        print("\n \n -- \n Variable: \n name: {s}, \n value: {any} \n\n--", .{ v.name, v.value });
}

pub fn interpret(source: []const u8) !void {
    const allocator = std.heap.page_allocator;
    var arenaAllocator = std.heap.ArenaAllocator.init(allocator);
    defer arenaAllocator.deinit();
    const arena = arenaAllocator.allocator();
    var inputIterator = std.mem.splitAny(u8, source, "() \t\n\r");
    var globalScope = Scope(true){
        .variables = .{},
        .children = .{},
    };

    while (inputIterator.next()) |input| {
        const tokenEnum = std.meta.stringToEnum(Token, input) orelse continue;

        std.debug.print("Token: {any}\n", .{tokenEnum});

        switch (tokenEnum) {
            .function, .@"fn" => {
                var args = try std.ArrayList(Variable).initCapacity(arena, 10);
                const fnName = inputIterator.next() orelse continue;
                while (std.meta.stringToEnum(Token, inputIterator.peek() orelse continue) != .@"{") {
                    const argName = inputIterator.next().?;
                    try args.append(arena, .{ .name = argName, .value = .undefined });
                }
                const iterIdx = inputIterator.index orelse continue;
                var fnScopeEndIdx: usize = undefined;
                var scopes: i32 = 0;
                while (inputIterator.next()) |str_| {
                    const str = std.mem.trim(u8, str_, " ");
                    const token = std.meta.stringToEnum(Token, str) orelse continue;
                    print("{any}", .{token});
                    if (token == .@"{") scopes += 1 else if (token == .@"}") scopes -= 1;
                    if (scopes < 0) @panic("Invalid syntax!");
                    if (scopes == 0) {
                        fnScopeEndIdx = inputIterator.index.?;
                        break;
                    }
                }
                const function = Function{
                    .name = fnName,
                    .parameters = args.items,
                    .body = inputIterator.buffer[iterIdx..inputIterator.index.?],
                };
                std.debug.print("Function: \n FnName: {s}\n Params: {any} \n Body: {s} \n ---- \n", .{ function.name, function.parameters, function.body });
            },
            .@"const", .@"var" => try handleVariableDecl(true, &globalScope, &inputIterator, tokenEnum, arena),
            else => {},
        }
    }
}

test "reading sample file and running it through the interpreter" {
    const f = try std.fs.cwd().openFile("samples/test.gom", .{});
    defer f.close();
    var buffer: [1024]u8 = undefined;
    const n = try f.read(&buffer);
    std.debug.print("Contents: {s}\n", .{buffer[0..n]});
    try interpret(buffer[0..n]);
}
