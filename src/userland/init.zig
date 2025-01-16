const ulib = @import("ulib.zig");

var shargv = [_]?[*:0]const u8{ "/sh", null };



export fn main() callconv(.C) void {
    // const pid = ulib.fork();
    // if (pid < 0) {
    //     ulib.puts("init: fork failed\n");
    //     ulib.exit();
    // }
    // if (pid == 0) {
    //     var i: u32 = 0;
    //     while (true) {
    //         if (i % 10_000_000 == 0) {
    //             ulib.puts("Child\n");
    //         }
    //         i +%= 1;
    //     }
    // } else {
    //     var i: u32 = 0;
    //     while (true) {
    //         if (i % 10_000_000 == 0) {
    //             ulib.puts("Parent\n");
    //         }
    //         i +%= 1;
    //     }
    // }

    // const p = ulib.sbrk(8192);
    // if (p == -1) {
    //     ulib.puts("Uh oh\n!");
    // } else {
    //     const ptr: [*]u8 = @ptrFromInt(@as(usize, @intCast(p)));
    //     ulib.print("ptr = {x}\n", .{@intFromPtr(ptr)});
    // }

    ulib.init();

    while (true) {
        ulib.puts("init: starting sh\n");

        const pid = ulib.fork();
        if (pid < 0) {
            ulib.fputs(ulib.stderr, "init: fork failed\n");
            ulib.exit();
        }
        if (pid == 0) {
            if (ulib.exec("./sh", &shargv) < 0) {
                ulib.fputs(ulib.stderr, "init: exec sh failed\n");
            }
            ulib.exit();
        }
        var wpid = ulib.wait();
        while (wpid >= 0 and wpid != pid) {
            ulib.fputs(ulib.stderr, "zombie!\n"); // A process other than sh finished
            wpid = ulib.wait();
        }
    }
}
