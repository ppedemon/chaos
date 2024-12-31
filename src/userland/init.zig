const user = @import("user.zig");

export fn main() callconv(.C) u32 {
    const argv: [*]?[*:0]const u8 = @constCast(@ptrCast(&[_]?[*:0]const u8{
        "first",
        "second",
        "third",
        null,
    }));
    _ = user.exec("./sh", argv);
    return 0;
}
