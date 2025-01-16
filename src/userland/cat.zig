const ulib = @import("ulib.zig");

var buf: [512]u8 = undefined;

fn cat(fd: u32) void {
    var n: i32 = ulib.read(fd, &buf, @sizeOf(@TypeOf(buf)));
    while (n > 0) {
        if (ulib.write(ulib.stdout, &buf, @as(u32, @intCast(n))) != n) {
            ulib.fputs(ulib.stderr, "cat: write error\n");
            ulib.exit();
        }
        n = ulib.read(fd, &buf, @sizeOf(@TypeOf(buf)));
    }
    if (n < 0) {
        ulib.fputs(ulib.stderr, "cat: read error\n");
        ulib.exit();
    }
}

export fn main(argc: u32, argv: [*][*:0]const u8) void {
    if (argc <= 1) {
        cat(ulib.stdin);
        ulib.exit();
    }
    for (1..argc) |i| {
        const result = ulib.open(argv[i], ulib.O_RDONLY);
        if (result < 0) {
            ulib.fprint(ulib.stderr, "cat: cannot open {s}\n", .{argv[i]});
            ulib.exit();
        }
        const fd: u32 = @intCast(result);
        cat(@intCast(fd));
        _ = ulib.close(fd);
    }
    ulib.exit();
}
