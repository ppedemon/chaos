fn scan(buf: []const u8, n: u8) ?u32 {
    for (buf, 0..) |x, i| {
        if (x == n) {
            return i;
        }
    }
    return null;
}

export fn main() callconv(.C) u32 {
    const buf: [512]u8 = [1]u8{0} ** 512;
    return scan(&buf, 1) orelse 0;
}
