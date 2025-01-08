const ulib = @import("ulib.zig");
const print = @import("print.zig");

export fn main() callconv(.C) void {
    if (ulib.open("console", ulib.O_RDWR) < 0) {
        _ = ulib.mknod("console", 1, 1); // device major = 1 is CONSOLE (see src/file.zig)
        if (ulib.open("console", ulib.O_RDWR) < 0) {
            return;
        }
    }

    _ = ulib.dup(0); // stdout
    _ = ulib.dup(0); // stderr

    const argv: [*]?[*:0]const u8 = @constCast(@ptrCast(&[_]?[*:0]const u8{
        "first",
        "second",
        "third",
        null,
    }));
    _ = ulib.exec("./sh", argv);
}
