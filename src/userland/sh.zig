const ulib = @import("ulib.zig");

export fn main(argc: u32, argv: [*][*:0]const u8) callconv(.C) void {
    for (0..argc) |i| {
        ulib.print("args[{}] = {s}\n", .{ i, argv[i] });
    }
    while (true) {}
}
