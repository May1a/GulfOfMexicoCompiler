const std = @import("std");
const root = @import("root.zig");

const Scope = struct {
    variables: std.StringArrayHashMap(root.Variable),
    functions: std.StringArrayHashMap(root.Function),
    arena: std.mem.Allocator,
};

const ScopeStack = std.ArrayList(*Scope);

const Interpreter = struct {
    arena: std.mem.Allocator,
    scopeStack: *ScopeStack,
    lineIterator: *TokenIterator,
    currentLine: u32 = 0, // TODO: Fix line counting!
    baseFunctions: *std.StringArrayHashMap(root.Function),

    pub fn nextLine(this: *@This()) ?[]const u8 {
        this.currentLine += 1;
        return this.lineIterator.next();
    }

    /// pass the interpreter in and set the line position to the starting `{`
    /// NOTE: Do NOT use `.nextLine()` on the lineIterator calling the function
    pub fn determineScopeEnd(this: *Interpreter) !u16 {
        var scopes: u8 = 1;
        while (this.nextLine()) |line| {
            var lineIdx: u16 = 0;
            while (line.len > lineIdx) : (lineIdx += 1) {
                const char = line[lineIdx];
                if (char == '}') {
                    scopes -= 1;
                    if (scopes == 0) return lineIdx;
                } else if (char == '{') {
                    scopes += 1;
                }
            }
        }
        return error.noEndInSight;
    }
    pub fn determineIfIsFnAndRunIfItIs(exprStart: []const u8, interpreter: *Interpreter, tokenIter: *TokenIterator) void {
        switch (exprStart[exprStart.len - 1]) {
            'a'...'z', 'A'...'Z' => runFn(exprStart, interpreter, tokenIter),
            else => return,
        }
    }
    pub fn computeMathExpr(this: *@This(), expr: []const u8) i32 {
        var iter = std.mem.splitAny(u8, expr, " !");
        var res: ?i32 = null;
        while (iter.next()) |seq| {
            switch (seq[0]) {
                '0'...'9' => {
                    const int = std.fmt.parseInt(i32, seq, 10) catch @panic("Could not parse Int.");
                    if (res) |_| {
                        @branchHint(.cold);

                        std.log.err(
                            "Error on line: {d} - Invalid syntax => cannot declare to numbers after each other. Did you mean to use an Operator?  {s}\n",
                            .{ this.currentLine, expr },
                        );
                        @panic("Error Fatal\n");
                    } else {
                        res = int;
                    }
                },
                '/' => {
                    const nextInt = std.fmt.parseInt(i32, iter.next().?, 10) catch {
                        std.log.err("Error on line: {d} - please provide an number after the `{c}` Operator\n", .{ this.currentLine, '/' });
                        @panic("Error Fatal\n");
                    };
                    res = @divTrunc(res orelse {
                        @branchHint(.cold);
                        std.log.err(
                            "Error on line: {d} - Please provide a number before the usage of the {c} operator.\n",
                            .{ this.currentLine, '/' },
                        );
                        @panic("Error Fatal\n");
                    }, nextInt);
                },

                '*' => {
                    const nextInt = std.fmt.parseInt(i32, iter.next().?, 10) catch {
                        std.log.err(
                            "Error on line: {d} - please provide an number after the `{c}` Operator\n",
                            .{ this.currentLine, '/' },
                        );
                        @panic("Error Fatal\n");
                    };
                    if (res) |_| {
                        res.? *= nextInt;
                    } else {
                        @branchHint(.cold);
                        std.log.err(
                            "Error on line: {d} - Please provide a number before the usage of the {c} operator.\n",
                            .{ this.currentLine, '/' },
                        );
                        @panic("Error Fatal\n");
                    }
                },

                '+' => {
                    const nextInt = std.fmt.parseInt(i32, iter.next().?, 10) catch {
                        std.log.err(
                            "Error on line: {d} - please provide an number after the `{c}` Operator\n",
                            .{ this.currentLine, '/' },
                        );
                        @panic("Error Fatal\n");
                    };
                    if (res) |_| {
                        res.? += nextInt;
                    } else {
                        @branchHint(.cold);
                        std.log.err(
                            "Error on line: {d} - Please provide a number before the usage of the {c} operator.\n",
                            .{ this.currentLine, '/' },
                        );
                        @panic("Error Fatal\n");
                    }
                },
                '-' => {
                    const nextInt = std.fmt.parseInt(i32, iter.next().?, 10) catch {
                        std.log.err(
                            "Error on line: {d} - please provide an number after the `{c}` Operator\n",
                            .{ this.currentLine, '/' },
                        );
                        @panic("Error Fatal\n");
                    };
                    if (res) |_| {
                        res.? -= nextInt;
                    } else {
                        @branchHint(.cold);
                        std.log.err(
                            "Error on line: {d} - Please provide a number before the usage of the {c} operator.\n",
                            .{ this.currentLine, '/' },
                        );
                        @panic("Error Fatal\n");
                    }
                },
                else => {
                    std.log.err("Error on line: {d} - Unknown error\n {s} \n", .{ this.currentLine, expr });
                    @panic("Error Fatal\n");
                },
            }
            return res.?;
        }
        unreachable;
    }
    /// parses the variable declaration *after* the `=`
    pub fn parseVarDecl(this: *@This(), decl: []const u8) root.VariableValue {
        switch (decl[0]) {
            '0'...'9', '-' => {
                return .{ .Int = this.computeMathExpr(decl) };
            },
            '"' => {
                const str = parseStr(decl) catch {
                    @branchHint(.cold);
                    std.log.err("Error on line: {d} - Could not parse string literal.\n", .{this.currentLine});
                    @panic("Error Fatal");
                };
                return root.VariableValue{ .str = str };
            },
            'a'...'z', 'A'...'Z' => {
                const refVar = this.scopeStack.getLast().variables.get(decl) orelse {
                    std.log.err("Error on Line {d} - Could not find variable: \"{s}\"", .{ this.currentLine, decl });
                    return .undefined;
                };
                return refVar.value;
            },
            '[' => {
                if (decl[decl.len - 1] != ']') {
                    @branchHint(.cold);
                    std.log.err("Error on line: {d} - Invalid Arrray syntax", .{this.currentLine});
                    @panic("Error Fatal");
                }
                return root.VariableValue{
                    .array = undefined, // TODO: Implement proper Array functionality
                };
            },
            else => {
                std.log.err("Error on line: {d} - Unknown Variable definition after `=` {s}\n", .{ this.currentLine, decl });
                @panic("Error Fatal");
            },
        }
        unreachable;
    }

    pub fn printAllVars(this: *@This()) void {
        var scope = this.scopeStack.getLast();
        for (scope.variables.values()) |v| {
            const val = v;
            std.debug.print("variable: name: |{s}|, value: |{any}| as String(|{s}|)\n", .{ val.name, val.value, if (val.value == .str) val.value.str else "@NONE" });
        }
    }
};

