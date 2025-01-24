//! Torture tests for kernel
//! Differences with xv86 codebase:
//!
//!  (1) No point in running bsstest: ANSI C ensures uninitialized static data will be zeroed out,
//!      but that doesn't hold with Zig. The Zig compiler doesn't like you accessing undefined data.
//!      Doing that is undefined behavious, so you can't simply assume they will be zeros.
//!
//!  (2) validatetest attempts to crash the kernel by passing args to sleep and link syscalls from
//!      invalid memory addresses, including 0. Zig is very pedantic about casting a 0 to a pointer
//!      so it isn't possible to use zero for link (but possible for sleep, since we are invoking
//!      it from an asm code wrapper where we declare the pointer as allowzero).

const ulib = @import("ulib.zig");
const share = @import("share");
const fcntl = share.fcntl;

const std = @import("std");

var buf: [8192]u8 align(@alignOf(u32)) = undefined;

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
        if (total != 12 * 500) {
            ulib.fprint(ulib.stderr, "wrong length {}\n", .{total});
            ulib.exit();
        }
        _ = ulib.unlink(fname);
    }

    ulib.puts("fourfiles ok\n");
}

fn sharedfd() void {
    var data: [10]u8 = undefined;

    ulib.puts("sharedfd test\n");

    _ = ulib.unlink("sharedfd");
    var fd = ulib.open("sharedfd", fcntl.O_CREATE | fcntl.O_RDWR);
    if (fd < 0) {
        ulib.fputs(ulib.stderr, "cannot open sharedfd for writing");
        return;
    }
    const pid = ulib.fork();
    @memset(&data, if (pid == 0) 'c' else 'p');
    for (0..1000) |_| {
        if (ulib.write(@intCast(fd), @ptrCast(&data), @sizeOf(@TypeOf(data))) != @sizeOf(@TypeOf(data))) {
            ulib.fputs(ulib.stderr, "write sharedfd failed\n");
            break;
        }
    }

    if (pid == 0) {
        ulib.exit();
    } else {
        _ = ulib.wait();
    }

    _ = ulib.close(@intCast(fd));
    fd = ulib.open("sharedfd", fcntl.O_RDONLY);
    if (fd < 0) {
        ulib.fputs(ulib.stderr, "cannot open sharedfd for reading\n");
        return;
    }
    var nc: u32 = 0;
    var np: u32 = 0;
    while (ulib.read(@intCast(fd), @ptrCast(&data), @sizeOf(@TypeOf(data))) > 0) {
        for (data) |c| {
            if (c == 'c') {
                nc += 1;
            } else if (c == 'p') {
                np += 1;
            }
        }
    }

    _ = ulib.close(@intCast(fd));
    _ = ulib.unlink("sharedfd");
    if (nc == 10_000 and np == 10_000) {
        ulib.puts("sharedfd ok\n");
    } else {
        ulib.print("sharedfd oops {} {}\n", .{ nc, np });
        ulib.exit();
    }
}

fn bigargtest() void {
    const MAXARG = 32;
    const static = struct {
        var argv: [MAXARG]?[*:0]const u8 = undefined;
    };

    _ = ulib.unlink("bigarg-ok");

    const pid = ulib.fork();
    if (pid == 0) {
        for (0..MAXARG - 1) |i| {
            static.argv[i] = "bigargs test: failed\n" ++ [_]u8{' '} ** 199;
        }
        static.argv[MAXARG - 1] = null;
        ulib.puts("bigarg test\n");
        _ = ulib.exec("echo", &static.argv);
        ulib.puts("bigarg test ok\n");
        const fd = ulib.open("bigarg-ok", fcntl.O_CREATE);
        _ = ulib.close(@intCast(fd));
        ulib.exit();
    } else if (pid < 0) {
        ulib.fputs(ulib.stderr, "bigarg test: fork failed!\n");
        ulib.exit();
    }

    _ = ulib.wait();
    const fd = ulib.open("bigarg-ok", fcntl.O_RDONLY);
    if (fd < 0) {
        ulib.fputs(ulib.stderr, "bigarg test failed\n");
        ulib.exit();
    }
    _ = ulib.close(@intCast(fd));
    _ = ulib.unlink("bigarg-ok");
}

fn bigwrite() void {
    ulib.puts("bigwrite test\n");

    _ = ulib.unlink("bigwrite");
    var size: usize = 499;
    while (size < 12 * 512) : (size += 471) {
        const fd = ulib.open("bigwrite", fcntl.O_CREATE | fcntl.O_RDWR);
        if (fd < 0) {
            ulib.fputs(ulib.stderr, "cannot create big write");
            ulib.exit();
        }
        for (0..2) |_| {
            const n = ulib.write(@intCast(fd), @ptrCast(&buf), size);
            if (n != size) {
                ulib.fprint(ulib.stderr, "write({}) returned {}\n", .{ size, n });
                ulib.exit();
            }
        }
        _ = ulib.close(@intCast(fd));
        _ = ulib.unlink("bigwrite");
    }

    ulib.puts("bigwrite ok\n");
}

