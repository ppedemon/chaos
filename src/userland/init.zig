const ulib = @import("ulib.zig");

export fn main() callconv(.C) u32 {
    _ = ulib.open("console", ulib.O_RDWR);
    const argv: [*]?[*:0]const u8 = @constCast(@ptrCast(&[_]?[*:0]const u8{
        "first",
        "second",
        "third",
        null,
    }));
    _ = ulib.exec("./sh", argv);
    return 0;
}
