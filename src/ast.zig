const std = @import("std");
const ArrayList = std.ArrayList;
const this = @This();

const Value = union(enum) {
    Str: []u8,
    Int: i32,
    Array: ArrayList(Value),
};

const Variable = struct {
    name: []const u8,
    value: Value,
};

const Function = struct {};

const Node = union(enum) {
    variable: Variable,
};

const AstNode = .{ Node, u16 };