fn sbrktest() void {
    ulib.puts("sbrk test\n");

    const oldbrk: usize = @intCast(ulib.sbrk(0));

    // can we ask for less than 1 page?
    var a: usize = @intCast(ulib.sbrk(0));
    for (0..5000) |i| {
        const b: usize = @intCast(ulib.sbrk(1));
        if (b != a) {
            ulib.fprint(ulib.stderr, "sbrk test failed {} 0x{x} 0x{x}", .{ i, a, b });
            ulib.exit();
        }
        @as(*u8, @ptrFromInt(b)).* = 1;
        a = b + 1;
    }
    const pid = ulib.fork();
    if (pid < 0) {
        ulib.fputs(ulib.stderr, "sbrk test fork failed\n");
        ulib.exit();
    }
    var c: usize = @intCast(ulib.sbrk(1));
    c = @intCast(ulib.sbrk(1));
    if (c != a + 1) {
        ulib.fputs(ulib.stderr, "sbrk test failed post-fork\n");
        ulib.exit();
    }
    if (pid == 0) {
        ulib.exit();
    }
    _ = ulib.wait();

    // can we grow addr space to 100 Mb?
    const BIG: usize = 100 * 1024 * 1024;
    a = @intCast(ulib.sbrk(0));
    const amount: isize = @intCast(BIG - a);
    const p: usize = @intCast(ulib.sbrk(amount));
    if (p != a) {
        ulib.fputs(ulib.stderr, "sbrk test failed to grow big addr space\n");
        ulib.exit();
    }
    const lastaddr: *u8 = @ptrFromInt(BIG - 1);
    lastaddr.* = 99;

    // can we dealloc?
    a = @intCast(ulib.sbrk(0));
    c = @intCast(ulib.sbrk(-4096));
    if (c == 0xFFFF_FFFF) {
        ulib.fputs(ulib.stderr, "sbrk test could not deallocate\n");
        ulib.exit();
    }
    c = @intCast(ulib.sbrk(0));
    if (c != a - 4096) {
        ulib.fprint(ulib.stderr, "sbrk test deallocation wrong address, a = 0x{x}, c = 0x{x}", .{ a, c });
        ulib.exit();
    }

    // can we realloc page dealloc'ed above?
    a = @intCast(ulib.sbrk(0));
    c = @intCast(ulib.sbrk(4096));
    if (c != a or @as(usize, @intCast(ulib.sbrk(0))) != a + 4096) {
        ulib.fprint(ulib.stderr, "sbrk realloc failed, a = 0x{x}, c = 0x{x}", .{ a, c });
        ulib.exit();
    }
    if (lastaddr.* == 99) {
        ulib.fputs(ulib.stderr, "sbrk dealloc didn't actually deallocate\n");
        ulib.exit();
    }
    a = @intCast(ulib.sbrk(0));
    c = @intCast(ulib.sbrk(-@as(isize, @intCast(@as(usize, @intCast(ulib.sbrk(0))) - oldbrk))));
    if (c != a) {
        ulib.fprint(ulib.stderr, "sbrk downsize failed, a = 0x{x}, c = 0x{x}", .{ a, c });
        ulib.exit();
    }

    // Can we read kernel mem?
    const KERNBASE: usize = 0x8000_0000;
    a = KERNBASE;
    while (a < KERNBASE + 2_000_000) : (a += 50_000) {
        const ppid: u32 = @intCast(ulib.getpid());
        const mypid = ulib.fork();
        if (mypid < 0) {
            ulib.fputs(ulib.stderr, "fork failed\n");
            ulib.exit();
        }
        if (mypid == 0) {
            const ptr: *u8 = @ptrFromInt(a);
            ulib.fprint(ulib.stderr, "oops cloud read 0x{x} = 0x{x}\n", .{ a, ptr.* });
            _ = ulib.kill(ppid);
            ulib.exit();
        }
        _ = ulib.wait();
    }

    // Does the system clean last failed alloc when running out of memory?
    var fds: [2]u32 = undefined;
    var pids: [10]i32 = undefined;
    var scratch: u8 = undefined;
    if (ulib.pipe(@ptrCast(&fds)) != 0) {
        ulib.fputs(ulib.stderr, "pipe() failed\n");
        ulib.exit();
    }
    for (0..pids.len) |i| {
        pids[i] = ulib.fork();
        if (pids[i] == 0) {
            const curr: usize = @intCast(ulib.sbrk(0));
            _ = ulib.sbrk(@intCast(BIG - curr));
            _ = ulib.write(fds[1], "x", 1);
            // Child: wait here until killed
            while (true) {
                _ = ulib.sleep(1000);
            }
        }
        if (pids[i] != -1) {
            _ = ulib.read(fds[0], @ptrCast(&scratch), 1);
        }
    }
    // If failed allocations free allocated paged, we should be able to allocate here
    c = @intCast(ulib.sbrk(4096));
    for (0..pids.len) |i| {
        if (pids[i] == -1) {
            continue;
        }
        // Kill children waiting above
        _ = ulib.kill(@intCast(pids[i]));
        _ = ulib.wait();
    }
    if (c == 0xFFFF_FFFF) {
        ulib.fputs(ulib.stderr, "failed sbrk leaked memory\n");
        ulib.exit();
    }

    // Cleanup
    const currsz: usize = @intCast(ulib.sbrk(0));
    if (currsz > oldbrk) {
        _ = ulib.sbrk(-@as(isize, @intCast(currsz - oldbrk)));
    }

    ulib.puts("sbrk test ok\n");
}

fn validateint(p: *allowzero usize) void {
    asm volatile (
        \\ movl $13, %eax
        \\ movl %esp, %ebx
        \\ movl %[addr], %ecx
        \\ movl (%ecx), %esp
        \\ int $64
        \\ movl %ebx, %esp
        :
        : [addr] "r" (p),
        : "{ebx}", "{ecx}"
    );
}

fn validatetest() void {
    ulib.puts("validate test\n");

    const hi = 1100 * 1024;
    var p: usize = 0;
    while (p < hi) : (p += 4096) {
        const pid = ulib.fork();
        if (pid == 0) {
            validateint(@ptrFromInt(p));
            ulib.exit();
        }
        _ = ulib.sleep(0);
        _ = ulib.sleep(0);
        _ = ulib.kill(@intCast(pid));
        _ = ulib.wait();

        if (p > 0 and ulib.link("nosuchfile", @ptrFromInt(p)) != -1) {
            ulib.fputs(ulib.stderr, "link should not succeed\n");
            ulib.exit();
        }
    }

    ulib.puts("validate ok\n");
}

