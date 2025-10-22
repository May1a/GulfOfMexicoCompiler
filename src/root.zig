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
    class,
    className,
    new,
};

const Scope = struct {
    type: enum {
        function,
        local,
    },
    name: []const u8,
    parent: *Scope,
    variables: std.ArrayList(Variable),
    children: std.ArrayList(*Scope),
};
const Variable = struct {
    name: []const u8,
    value: union(enum) {
        integer: i64,
        float: f64,
        string: []const u8,
        boolean: bool,
        array: []const u8,
        object: []const u8,
        undefined,
    },
};

const Function = struct {
    name: []const u8,
    parameters: []const Variable,
    body: []const u8,
};

pub fn interpret(source: []const u8) !void {
    const allocator = std.heap.page_allocator;
    var arenaAllocator = std.heap.ArenaAllocator.init(allocator);
    defer arenaAllocator.deinit();
    const arena = arenaAllocator.allocator();
    var inputIterator = std.mem.splitAny(u8, source, "() \t\n\r");
    const globalScope = .{
        .variables = std.ArrayList(Variable),
        .children = std.ArrayList(*Scope),
    };

    std.debug.print("Global Scope: {any}\n", .{globalScope});

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
                //    _ = inputIterator.next(); // progress 1 to get beyond the first '{'
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
