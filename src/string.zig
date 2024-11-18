const x86 = @import("x86.zig");

pub fn memset(dst: usize, data: u8, n: usize) void {
    if (dst % 4 == 0 and n % 4 == 0) {
        var c: u32 = @intCast(data);
        c &= 0xFF;
        x86.stos(u32, dst, (c << 24) | (c << 16) | (c << 8) | c, n >> 2);
    } else {
        x86.stos(u8, dst, data, n);
    }
}

pub fn memmove(dst: usize, src: usize, n: usize) void {
    const d: [*]u8 = @ptrFromInt(dst);
    const s: [*]const u8 = @ptrFromInt(src);

    if (src < dst and src + n > dst) {
        var i: usize = n;
        while (i > 0) : (i -= 1) {
            d[i - 1] = s[i - 1];
        }
    } else {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            d[i] = s[i];
        }
    }
}

pub fn sprintn(x: anytype, buf: []u8) usize {
    var n: usize = 0;
    var c = x;
    while (true) {
        buf[n] = '0' + @as(u8, @intCast(c % 10));
        c /= 10;
        n += 1;
        if (c == 0) {
            break;
        }
    }
    for (0..n / 2) |j| {
        const tmp = buf[j];
        buf[j] = buf[n - j - 1];
        buf[n - j - 1] = tmp;
    }
    return n;
}