fn opentest() void {
    ulib.puts("open test\n");

    var fd = ulib.open("echo", fcntl.O_RDONLY);
    if (fd < 0) {
        ulib.fputs(ulib.stderr, "open echo failed\n");
        ulib.exit();
    }
    _ = ulib.close(@intCast(fd));
    fd = ulib.open("bogus", fcntl.O_RDONLY);
    if (fd >= 0) {
        ulib.fputs(ulib.stderr, "open bogus succeeded\n");
        ulib.exit();
    }

    ulib.puts("open test ok\n");
}

fn writetest() void {
    ulib.puts("small file test\n");

    var r = ulib.open("small", fcntl.O_CREATE | fcntl.O_RDWR);
    if (r < 0) {
        ulib.puts("create small failed\n");
        ulib.exit();
    }
    var fd: u32 = @intCast(r);
    for (0..100) |i| {
        if (ulib.write(fd, "aaaaaaaaaa", 10) != 10) {
            ulib.fprint(ulib.stderr, "write aa {} failed\n", .{i});
            ulib.exit();
        }
        if (ulib.write(fd, "bbbbbbbbbb", 10) != 10) {
            ulib.fprint(ulib.stderr, "write bb {} failed\n", .{i});
            ulib.exit();
        }
    }
    ulib.puts("writes ok\n");
    _ = ulib.close(fd);

    r = ulib.open("small", fcntl.O_RDONLY);
    if (r >= 0) {
        ulib.puts("open small succeeded\n");
    } else {
        ulib.fputs(ulib.stderr, "open small failed\n");
        ulib.exit();
    }
    fd = @intCast(r);
    const n = ulib.read(fd, @ptrCast(&buf), 2000);
    if (n == 2000) {
        ulib.puts("read succeeded\n");
    } else {
        ulib.fputs(ulib.stderr, "read failed\n");
        ulib.exit();
    }
    _ = ulib.close(fd);

    if (ulib.unlink("small") < 0) {
        ulib.fputs(ulib.stderr, "unlink small failed\n");
        ulib.exit();
    }

    ulib.puts("small file test ok\n");
}

fn writetest1() void {
    ulib.puts("big files test\n");

    const MAXFILE = 140;
    var r = ulib.open("big", fcntl.O_CREATE | fcntl.O_RDWR);
    if (r < 0) {
        ulib.puts("create big failed\n");
        ulib.exit();
    }
    var fd: u32 = @intCast(r);
    for (0..MAXFILE) |i| {
        @as([*]u32, @ptrCast(&buf))[0] = i;
        if (ulib.write(fd, @ptrCast(&buf), 512) != 512) {
            ulib.fputs(ulib.stderr, "write big file failed\n");
            ulib.exit();
        }
    }
    _ = ulib.close(fd);

    r = ulib.open("big", fcntl.O_RDWR);
    if (r < 0) {
        ulib.puts("open big failed\n");
        ulib.exit();
    }
    fd = @intCast(r);
    var n: usize = 0;
    while (true) : (n += 1) {
        const i = ulib.read(fd, @ptrCast(&buf), 512);
        if (i == 0) {
            if (n == MAXFILE) {
                break;
            }
            ulib.fprint(ulib.stderr, "read only {} blocks from big\n", .{n});
            ulib.exit();
        } else if (i != 512) {
            ulib.fprint(ulib.stderr, "read failed {}\n", .{i});
            ulib.exit();
        }
        const x = @as([*]u32, @ptrCast(&buf))[0];
        if (x != n) {
            ulib.fprint(ulib.stderr, "read content of block {} is {}\n", .{ n, x });
            ulib.exit();
        }
    }
    _ = ulib.close(fd);

    if (ulib.unlink("big") < 0) {
        ulib.fputs(ulib.stderr, "unlink big failed\n");
        ulib.exit();
    }

    ulib.puts("big files ok\n");
}

fn createtest() void {
    ulib.puts("create test\n");

    var name: [2:0]u8 = undefined;
    @memset(&name, 0);
    name[0] = 'a';
    for (0..52) |i| {
        name[1] = '0' + @as(u8, @intCast(i));
        const fd = ulib.open(@ptrCast(&name), fcntl.O_CREATE | fcntl.O_RDWR);
        _ = ulib.close(@intCast(fd));
    }
    for (0..52) |i| {
        name[1] = '0' + @as(u8, @intCast(i));
        _ = ulib.unlink(@ptrCast(&name));
    }

    ulib.puts("create test ok\n");
}

fn openiputtest() void {
    ulib.puts("openiput test\n");

    if (ulib.mkdir("oidir") < 0) {
        ulib.fputs(ulib.stderr, "mkdir oidir failed\n");
        ulib.exit();
    }
    const pid = ulib.fork();
    if (pid < 0) {
        ulib.fputs(ulib.stderr, "fork failed\n");
        ulib.exit();
    }
    if (pid == 0) {
        const fd = ulib.open("oidir", fcntl.O_RDWR);
        if (fd >= 0) {
            ulib.fputs(ulib.stderr, "open dir for writing succeeded\n");
            ulib.exit();
        }
        ulib.exit();
    }
    _ = ulib.sleep(1);
    if (ulib.unlink("oidir") != 0) {
        ulib.fputs(ulib.stderr, "unlink failed\n");
        ulib.exit();
    }
    _ = ulib.wait();

    ulib.puts("openiput test ok\n");
}

fn exitiputtest() void {
    ulib.puts("exitiput \n");

    const pid = ulib.fork();
    if (pid < 0) {
        ulib.fputs(ulib.stderr, "fork failed\n");
        ulib.exit();
    }
    if (pid == 0) {
        if (ulib.mkdir("iputdir") < 0) {
            ulib.fputs(ulib.stderr, "mkdir iputdir failed\n");
            ulib.exit();
        }
        if (ulib.chdir("iputdir") < 0) {
            ulib.fputs(ulib.stderr, "chdir iputdir failed\n");
            ulib.exit();
        }
        if (ulib.unlink("../iputdir") < 0) {
            ulib.fputs(ulib.stderr, "unlink ../iputdir failed\n");
            ulib.exit();
        }
        ulib.exit();
    }
    _ = ulib.wait();

    ulib.puts("exitiput test ok\n");
}

