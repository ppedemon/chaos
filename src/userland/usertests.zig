const ulib = @import("ulib.zig");
const share = @import("share");
const fcntl = share.fcntl;

const std = @import("std");

var buf: [8192]u8 = undefined;

fn argptest() void {
    const fd = ulib.open("init", fcntl.O_RDONLY);
    if (fd < 0) {
        ulib.fputs(ulib.stderr, "open failed\n");
        ulib.exit();
    }

    const ptr: usize = @intCast(ulib.sbrk(0));
    _ = ulib.read(@intCast(fd), @as([*]u8, @ptrFromInt(ptr)), 0xFFFF_FFFF);
    _ = ulib.close(@intCast(fd));
    ulib.puts("arg test passed\n");
}

fn createdelete() void {
    const P = 4;
    const N = 20;
    var name: [2:0]u8 = undefined;
    @memset(&name, 0);

    ulib.puts("createdelete test\n");

    for (0..P) |pi| {
        const pid = ulib.fork();
        if (pid < 0) {
            ulib.fputs(ulib.stderr, "fork failed\n");
            ulib.exit();
        }
        if (pid == 0) {
            name[0] = 'p' + @as(u8, @intCast(pi));
            for (0..N) |i| {
                name[1] = '0' + @as(u8, @intCast(i));
                const fd = ulib.open(@ptrCast(&name), fcntl.O_CREATE | fcntl.O_RDWR);
                if (fd < 0) {
                    ulib.fputs(ulib.stderr, "create failed\n");
                    ulib.exit();
                }
                _ = ulib.close(@intCast(fd));
                if (i > 0 and i % 2 == 0) {
                    name[1] = '0' + @as(u8, @intCast(i / 2));
                    if (ulib.unlink(@ptrCast(&name)) < 0) {
                        ulib.fputs(ulib.stderr, "unlink failed\n");
                        ulib.exit();
                    }
                }
            }
            ulib.exit();
        }
    }

    for (0..P) |_| {
        _ = ulib.wait();
    }

    for (0..N) |i| {
        for (0..P) |pi| {
            name[0] = 'p' + @as(u8, @intCast(pi));
            name[1] = '0' + @as(u8, @intCast(i));
            const fd = ulib.open(@ptrCast(&name), fcntl.O_RDONLY);
            if ((i == 0 or i >= N / 2) and fd < 0) {
                ulib.fprint(ulib.stderr, "oops: createdelere {s} didn't exist", .{name});
                ulib.exit();
            } else if (i >= 1 and i < N / 2 and fd >= 0) {
                ulib.fprint(ulib.stderr, "oops: createdelete {s} did exist", .{name});
                ulib.exit();
            }
            if (fd >= 0) {
                _ = ulib.close(@intCast(fd));
            }
        }
    }

    for (0..N) |i| {
        for (0..P) |pi| {
            name[0] = 'p' + @as(u8, @intCast(pi));
            name[1] = '0' + @as(u8, @intCast(i));
            _ = ulib.unlink(@ptrCast(&name));
        }
    }

    ulib.puts("createdelete ok\n");
}

fn linkunlink() void {
    ulib.puts("link/unink test\n");

    _ = ulib.unlink("x");
    const pid = ulib.fork();
    if (pid < 0) {
        ulib.fputs(ulib.stderr, "fork failed\n");
        ulib.exit();
    }

    var x: u32 = if (pid > 0) 1 else 97;
    for (0..100) |_| {
        x = x *% 1103515245 +% 12345;
        switch (x % 3) {
            0 => _ = ulib.close(@intCast(ulib.open("x", fcntl.O_CREATE | fcntl.O_RDWR))),
            1 => _ = ulib.link("cat", "x"),
            else => _ = ulib.unlink("x"),
        }
    }

    if (pid > 0) {
        _ = ulib.wait();
    } else {
        ulib.exit();
    }

    ulib.puts("linkunlink ok\n");
}

