const ulib = @import("ulib.zig");

export fn main(argc: u32, argv: [*][*:0]const u8) void {
    for (1..argc) |i| {
        const end = if (i + 1 < argc) " " else "\n";
        ulib.print("{s}{s}", .{ argv[i], end });
    }
    ulib.exit();
}
