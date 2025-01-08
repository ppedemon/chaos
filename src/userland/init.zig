const ulib = @import("ulib.zig");
const print = @import("print.zig");

const argv: [*]?[*:0]const u8 = @constCast(@ptrCast(&[_]?[*:0]const u8{ "sh", null }));

export fn main() callconv(.C) void {
    if (ulib.open("console", ulib.O_RDWR) < 0) {
        // Create an inode for device major 1 (that is, console)
        if (ulib.mknod("console", 1, 1) < 0) {
            return;
        }
        if (ulib.open("console", ulib.O_RDWR) < 0) {
            return;
        }
    }

    const stdout: u32 = @intCast(ulib.dup(0));
    _ = ulib.dup(0); // stderr, not used for now

    var printer = print.Printer.init(stdout);

    while (true) {
        printer.put("init: starting sh\n").flush();
        const pid = ulib.fork();
        if (pid < 0) {
            printer.put("init: fork failed\n").flush();
            ulib.exit();
        }
        if (pid == 0) {
            if (ulib.exec("./sh", argv) < 0) {
                printer.putall("init: exec sh failed\n").flush();
            }
            ulib.exit();
        }
        var wpid = ulib.wait();
        while (wpid >= 0 and wpid != pid) {
            printer.putall("zombie!\n").flush(); // A process other than sh finished
            wpid = ulib.wait();
        }
    }

    // const argv: [*]?[*:0]const u8 = @constCast(@ptrCast(&[_]?[*:0]const u8{
    //     "first",
    //     "second",
    //     "third",
    //     null,
    // }));
}