fn iputtest() void {
    ulib.puts("iput test \n");

    if (ulib.mkdir("iputdir") < 0) {
        ulib.fputs(ulib.stderr, "mkdir iputdir failed\n");
        ulib.exit();
    }
    if (ulib.chdir("iputdir") < 0) {
        ulib.fputs(ulib.stderr, "chdir iputdir failed\n");
        ulib.exit();
    }
    if (ulib.unlink("../iputdir") < 0) {
        ulib.fputs(ulib.stderr, "unlink ../iputdir failed\n");
        ulib.exit();
    }
    if (ulib.chdir("/") < 0) {
        ulib.fputs(ulib.stderr, "chdir / failed\n");
        ulib.exit();
    }

    ulib.puts("iput test ok\n");
}

fn mem() void {
    ulib.puts("mem test\n");

    const ppid = ulib.getpid();
    const pid = ulib.fork();
    if (pid == 0) {
        var m1: usize = 0;
        var m2: usize = 0;
        while (true) {
            m2 = ulib.malloc(10001);
            if (m2 == 0) {
                break;
            }
            @as(*usize, @ptrFromInt(m2)).* = m1;
            m1 = m2;
        }
        while (m1 != 0) {
            m2 = @as(*usize, @ptrFromInt(m1)).*;
            ulib.free(m1);
            m1 = m2;
        }
        m1 = ulib.malloc(1024 * 20);
        if (m1 == 0) {
            ulib.fputs(ulib.stderr, "can not allocate mem\n");
            _ = ulib.kill(@intCast(ppid));
            ulib.exit();
        }
        ulib.free(m1);
        ulib.puts("mem test ok\n");
        ulib.exit();
    }
    _ = ulib.wait();
}

fn pipe1() void {
    ulib.puts("pipe1 test\n");

    var fds: [2]u32 = undefined;
    if (ulib.pipe(@ptrCast(&fds)) != 0) {
        ulib.fputs(ulib.stderr, "pipe() failed\n");
        ulib.exit();
    }

    var seq: u8 = 0;
    const pid = ulib.fork();
    if (pid == 0) {
        _ = ulib.close(fds[0]);
        for (0..5) |_| {
            for (0..1033) |i| {
                buf[i] = seq;
                seq +%= 1;
            }
            if (ulib.write(fds[1], @ptrCast(&buf), 1033) != 1033) {
                ulib.fputs(ulib.stderr, "pipe1 oops write\n");
                ulib.exit();
            }
        }
        ulib.exit();
    } else if (pid > 0) {
        _ = ulib.close(fds[1]);
        var total: u32 = 0;
        var cc: u32 = 1;
        while (true) {
            const n = ulib.read(fds[0], @ptrCast(&buf), cc);
            if (n <= 0) {
                break;
            }
            for (0..@intCast(n)) |i| {
                if (buf[i] != seq) {
                    ulib.fputs(ulib.stderr, "pipe1 oops read\n");
                    ulib.exit();
                }
                seq +%= 1;
            }
            total += @intCast(n);
            cc = @min(@sizeOf(@TypeOf(buf)), cc * 2);
        }
        if (total != 5 * 1033) {
            ulib.fprint(ulib.stderr, "pipe1 oops total = {}\n", .{total});
            ulib.exit();
        }
        _ = ulib.close(fds[0]);
        _ = ulib.wait();
    } else {
        ulib.fputs(ulib.stderr, "fork failed\n");
        ulib.exit();
    }

    ulib.puts("pipe1 test ok\n");
}

fn preempt() void {
    ulib.puts("preempt: ");

    const pid1: u32 = @intCast(ulib.fork());
    if (pid1 == 0) {
        while (true) {}
    }

    const pid2: u32 = @intCast(ulib.fork());
    if (pid2 == 0) {
        while (true) {}
    }

    var fds: [2]u32 = undefined;
    _ = ulib.pipe(@ptrCast(&fds));
    const pid3: u32 = @intCast(ulib.fork());
    if (pid3 == 0) {
        _ = ulib.close(fds[0]);
        if (ulib.write(fds[1], "x", 1) != 1) {
            ulib.fputs(ulib.stderr, "preempt write error\n");
        }
        _ = ulib.close(fds[1]);
        while (true) {}
    }

    _ = ulib.close(fds[1]);
    if (ulib.read(fds[0], @ptrCast(&buf), @sizeOf(@TypeOf(buf))) != 1) {
        ulib.fputs(ulib.stderr, "preempt read error\n");
        return;
    }
    _ = ulib.close(fds[0]);

    ulib.puts("kill...");
    _ = ulib.kill(pid1);
    _ = ulib.kill(pid2);
    _ = ulib.kill(pid3);

    ulib.puts("wait... ");
    _ = ulib.wait();
    _ = ulib.wait();
    _ = ulib.wait();

    ulib.puts("preempt ok\n");
}

fn exitwait() void {
    ulib.puts("exitwait\n");

    for (0..100) |_| {
        const pid = ulib.fork();
        if (pid < 0) {
            ulib.fputs(ulib.stderr, "fork failed\n");
            return;
        }
        if (pid > 0) {
            if (ulib.wait() != pid) {
                ulib.fputs(ulib.stderr, "wait got wrong pid\n");
                return;
            }
        } else {
            ulib.exit();
        }
    }

    ulib.puts("exitwait ok\n");
}

