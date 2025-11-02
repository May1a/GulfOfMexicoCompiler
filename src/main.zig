const std = @import("std");
const zGoM = @import("interpreter.zig");

pub fn main() !void {
    const f = try std.fs.cwd().openFile("samples/test.gom", .{});
    defer f.close();
    var buffer: [2048]u8 = undefined;
    const n = try f.read(&buffer);
    std.debug.print("Contents: {s}\n", .{buffer[0..n]});
    try zGoM.interpret(buffer[0..n]);
}

test "Line Counting" {
    const f = try std.fs.cwd().openFile("samples/simple_line_test.gom", .{});
    defer f.close();
    var buffer: [2048]u8 = undefined;
    const n = try f.read(&buffer);
    std.debug.print("Contents: {s}\n", .{buffer[0..n]});
    try zGoM.interpret(buffer[0..n]);
}
