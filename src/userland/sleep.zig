const ulib = @import("ulib.zig");
const std = @import("std");

pub export fn main(argc: u32, argv: [*][*:0]const u8) void {
    if (argc != 2) {
        ulib.fputs(ulib.stderr, "usage: sleep ticks...\n");
        ulib.exit();
    }

    const ticks = std.fmt.parseInt(u32, std.mem.sliceTo(argv[1], 0), 10) catch {
        ulib.fprint(ulib.stderr, "invalid ticks: {s}\n", .{argv[1]});
        ulib.exit();
    };
    _ = ulib.sleep(ticks);
    ulib.exit();
}
