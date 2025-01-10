const ulib = @import("ulib.zig");

var shargv = [_]?[*:0]const u8{ "/sh", null };

export fn main(argc: u32, argv: [*][*:0]const u8) callconv(.C) void {
    for (0..argc) |i| {
        ulib.print("args[{}] = {s}\n", .{ i, argv[i] });
    }

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

    ulib.puts("init: starting sh\n");

    while (true) {
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