fn rmdot() void {
    ulib.puts("rmdot test\n");

    if (ulib.mkdir("dots") != 0) {
        ulib.fputs(ulib.stderr, "mkdir dots failed!\n");
        ulib.exit();
    }
    if (ulib.chdir("dots") != 0) {
        ulib.fputs(ulib.stderr, "chdir dots failed!\n");
        ulib.exit();
    }
    if (ulib.unlink(".") == 0) {
        ulib.fputs(ulib.stderr, "rm . worked!\n");
        ulib.exit();
    }
    if (ulib.unlink("..") == 0) {
        ulib.fputs(ulib.stderr, "rm .. worked!\n");
        ulib.exit();
    }
    if (ulib.chdir("/") != 0) {
        ulib.fputs(ulib.stderr, "chdir / failed\n");
        ulib.exit();
    }
    if (ulib.unlink("dots/.") == 0) {
        ulib.fputs(ulib.stderr, "rm dots/. worked!\n");
        ulib.exit();
    }
    if (ulib.unlink("dots/..") == 0) {
        ulib.fputs(ulib.stderr, "rm dots/.. worked!\n");
        ulib.exit();
    }
    if (ulib.unlink("dots") != 0) {
        ulib.fputs(ulib.stderr, "rm dots failed!\n");
        ulib.exit();
    }

    ulib.puts("rmdot test ok\n");
}

fn fourteen() void {
    ulib.puts("fourteen test\n");

    if (ulib.mkdir("12345678901234") != 0) {
        ulib.fputs(ulib.stderr, "mkdir 12345678901234 failed\n");
        ulib.exit();
    }
    if (ulib.mkdir("12345678901234/123456789012345") != 0) {
        ulib.fputs(ulib.stderr, "mkdir 12345678901234/123456789012345 failed\n");
        ulib.exit();
    }
    var fd = ulib.open("123456789012345/123456789012345/123456789012345", fcntl.O_CREATE);
    if (fd < 0) {
        ulib.fputs(ulib.stderr, "create 123456789012345/123456789012345/123456789012345 failed\n");
        ulib.exit();
    }
    _ = ulib.close(@intCast(fd));
    fd = ulib.open("12345678901234/12345678901234/12345678901234", fcntl.O_RDONLY);
    if (fd < 0) {
        ulib.fputs(ulib.stderr, "open 12345678901234/12345678901234/12345678901234 failed\n");
        ulib.exit();
    }
    _ = ulib.close(@intCast(fd));

    if (ulib.mkdir("12345678901234/12345678901234") == 0) {
        ulib.fputs(ulib.stderr, "mkdir 12345678901234/12345678901234 succeeded!\n");
        ulib.exit();
    }
    if (ulib.mkdir("123456789012345/12345678901234") == 0) {
        ulib.fputs(1, "mkdir 12345678901234/123456789012345 succeeded!\n");
        ulib.exit();
    }

    ulib.puts("fourteen test ok\n");
}

fn bigfile() void {
    ulib.puts("bigfile test\n");

    _ = ulib.unlink("bigfile");
    var r = ulib.open("bigfile", fcntl.O_CREATE | fcntl.O_RDWR);
    if (r < 0) {
        ulib.fputs(ulib.stderr, "cannot create bigfile\n");
        ulib.exit();
    }
    var fd: u32 = @intCast(r);
    for (0..20) |i| {
        @memset(buf[0..600], @intCast(i));
        if (ulib.write(fd, @ptrCast(&buf), 600) != 600) {
            ulib.fputs(ulib.stderr, "write bigfile failed\n");
            ulib.exit();
        }
    }
    _ = ulib.close(fd);

    r = ulib.open("bigfile", fcntl.O_RDONLY);
    if (r < 0) {
        ulib.fputs(ulib.stderr, "cannot open bigfile\n");
        ulib.exit();
    }
    fd = @intCast(r);
    var total: u32 = 0;
    var i: usize = 0;
    while (true) : (i += 1) {
        const cc = ulib.read(fd, @ptrCast(&buf), 300);
        if (cc < 0) {
            ulib.fputs(ulib.stderr, "read bigfile failed\n");
            ulib.exit();
        }
        if (cc == 0) {
            break;
        }
        if (cc != 300) {
            ulib.fputs(ulib.stderr, "short read bigfile\n");
            ulib.exit();
        }
        if (buf[0] != @as(u8, @intCast(i / 2)) or buf[299] != @as(u8, @intCast(i / 2))) {
            ulib.fputs(ulib.stderr, "read bigfile wrong data\n");
            ulib.exit();
        }
        total += @intCast(cc);
    }
    _ = ulib.close(fd);
    if (total != 20 * 600) {
        ulib.fputs(ulib.stderr, "read bigfile wrong total\n");
        ulib.exit();
    }
    _ = ulib.unlink("bigfile");

    ulib.puts("bigfile test ok\n");
}

