const std = @import("std");
const zGoM = @import("root.zig");
const Parser = @import("parser.zig");

pub fn main() !void {
    var allocator = std.heap.c_allocator;
    _ = &allocator;
    var arenaAlloc = std.heap.ArenaAllocator.init(allocator);
    const arena = arenaAlloc.allocator();

    const f = try std.fs.cwd().openFile("samples/test.gom", .{});
    defer f.close();
    var buffer: [2048]u8 = undefined;
    const n = try f.read(&buffer);
    std.debug.print("Contents: {s}\n", .{buffer[0..n]});
    var parser = Parser.init(arena);
    const parsed = try parser.parse(buffer[0..n]);
    std.debug.print("All Tokens:\n", .{});
    var identIdx: u16 = 0;
    var numIdx: u16 = 0;
    var strIdx: u16 = 0;
    for (parsed.Tokens) |t| {
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

test "Line Counting" {
    const f = try std.fs.cwd().openFile("samples/simple_line_test.gom", .{});
    defer f.close();
    var buffer: [2048]u8 = undefined;
    const n = try f.read(&buffer);
    std.debug.print("Contents: {s}\n", .{buffer[0..n]});
    try zGoM.interpret(buffer[0..n]);
}
