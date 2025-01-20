const ulib = @import("ulib.zig");

export fn main(argc: u32, argv: [*][*:0]const u8) void {
    if (argc < 2) {
        ulib.fputs(ulib.stderr, "usage: mkdir dirs...\n") catch unreachable;
        ulib.exit();
    }
    for (1..argc) |i| {
        ulib.mkdir(argv[i]) catch {
            ulib.fprint(ulib.stderr, "mkdir: failed to create {s}\n", .{argv[i]}) catch unreachable;
            break;
        };
    }
    ulib.exit();
}