fn subdir() void {
    ulib.puts("subdir test\n");

    _ = ulib.unlink("ff");
    if (ulib.mkdir("dd") != 0) {
        ulib.fputs(ulib.stderr, "subdir mkdir dd failed\n");
        ulib.exit();
    }

    var r = ulib.open("dd/ff", fcntl.O_CREATE | fcntl.O_RDWR);
    if (r < 0) {
        ulib.fputs(ulib.stderr, "create dd/ff failed\n");
        ulib.exit();
    }
    var fd: u32 = @intCast(r);
    _ = ulib.write(fd, "ff", 2);
    _ = ulib.close(fd);

    if (ulib.unlink("dd") >= 0) {
        ulib.fputs(ulib.stderr, "unlink dd (non-empty dir) succeeded!\n");
        ulib.exit();
    }

    if (ulib.mkdir("/dd/dd") != 0) {
        ulib.fputs(ulib.stderr, "subdir mkdir dd/dd failed\n");
        ulib.exit();
    }

    r = ulib.open("dd/dd/ff", fcntl.O_CREATE | fcntl.O_RDWR);
    if (r < 0) {
        ulib.fputs(ulib.stderr, "create dd/dd/ff failed\n");
        ulib.exit();
    }
    fd = @intCast(r);
    _ = ulib.write(fd, "FF", 2);
    _ = ulib.close(fd);

    r = ulib.open("dd/dd/../ff", fcntl.O_RDONLY);
    if (r < 0) {
        ulib.fputs(ulib.stderr, "open dd/dd/../ff failed\n");
        ulib.exit();
    }
    fd = @intCast(r);
    const cc = ulib.read(fd, @ptrCast(&buf), @sizeOf(@TypeOf(buf)));
    if (cc != 2 or buf[0] != 'f') {
        ulib.fputs(ulib.stderr, "dd/dd/../ff wrong content\n");
        ulib.exit();
    }
    _ = ulib.close(fd);

    if (ulib.link("dd/dd/ff", "dd/dd/ffff") != 0) {
        ulib.fputs(ulib.stderr, "link dd/dd/ff dd/dd/ffff failed\n");
        ulib.exit();
    }

    if (ulib.unlink("dd/dd/ff") != 0) {
        ulib.fputs(ulib.stderr, "unlink dd/dd/ff failed\n");
        ulib.exit();
    }
    if (ulib.open("dd/dd/ff", fcntl.O_RDONLY) >= 0) {
        ulib.fputs(ulib.stderr, "open (unlinked) dd/dd/ff succeeded\n");
        ulib.exit();
    }

    if (ulib.chdir("dd") != 0) {
        ulib.fputs(ulib.stderr, "chdir dd failed\n");
        ulib.exit();
    }
    if (ulib.chdir("dd/../../dd") != 0) {
        ulib.fputs(ulib.stderr, "chdir dd/../../dd failed\n");
        ulib.exit();
    }
    if (ulib.chdir("dd/../../../dd") != 0) {
        ulib.fputs(ulib.stderr, "chdir dd/../../../dd failed\n");
        ulib.exit();
    }
    if (ulib.chdir("./..") != 0) {
        ulib.fputs(ulib.stderr, "chdir ./.. failed\n");
        ulib.exit();
    }

    r = ulib.open("dd/dd/ffff", fcntl.O_RDONLY);
    if (fd < 0) {
        ulib.fputs(ulib.stderr, "open dd/dd/ffff failed\n");
        ulib.exit();
    }
    fd = @intCast(r);
    if (ulib.read(fd, @ptrCast(&buf), @sizeOf(@TypeOf(buf))) != 2) {
        ulib.fputs(ulib.stderr, "read dd/dd/ffff wrong len\n");
        ulib.exit();
    }
    _ = ulib.close(fd);

    if (ulib.open("dd/dd/ff", fcntl.O_RDONLY) >= 0) {
        ulib.fputs(ulib.stderr, "open (unlinked) dd/dd/ff succeeded!\n");
        ulib.exit();
    }

    if (ulib.open("dd/ff/ff", fcntl.O_CREATE | fcntl.O_RDWR) >= 0) {
        ulib.fputs(ulib.stderr, "create dd/ff/ff succeeded!\n");
        ulib.exit();
    }
    if (ulib.open("dd/xx/ff", fcntl.O_CREATE | fcntl.O_RDWR) >= 0) {
        ulib.fputs(ulib.stderr, "create dd/xx/ff succeeded!\n");
        ulib.exit();
    }
    if (ulib.open("dd", fcntl.O_CREATE) >= 0) {
        ulib.fputs(ulib.stderr, "create dd succeeded!\n");
        ulib.exit();
    }
    if (ulib.open("dd", fcntl.O_RDWR) >= 0) {
        ulib.fputs(ulib.stderr, "open dd rdwr succeeded!\n");
        ulib.exit();
    }
    if (ulib.open("dd", fcntl.O_WRONLY) >= 0) {
        ulib.fputs(ulib.stderr, "open dd wronly succeeded!\n");
        ulib.exit();
    }
    if (ulib.link("dd/ff/ff", "dd/dd/xx") == 0) {
        ulib.fputs(ulib.stderr, "link dd/ff/ff dd/dd/xx succeeded!\n");
        ulib.exit();
    }
    if (ulib.link("dd/xx/ff", "dd/dd/xx") == 0) {
        ulib.fputs(ulib.stderr, "link dd/xx/ff dd/dd/xx succeeded!\n");
        ulib.exit();
    }
    if (ulib.link("dd/ff", "dd/dd/ffff") == 0) {
        ulib.fputs(ulib.stderr, "link dd/ff dd/dd/ffff succeeded!\n");
        ulib.exit();
    }
    if (ulib.mkdir("dd/ff/ff") == 0) {
        ulib.fputs(ulib.stderr, "mkdir dd/ff/ff succeeded!\n");
        ulib.exit();
    }
    if (ulib.mkdir("dd/xx/ff") == 0) {
        ulib.fputs(ulib.stderr, "mkdir dd/xx/ff succeeded!\n");
        ulib.exit();
    }
    if (ulib.mkdir("dd/dd/ffff") == 0) {
        ulib.fputs(ulib.stderr, "mkdir dd/dd/ffff succeeded!\n");
        ulib.exit();
    }
    if (ulib.unlink("dd/xx/ff") == 0) {
        ulib.fputs(ulib.stderr, "unlink dd/xx/ff succeeded!\n");
        ulib.exit();
    }
    if (ulib.unlink("dd/ff/ff") == 0) {
        ulib.fputs(ulib.stderr, "unlink dd/ff/ff succeeded!\n");
        ulib.exit();
    }
    if (ulib.chdir("dd/ff") == 0) {
        ulib.fputs(ulib.stderr, "chdir dd/ff succeeded!\n");
        ulib.exit();
    }
    if (ulib.chdir("dd/xx") == 0) {
        ulib.fputs(1, "chdir dd/xx succeeded!\n");
        ulib.exit();
    }

    if (ulib.unlink("dd/dd/ffff") != 0) {
        ulib.fputs(ulib.stderr, "unlink dd/dd/ff failed\n");
        ulib.exit();
    }
    if (ulib.unlink("dd/ff") != 0) {
        ulib.fputs(ulib.stderr, "unlink dd/ff failed\n");
        ulib.exit();
    }
    if (ulib.unlink("dd") == 0) {
        ulib.fputs(1, "unlink non-empty dd succeeded!\n");
        ulib.exit();
    }
    if (ulib.unlink("dd/dd") < 0) {
        ulib.fputs(ulib.stderr, "unlink dd/dd failed\n");
        ulib.exit();
    }
    if (ulib.unlink("dd") < 0) {
        ulib.fputs(ulib.stderr, "unlink dd failed\n");
        ulib.exit();
    }

    ulib.puts("subdir test ok\n");
}

