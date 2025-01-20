const ulib = @import("ulib.zig");
const fcntl = @import("share").fcntl;

var buf: [512]u8 = undefined;

fn cat(fd: u32) !void {
    while (ulib.read(fd, &buf, @sizeOf(@TypeOf(buf)))) |n| {
        if (try ulib.write(ulib.stdout, &buf, @as(u32, @intCast(n))) != n) {
            try ulib.fputs(ulib.stderr, "cat: write error\n");
            ulib.exit();
        }
    } else |_| {
        try ulib.fputs(ulib.stderr, "cat: read error\n");
        ulib.exit();
    }
}

export fn main(argc: u32, argv: [*][*:0]const u8) void {
    if (argc <= 1) {
        cat(ulib.stdin) catch unreachable;
        ulib.exit();
    }
    for (1..argc) |i| {
        const fd = ulib.open(argv[i], fcntl.O_RDONLY) catch {
            ulib.fprint(ulib.stderr, "cat: cannot open {s}\n", .{argv[i]}) catch unreachable;
            ulib.exit();
        };
        cat(fd) catch unreachable;
        ulib.close(fd) catch unreachable;
    }
    ulib.exit();
}
