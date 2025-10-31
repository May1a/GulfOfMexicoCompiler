const std = @import("std");
const print = std.debug.print;
const Errors = @import("errors.zig");

pub const Allocator = std.mem.Allocator;

pub const Token = enum {
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

pub const Scope = struct {
    functions: std.StringArrayHashMap(Function),
    variables: std.StringArrayHashMap(Variable),
    arena: Allocator,
};

pub const ScopeStack = std.ArrayList(*Scope);

pub const VarType = enum {
    const_const,
    const_var,
    var_var,
    var_const,
};

pub const TokenIter = std.mem.TokenIterator(u8, std.mem.DelimiterType.any);

pub const VariableValue = union(enum) {
    Int: i32,
    str: []const u8,
    bool: bool,
    array: []const u8,
    undefined,
};

pub const Variable = struct {
    name: []const u8,
    type: VarType,
    value: VariableValue,
};

pub const Function = struct {
    name: []const u8,
    parameters: []Variable,
    body: []const u8,
};

pub const MathOp = enum {
    add,
    sub,
    div,
    mult,
    pub fn determine(char: u8) !MathOp {
        return switch (char) {
            '+' => .add,
            '-' => .sub,
            '*' => .mult,
            '/' => .div,
            else => error.invalidMathOp,
        };
    }
};

pub fn handleMathOp(mathOps: []MathOp, nums: []i32) i32 {
    var result: i32 = nums[0];
    for (mathOps, nums[1..]) |op, num| {
        switch (op) {
            .add => result += num,
            .sub => result -= num,
            .mult => result *= num,
            .div => result = @divTrunc(result, num),
        }
    }
    return result;
}

test "Math Ops" {
    var ops = [_]MathOp{ .add, .sub };
    var nums = [_]i32{ 1, 4, 5 };

    const res = handleMathOp(&ops, &nums);
    try std.testing.expect(res == (1 + 4 - 5));
}

pub fn handleVariableDecl(
    scopeStack: *ScopeStack,
    inputIterator: *TokenIter,
    declBegin: Token,
    alloc: Allocator,
) !void {
    const declEnd = std.meta.stringToEnum(Token, inputIterator.next().?) orelse @panic(Errors.invalidVarDecl);
    const varType: VarType = if (declBegin == .@"const" and declEnd == .@"const") .const_const else if (declBegin == .@"const" and declEnd == .@"var") .const_var else if (declBegin == .@"var" and declEnd == .@"const") .var_const else if (declBegin == .@"var" and declEnd == .@"var") .var_var else return error.invalidDecl;

    while (std.meta.stringToEnum(Token, inputIterator.peek().?) != null) {
        _ = inputIterator.next();
    }
    var variable = Variable{
        .name = inputIterator.next().?,
        .type = varType,
        .value = undefined,
    };

    var scope = scopeStack.items[scopeStack.items.len - 1];

    if (inputIterator.peek().?[0] == '=') _ = inputIterator.next() else @panic("Expected `=` after variable declaration!");
    const decl = inputIterator.next().?;
    switch (decl[0]) {
        '0'...'9', '-' => {
            const nextToken = inputIterator.peek().?[0];

            switch (nextToken) {
                '+', '-', '/', '*' => |op| {
                    _ = inputIterator.next();
                    const firstInt = try std.fmt.parseInt(i32, decl, 10);
                    var ops = try std.ArrayList(MathOp).initCapacity(alloc, 1);
                    try ops.insert(alloc, 0, try MathOp.determine(op));
                    var nums = try std.ArrayList(i32).initCapacity(alloc, 1);
                    try nums.insert(alloc, 0, firstInt);

                    while (inputIterator.peek().?[inputIterator.peek().?.len - 1] != '!') {
                        const next = inputIterator.next().?;
                        try switch (next[0]) {
                            '+', '-', '/', '*' => |char| ops.append(alloc, try MathOp.determine(char)),
                            '0'...'9' => nums.append(alloc, try std.fmt.parseInt(i32, next, 10)),
                            else => return error.notANumber,
                        };
                    }
                    const lastToken = inputIterator.peek().?;
                    const lastNum = try std.fmt.parseInt(i32, lastToken[0 .. lastToken.len - 1], 10);
                    try nums.append(alloc, lastNum);
                    const variableValue = handleMathOp(ops.items, nums.items);

                    variable.value = .{ .Int = variableValue };
                },
                else => {
                    variable.value = .{ .Int = std.fmt.parseInt(i32, decl[0 .. decl.len - 1], 10) catch @panic("failed to parse Int!") };
                },
            }
        },
        '\'', '"' => {
            variable.value = .{ .str = decl[1 .. decl.len - 2] };
        },
        'a'...'z' => {
            const name = decl[0 .. decl.len - 1];
            if (scope.variables.get(name)) |v| {
                variable.value = v.value;
            }
        },
        else => {},
    }
    scope.variables.put(variable.name, variable) catch unreachable;
}

pub fn interpret(source: []const u8, comptime dbg: bool) !void {
    const allocator = std.heap.page_allocator;
    var arenaAllocator = std.heap.ArenaAllocator.init(allocator);
    defer arenaAllocator.deinit();
    const arena = arenaAllocator.allocator();
    var inputIterator = std.mem.tokenizeAny(u8, source, "\n\r");
    var mScope = Scope{
        .variables = std.StringArrayHashMap(Variable).init(allocator),
        .functions = std.StringArrayHashMap(Function).init(allocator),
        .arena = arena,
    };
    var scopeStack = try ScopeStack.initCapacity(arena, 1);
    try scopeStack.insert(arena, 0, &mScope);
    defer {
        if (dbg) {
            print("---\nAll the variables: \n", .{});
            for (scopeStack.items) |scope|
                for (scope.variables.values()) |v| {
                    print("\n \n -- \n Variable: \n name: {s}, \n value: {any} (Value(string): {s}) \n type: {any} \n\n--", .{ v.name, v.value, if (v.value == .str) v.value.str else "N/A", v.type });
                };
            print("\nAll Varibles printed\n ---", .{});
        }
    }
    while (inputIterator.next()) |input| {
        var lineIterator = std.mem.tokenizeAny(u8, input, "() \t\n\r");
        const tokenEnum = std.meta.stringToEnum(Token, lineIterator.next().?) orelse continue;

        switch (tokenEnum) {
            .function, .@"fn" => {
                var args = try std.ArrayList(Variable).initCapacity(arena, 10);
                const fnName = inputIterator.next() orelse continue;
                while ((inputIterator.peek() orelse continue)[0] != '{') {
                    const argName = inputIterator.next().?;
                    try args.append(arena, .{ .name = argName, .value = .undefined, .type = .const_const });
                }
                const iterIdx = inputIterator.index;
                var fnScopeEndIdx: usize = undefined;
                var scopes: i32 = 0;
                while (inputIterator.next()) |str| {
                    const firstChar = str[0];
                    if (firstChar == '{') scopes += 1 else if (firstChar == '}') scopes -= 1;
                    if (scopes < 0) @panic("Invalid syntax!");
                    if (scopes == 0) {
                        fnScopeEndIdx = inputIterator.index;
                        break;
                    }
                }
                const function = Function{
                    .name = fnName,
                    .parameters = args.items,
                    .body = inputIterator.buffer[iterIdx..inputIterator.index],
                };
                if (dbg)
                    std.log.info("Function: \n FnName: {s}\n Params: {any} \n Body: {s} \n ---- \n", .{ function.name, function.parameters, function.body });
            },
            .@"const", .@"var" => try handleVariableDecl(&scopeStack, &inputIterator, tokenEnum, arena),
            else => {},
        }
    }
}

test "reading sample file and running it through the interpreter" {
    const f = try std.fs.cwd().openFile("samples/test.gom", .{});
    defer f.close();
    var buffer: [2048]u8 = undefined;
    const n = try f.read(&buffer);
    std.debug.print("Contents: {s}\n", .{buffer[0..n]});
    try interpret(buffer[0..n], true);
}
