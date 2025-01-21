const ulib = @import("ulib.zig");
const share = @import("share");
const fcntl = share.fcntl;

fn argptest() void {
    const fd = ulib.open("init", fcntl.O_RDONLY);
    if (fd < 0) {
        ulib.fputs(ulib.stderr, "open failed\n");
        ulib.exit();
    }

    const ptr: usize = @intCast(ulib.sbrk(0));
    _ = ulib.read(@intCast(fd), @as([*]u8, @ptrFromInt(ptr)), 0xFFFF_FFFF);
    _ = ulib.close(@intCast(fd));
}

pub export fn main() void {
    ulib.puts("usertests starting\n");

    if (ulib.open("usertests.ran", fcntl.O_RDONLY) >= 0) {
        ulib.puts("already run user tests, rebuild fs.img\n");
        ulib.exit();
    }
    _ = ulib.close(@intCast(ulib.open("usertests.ran", fcntl.O_CREATE)));

    argptest();

    ulib.exit();
}
