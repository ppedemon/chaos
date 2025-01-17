const ulib = @import("ulib.zig");

var shargv = [_]?[*:0]const u8{ "/sh", null };

export fn main() callconv(.C) void {
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
            wpid = ulib.wait(); // A process other than sh finished, continue waiting
        }
    }
}