fn linktest() void {
    ulib.puts("linktest\n");

    var r = ulib.open("lf1", fcntl.O_CREATE | fcntl.O_RDWR);
    var fd: u32 = @intCast(r);
    if (r < 0) {
        ulib.fputs(ulib.stderr, "create lf1 failed\n");
        ulib.exit();
    }
    if (ulib.write(fd, "hello", 5) != 5) {
        ulib.fputs(ulib.stderr, "write lf1 failed\n");
        ulib.exit();
    }
    _ = ulib.close(fd);

    if (ulib.link("lf1", "lf2") < 0) {
        ulib.fputs(ulib.stderr, "link lf1 lf2 failed\n");
        ulib.exit();
    }
    _ = ulib.unlink("lf1");

    if (ulib.open("lf1", 0) >= 0) {
        ulib.fputs(ulib.stderr, "unlinked lf1 but it is still there!\n");
        ulib.exit();
    }

    r = ulib.open("lf2", 0);
    fd = @intCast(r);
    if (r < 0) {
        ulib.fputs(1, "open lf2 failed\n");
        ulib.exit();
    }
    if (ulib.read(fd, @ptrCast(&buf), @sizeOf(@TypeOf(buf))) != 5) {
        ulib.fputs(ulib.stderr, "read lf2 failed\n");
        ulib.exit();
    }
    _ = ulib.close(fd);

    if (ulib.link("lf2", "lf2") >= 0) {
        ulib.fputs(ulib.stderr, "link lf2 lf2 succeeded! oops\n");
        ulib.exit();
    }

    _ = ulib.unlink("lf2");
    if (ulib.link("lf2", "lf1") >= 0) {
        ulib.fputs(ulib.stderr, "link non-existant succeeded! oops\n");
        ulib.exit();
    }

    if (ulib.link(".", "lf1") >= 0) {
        ulib.fputs(ulib.stderr, "link . lf1 succeeded! oops\n");
        ulib.exit();
    }

    ulib.puts("linktest ok\n");
}

fn unlinkread() void {
    ulib.puts("unlinkread test\n");

    var r = ulib.open("unlinkread", fcntl.O_CREATE | fcntl.O_RDWR);
    if (r < 0) {
        ulib.fputs(ulib.stderr, "create unlinkread failed\n");
        ulib.exit();
    }
    const fd: u32 = @intCast(r);
    _ = ulib.write(fd, "hello", 5);
    _ = ulib.close(fd);

    r = ulib.open("unlinkread", fcntl.O_RDWR);
    if (r < 0) {
        ulib.fputs(ulib.stderr, "open unlinkread failed\n");
        ulib.exit();
    }
    if (ulib.unlink("unlinkread") != 0) {
        ulib.fputs(ulib.stderr, "unlink unlinkread failed\n");
        ulib.exit();
    }

    r = ulib.open("unlinkread", fcntl.O_CREATE | fcntl.O_RDWR);
    const fd1: u32 = @intCast(r);
    _ = ulib.write(fd1, "yyy", 3);
    _ = ulib.close(fd1);

    if (ulib.read(fd, @ptrCast(&buf), @sizeOf(@TypeOf(buf))) != 5) {
        ulib.fputs(ulib.stderr, "unlinkread read failed");
        ulib.exit();
    }
    if (buf[0] != 'h') {
        ulib.fputs(ulib.stderr, "unlinkread wrong data\n");
        ulib.exit();
    }
    if (ulib.write(fd, @ptrCast(&buf), 10) != 10) {
        ulib.fputs(ulib.stderr, "unlinkread write failed\n");
        ulib.exit();
    }
    _ = ulib.close(fd);
    _ = ulib.unlink("unlinkread");

    ulib.puts("unlinkread test ok\n");
}

fn dirfile() void {
    ulib.puts("dir vs file\n");

    var r = ulib.open("dirfile", fcntl.O_CREATE);
    if (r < 0) {
        ulib.fputs(ulib.stderr, "create dirfile failed\n");
        ulib.exit();
    }
    _ = ulib.close(@intCast(r));
    if (ulib.chdir("dirfile") == 0) {
        ulib.fputs(ulib.stderr, "chdir dirfile succeeded!\n");
        ulib.exit();
    }
    r = ulib.open("dirfile/xx", fcntl.O_RDONLY);
    if (r >= 0) {
        ulib.fputs(ulib.stderr, "create dirfile/xx succeeded!\n");
        ulib.exit();
    }
    r = ulib.open("dirfile/xx", fcntl.O_CREATE);
    if (r >= 0) {
        ulib.fputs(ulib.stderr, "create dirfile/xx succeeded!\n");
        ulib.exit();
    }
    if (ulib.mkdir("dirfile/xx") == 0) {
        ulib.fputs(ulib.stderr, "mkdir dirfile/xx succeeded!\n");
        ulib.exit();
    }
    if (ulib.unlink("dirfile/xx") == 0) {
        ulib.fputs(ulib.stderr, "unlink dirfile/xx succeeded!\n");
        ulib.exit();
    }
    if (ulib.link("README", "dirfile/xx") == 0) {
        ulib.fputs(ulib.stderr, "link to dirfile/xx succeeded!\n");
        ulib.exit();
    }
    if (ulib.unlink("dirfile") != 0) {
        ulib.fputs(ulib.stderr, "unlink dirfile failed!\n");
        ulib.exit();
    }

    r = ulib.open(".", fcntl.O_RDWR);
    if (r >= 0) {
        ulib.fputs(ulib.stderr, "open . for writing succeeded!\n");
        ulib.exit();
    }
    r = ulib.open(".", fcntl.O_RDONLY);
    if (ulib.write(@intCast(r), "x", 1) > 0) {
        ulib.fputs(ulib.stderr, "write . succeeded!\n");
        ulib.exit();
    }
    _ = ulib.close(@intCast(r));

    ulib.puts("dir vs file ok\n");
}

