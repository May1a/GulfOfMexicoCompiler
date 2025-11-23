const std = @import("std");

const AST = @import("ast.zig");
const Parser = @import("parser.zig");
const zGoM = @import("root.zig");

fn printTokens(parsed: []Parser.Token) void {
    var identIdx: u16 = 0;
    var numIdx: u16 = 0;
    var strIdx: u16 = 0;
    std.debug.print("All Tokens:\n", .{});

    for (parsed) |t| {
        if (t.type == .Ident) {
            std.debug.print("{any} - {s}\n", .{ t, parsed.idents[identIdx] });
            identIdx += 1;
        } else if (t.type == .String) {
            std.debug.print("{any} - \"{s}\"\n", .{ t, parsed.strings[strIdx] });
            strIdx += 1;
        } else if (t.type == .Number) {
            std.debug.print("{any} - {d}\n", .{ t, parsed.numbers[numIdx] });
            numIdx += 1;
        } else std.debug.print("{any}\n", .{t});
    }
}

pub fn main() !void {
    try std.fs.File.stdout().writeAll("Hello, World!\n");
    var allocator = std.heap.page_allocator;
    _ = &allocator;
    var arenaAlloc = std.heap.ArenaAllocator.init(allocator);
    const arena = arenaAlloc.allocator();

    var args = try std.process.ArgIterator.initWithAllocator(arena);
    _ = args.skip();
    const fileN = args.next() orelse "samples/test.gom";
    const f = try std.fs.cwd().openFile(fileN, .{});
    defer f.close();
    var buffer: [2048]u8 = undefined;
    const n = try f.read(&buffer);
    std.debug.print("Contents: {s}\n", .{buffer[0..n]});
    var parser = Parser.init(arena);
    const parsed = try parser.parse(buffer[0..n]);

    var ast = AST.init(parsed, arena);
    const parsedRoot = try ast.parseRoot();
    std.debug.print("{any}\n", .{parsedRoot});
}

test "Line Counting" {
    const f = try std.fs.cwd().openFile("samples/simple_line_test.gom", .{});
    defer f.close();
    var buffer: [2048]u8 = undefined;
    const n = try f.read(&buffer);
    std.debug.print("Contents: {s}\n", .{buffer[0..n]});
    try zGoM.interpret(buffer[0..n]);
}
