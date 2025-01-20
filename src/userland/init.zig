const ulib = @import("ulib.zig");

var shargv = [_]?[*:0]const u8{ "/sh", null };

export fn main() callconv(.C) void {
    ulib.init() catch unreachable;

    while (true) {
        ulib.puts("init: starting sh\n") catch unreachable;

        const pid = ulib.fork() catch {
            ulib.fputs(ulib.stderr, "init: fork failed\n") catch unreachable;
            ulib.exit();
        };
        if (pid == 0) {
            ulib.exec("./sh", &shargv) catch unreachable;
            ulib.fputs(ulib.stderr, "init: exec sh failed\n") catch unreachable;
            ulib.exit();
        }
        var wpid = ulib.wait() catch unreachable;
        while (wpid != pid) {
            wpid = ulib.wait() catch unreachable; // A process other than sh finished, continue waiting
        }
    }
}