fn iref() void {
    ulib.puts("iref test\n");

    for (0..51) |_| {
        if (ulib.mkdir("irefd") != 0) {
            ulib.fputs(ulib.stderr, "mkdir irefd failed\n");
            ulib.exit();
        }
        if (ulib.chdir("irefd") != 0) {
            ulib.fputs(ulib.stderr, "chdir irefd failed\n");
            ulib.exit();
        }

        _ = ulib.mkdir("");
        _ = ulib.link("README", "");
        var r = ulib.open("", fcntl.O_CREATE);
        if (r >= 0) {
            _ = ulib.close(@intCast(r));
        }
        r = ulib.open("xx", fcntl.O_CREATE);
        if (r >= 0) {
            _ = ulib.close(@intCast(r));
        }
        _ = ulib.unlink("xx");
    }
    _ = ulib.chdir("/");

    ulib.puts("iref test ok\n");
}

fn forktest() void {
    const N = 1000;

    var n: usize = 0;
    while (n < N) : (n += 1) {
        const pid = ulib.fork();
        if (pid < 0) {
            break;
        }
        if (pid == 0) {
            ulib.exit();
        }
    }

    if (n == N) {
        ulib.print("fork claimed to work {} times\n", .{N});
        ulib.exit();
    }

    for (0..n) |_| {
        if (ulib.wait() < 0) {
            ulib.puts("wait stopped early\n");
            ulib.exit();
        }
    }

    if (ulib.wait() != -1) {
        ulib.puts("wait got too many\n");
        ulib.exit();
    }

    ulib.puts("fork test ok!\n");
}

fn bigdir() void {
    ulib.puts("bigdir test\n");

    _ = ulib.unlink("bd");
    const r = ulib.open("bd", fcntl.O_CREATE);
    if (r < 0) {
        ulib.fputs(ulib.stderr, "bigdir create failed\n");
        ulib.exit();
    }
    _ = ulib.close(@intCast(r));

    var name: [10]u8 = undefined;
    @memset(&name, 0);
    for (0..500) |i| {
        name[0] = 'x';
        name[1] = '0' + @as(u8, @intCast(i / 64));
        name[2] = '0' + @as(u8, @intCast(i % 64));
        if (ulib.link("bd", @ptrCast(&name)) != 0) {
            ulib.fputs(ulib.stderr, "bigdir link failed\n");
            ulib.exit();
        }
    }

    _ = ulib.unlink("bd");
    for (0..500) |i| {
        name[0] = 'x';
        name[1] = '0' + @as(u8, @intCast(i / 64));
        name[2] = '0' + @as(u8, @intCast(i % 64));
        if (ulib.unlink(@ptrCast(&name)) != 0) {
            ulib.fputs(ulib.stderr, "bigdir unlink failed\n");
            ulib.exit();
        }
    }

    ulib.puts("bigdir test ok\n");
}

// Attempt to read Real Time Clock from user code
// See https://wiki.osdev.org/CMOS
fn uio() void {
    const RTC_ADDR: u8 = 0x70;
    const RTC_DATA: u8 = 0x71;

    ulib.puts("uio test\n");

    const pid = ulib.fork();
    if (pid == 0) {
        const val: u8 = 0x09; // Year register
        asm volatile ("outb %[val], %[port]" :: [val] "{al}" (val), [port] "N{dx}" (RTC_ADDR));
        _ = asm volatile ("inb %[port], %[val]" : [val] "={al}" (-> u8) : [port] "N{dx}" (RTC_DATA));
        ulib.fputs(ulib.stderr, "not supposed to read mem-mapped devices from userland\n");
        ulib.exit();
    } else if (pid < 0) {
        ulib.fputs(ulib.stderr, "fork failed\n");
        ulib.exit();
    }
    _ = ulib.wait();

    ulib.puts("uio test ok\n");
}


fn exectest() void {
    ulib.puts("exec test\n");
    if (ulib.exec("echo", &[_]?[*:0]const u8{ "echo", "ALL", "TESTS", "PASSED", null }) < 0) {
        ulib.fputs(ulib.stderr, "exec test failed\n");
        ulib.exit();
    }
}

pub export fn main() void {
    ulib.puts("usertests starting\n");

    if (ulib.open("usertests.ran", fcntl.O_RDONLY) >= 0) {
        ulib.puts("already run user tests, rebuild fs.img\n");
        ulib.exit();
    }
    _ = ulib.close(@intCast(ulib.open("usertests.ran", fcntl.O_CREATE)));

    argptest();
    createdelete();
    linkunlink();
    concreate();
    fourfiles();
    sharedfd();

    bigargtest();
    bigwrite();
    sbrktest();
    validatetest();

    opentest();
    writetest();
    writetest1();
    createtest();

    openiputtest();
    exitiputtest();
    iputtest();

    mem();
    pipe1();
    preempt();
    exitwait();

    rmdot();
    fourteen();
    bigfile();
    subdir();
    linktest();
    unlinkread();
    dirfile();
    iref();
    forktest();
    bigdir();

    uio();

    exectest();

    ulib.exit();
}