const TokenIterator = root.TokenIter;

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

pub fn runFn(exprStart: []const u8, interpreter: *Interpreter, tokenIter: *TokenIterator) void {
    var scope = interpreter.scopeStack.getLast();
    var func = scope.functions.get(exprStart) orelse interpreter.baseFunctions.get(exprStart) orelse {
        std.log.err("Function \"{s}\" could not be found.\nError on line {d}", .{ exprStart, interpreter.currentLine });
        return;
    };
    var i: u16 = 0;
    while (tokenIter.peek() != null and i < func.parameters.len) : (i += 1) {
        const token = tokenIter.peek().?;
        switch (token[0]) {
            '"' => {
                func.parameters[i].value = .{ .str = parseStr(tokenIter.rest()) catch @panic("panic") };
                _ = tokenIter.next();
            },
            'a'...'z', 'A'...'Z' => {
                const varName = if (token.len > 0 and token[token.len - 1] == '!')
                    token[0 .. token.len - 1]
                else
                    token;
                const varVal = scope.variables.get(varName) orelse blk: {
                    std.log.err("Variable \"{s}\" could not be found.\nError on line {d}\n", .{ token, interpreter.currentLine });
                    break :blk root.Variable{
                        .name = varName,
                        .type = .const_const,
                        .value = .undefined,
                    };
                };
                func.parameters[i].value = varVal.value;
                _ = tokenIter.next();
            },
            else => {
                _ = tokenIter.next();
            },
        }
    }
    if (std.mem.eql(u8, func.name, "print")) {
        const param = func.parameters[0];
        std.debug.print("PRINT: ", .{});
        switch (param.value) {
            .Int => |v| {
                std.debug.print("{d}\n", .{v});
            },
            .array => {
                std.log.warn("Arrays not yet supported!\n", .{}); // TODO: Support arrays
            },
            .bool => |v| {
                std.debug.print("{s}\n", .{if (v) "true" else "false"});
            },
            .str => |v| {
                std.debug.print("{s}\n", .{v});
            },
            .undefined => {
                std.log.warn("Value is undefined of {s}!\n", .{param.name});
            },
        }
    }
}

