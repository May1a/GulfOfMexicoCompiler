const I = @This();
const AST = @import("ast.zig");
const std = @import("std");

const Allocator = std.mem.Allocator;

const Scope = struct {
    vars: AST.Variable,
    pScope: ?*Scope,
};

ast: *const AST.AstNode,
allocator: Allocator,

pub fn init(ast: *const AST.AstNode, allocator: Allocator) I {
    const interpreter: I = .{ .allocator = allocator, .ast = ast };
    return interpreter;
}

pub fn run(this: *I) !void {
    // @breakpoint();
    const rNode = this.ast.*.RootNode;
    std.debug.print("HELLO!!!!\n\n", .{});
    for (rNode.*) |n| {
        std.debug.print("{any}\n", .{n});
    }
}
