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
    currentLine: u32 = 0,
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
                start = i;
            }
        }
    }
    return error.couldNotParseStr;
}

pub fn runFn(exprStart: []const u8, interpreter: *Interpreter, tokenIter: *TokenIterator) void {
    var scope = interpreter.scopeStack.getLast();
    var func = scope.functions.get(exprStart) orelse {
        std.log.err("Function \"{s}\" could not be found.\nError on line {d}", .{ exprStart, interpreter.currentLine });
        return;
        //  @panic("Fatal exit");
    };
    var i: u16 = 0;
    while (tokenIter.peek() != null and i < func.parameters.len) : (i += 1) {
        const token = tokenIter.peek().?;
        switch (token[0]) {
            '"' => {
                func.parameters[i].value = .{ .str = parseStr(tokenIter.rest()) catch @panic("panic") };
            },
            else => {},
        }
    }
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
    var interpreter = Interpreter{
        .arena = arena,
        .lineIterator = &lineIterator,
        .scopeStack = &scopeStack,
    };
    try scopeStack.append(arena, &rootScope);
    while (interpreter.nextLine()) |currentLine| {
        var tokenIterator = std.mem.tokenizeAny(u8, currentLine, " ()");

        while (tokenIterator.peek() != null) {
            const token = std.meta.stringToEnum(root.Token, tokenIterator.peek().?) orelse {
                runFn(tokenIterator.next().?, &interpreter, &tokenIterator);
                continue;
            };
            _ = tokenIterator.next();
            switch (token) {
                .@"fn", .function => {
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
                        .parameters = undefined,
                    };
                    _ = func;
                    //   @panic("done");
                },
                else => {},
            }
        }
    }
}