pub fn initPrintFn(this: *Interpreter) !void {
    const argVar = root.Variable{ .name = "print", .type = .const_const, .value = .undefined };
    var params = [1]root.Variable{argVar};
    const fun = root.Function{
        .name = "print",
        .body = "",
        .parameters = &params,
    };
    try this.baseFunctions.put("print", fun);
}

pub fn interpret(input: []const u8) !void {
    var lineIterator = std.mem.tokenizeAny(u8, input, "\n\r");
    const allocator = std.heap.page_allocator;
    var arenaAllocator = std.heap.ArenaAllocator.init(allocator);
    defer arenaAllocator.deinit();
    const arena = arenaAllocator.allocator();
    var rootScope = Scope{
        .arena = arena,
        .functions = .init(arena),
        .variables = .init(arena),
    };
    var scopeStack = ScopeStack.initCapacity(arena, 1) catch unreachable;
    var baseFunctions = std.StringArrayHashMap(root.Function).init(arena);
    var interpreter = Interpreter{
        .arena = arena,
        .lineIterator = &lineIterator,
        .scopeStack = &scopeStack,
        .baseFunctions = &baseFunctions,
    };
    try initPrintFn(&interpreter);
    try scopeStack.append(arena, &rootScope);
    defer interpreter.printAllVars();
    while (interpreter.nextLine()) |currentLine| {
        var tokenIterator = std.mem.tokenizeAny(u8, currentLine, " ()");

        while (tokenIterator.peek() != null) {
            const token = std.meta.stringToEnum(root.Token, tokenIterator.peek().?) orelse {
                Interpreter.determineIfIsFnAndRunIfItIs(tokenIterator.next().?, &interpreter, &tokenIterator);
                continue;
            };
            _ = tokenIterator.next();
            switch (token) {
                .@"fn", .function => {
                    const scope = interpreter.scopeStack.getLast();
                    const fnName = tokenIterator.next().?;
                    var args = try std.ArrayList(root.Variable).initCapacity(arena, 1);
                    while (tokenIterator.next()) |nextToken| {
                        switch (nextToken[nextToken.len - 1]) {
                            ',' => try args.append(arena, root.Variable{
                                .name = nextToken[0 .. nextToken.len - 2],
                                .type = .const_const,
                                .value = .undefined,
                            }),
                            '>' => break,
                            else => {},
                        }
                    }

                    const bodyStart = lineIterator.index;
                    _ = try interpreter.determineScopeEnd();
                    const bodyEnd = lineIterator.index;
                    const func = root.Function{
                        .body = interpreter.lineIterator.buffer[bodyStart..bodyEnd],
                        .name = fnName,
                        .parameters = args.items,
                    };
                    try scope.functions.put(func.name, func);
                },
                .@"const", .@"var" => |v| {
                    const v2 = std.meta.stringToEnum(root.Token, tokenIterator.next().?) orelse {
                        std.log.err("Error on line: {d}. Please follow up the {s} declaration with either a const or a var.", .{ interpreter.currentLine, if (v == .@"const") "const" else "var" });
                        @panic("Fatal Error");
                    };
                    const varType: root.VarType = if (v == .@"const" and v2 == .@"const") .const_const else if (v == .@"var" and v2 == .@"var") .var_var else if (v == .@"var" and v2 == .@"const") .var_const else .const_var;
                    var scope = interpreter.scopeStack.getLast();
                    const varName = tokenIterator.next().?;
                    if (tokenIterator.next().?[0] != '=') {
                        std.log.err("Error on Line: {d}. After a variable declaration a `=` is required but it wasn't provided.", .{interpreter.currentLine});
                        @panic("Error Fatal");
                    }
                    const varVal = interpreter.parseVarDecl(tokenIterator.rest());
                    try scope.variables.put(varName, root.Variable{ .name = varName, .type = varType, .value = varVal });
                },
                else => {},
            }
        }
    }
}