fn concreate() void {
    const N = 40;
    var file: [2:0]u8 = undefined;
    @memset(&file, 0);

    ulib.puts("concreate test\n");

    file[0] = 'C';
    for (0..N) |i| {
        file[1] = '0' + @as(u8, @intCast(i));
        _ = ulib.unlink(@ptrCast(&file));
        const pid = ulib.fork();
        if (pid > 0 and i % 3 == 1) {
            _ = ulib.link("C0", @ptrCast(&file));
        } else if (pid == 0 and i % 5 == 1) {
            _ = ulib.link("C0", @ptrCast(&file));
        } else {
            const fd = ulib.open(@ptrCast(&file), fcntl.O_CREATE | fcntl.O_RDWR);
            if (fd < 0) {
                ulib.fprint(ulib.stderr, "concreate create {s} failed\n", .{file});
                ulib.exit();
            }
            _ = ulib.close(@intCast(fd));
        }
        if (pid == 0) {
            ulib.exit();
        } else {
            _ = ulib.wait();
        }
    }

    var fa: [40]u8 = undefined;
    @memset(&fa, 0);

    var de = extern struct {
        inum: u16,
        name: [13:0]u8,
    }{
        .inum = 0,
        .name = undefined,
    };
    @memset(&de.name, 0);

    const fd = ulib.open(".", fcntl.O_RDONLY);
    var n: usize = 0;
    while (ulib.read(@intCast(fd), std.mem.asBytes(&de), @sizeOf(@TypeOf(de))) > 0) {
        if (de.inum == 0) {
            continue;
        }
        if (de.name[0] == 'C' and de.name[2] == 0) {
            const i = de.name[1] - '0';
            if (i < 0 or i >= @sizeOf(@TypeOf(fa))) {
                ulib.fprint(ulib.stderr, "concreate weird file {s}\n", .{de.name});
                ulib.exit();
            }
            if (fa[i] != 0) {
                ulib.fprint(ulib.stderr, "concreate duplicate file {s}\n", .{de.name});
            }
            fa[i] = 1;
            n += 1;
        }
    }

    if (n != N) {
        ulib.fputs(ulib.stderr, "concreate not enough file in directory listing\n");
        ulib.exit();
    }

    for (0..N) |i| {
        file[1] = '0' + @as(u8, @intCast(i));
        const pid = ulib.fork();
        if (pid < 0) {
            ulib.fputs(ulib.stderr, "fork failed\n");
            ulib.exit();
        }
        if ((i % 3 == 0 and pid == 0) or (i % 3 == 1 and pid != 0)) {
            _ = ulib.close(@intCast(ulib.open(@ptrCast(&file), fcntl.O_RDONLY)));
            _ = ulib.close(@intCast(ulib.open(@ptrCast(&file), fcntl.O_RDONLY)));
            _ = ulib.close(@intCast(ulib.open(@ptrCast(&file), fcntl.O_RDONLY)));
            _ = ulib.close(@intCast(ulib.open(@ptrCast(&file), fcntl.O_RDONLY)));
        } else {
            _ = ulib.unlink(@ptrCast(&file));
            _ = ulib.unlink(@ptrCast(&file));
            _ = ulib.unlink(@ptrCast(&file));
            _ = ulib.unlink(@ptrCast(&file));
        }
        if (pid == 0) {
            ulib.exit();
        } else {
            _ = ulib.wait();
        }
    }

    ulib.puts("concreate ok\n");
}

fn fourfiles() void {
    const P = 4;
    const names: [4][*:0]const u8 = [_][*:0]const u8{ "f0", "f1", "f2", "f3" };

    ulib.puts("fourfiles test\n");

    for (0..P) |pi| {
        const fname = names[pi];
        _ = ulib.unlink(fname);

        const pid = ulib.fork();
        if (pid < 0) {
            ulib.fputs(ulib.stderr, "fork failed\n");
            ulib.exit();
        }

        if (pid == 0) {
            const fd = ulib.open(fname, fcntl.O_CREATE | fcntl.O_RDWR);
            if (fd < 0) {
                ulib.fputs(ulib.stderr, "create failed\n");
                ulib.exit();
            }
            @memset(buf[0..512], '0' + @as(u8, @intCast(pi)));
            for (0..12) |_| {
                const n = ulib.write(@intCast(fd), @ptrCast(&buf), 500);
                if (n != 500) {
                    ulib.fprint(ulib.stderr, "write failed {}\n", .{n});
                    ulib.exit();
                }
            }
            ulib.exit();
        }
    }

    for (0..P) |_| {
        _ = ulib.wait();
    }

    for (0..P) |pi| {
        const fname = names[pi];
        const fd = ulib.open(fname, fcntl.O_RDONLY);
        var total: u32 = 0;
        while (true) {
            const n = ulib.read(@intCast(fd), @ptrCast(&buf), @sizeOf(@TypeOf(buf)));
            if (n <= 0) {
                break;
            }
            for (0..@intCast(n)) |j| {
                if (buf[j] != '0' + @as(u8, @intCast(pi))) {
                    ulib.fputs(ulib.stderr, "wrong char\n");
                    ulib.exit();
                }
            }
            total += @intCast(n);
        }
        _ = ulib.close(@intCast(fd));
        if (total != 12*500) {
            ulib.fprint(ulib.stderr, "wrong length {}\n", .{total});
            ulib.exit();
        }
        _ = ulib.unlink(fname);
    }

    ulib.puts("fourfiles ok\n");
}

pub export fn main() void {
    ulib.puts("usertests starting\n");

    // if (ulib.open("usertests.ran", fcntl.O_RDONLY) >= 0) {
    //     ulib.puts("already run user tests, rebuild fs.img\n");
    //     ulib.exit();
    // }
    // _ = ulib.close(@intCast(ulib.open("usertests.ran", fcntl.O_CREATE)));

    argptest();
    createdelete();
    linkunlink();
    concreate();
    fourfiles();

    ulib.exit();
}
