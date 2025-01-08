const ulib = @import("ulib.zig");
const std = @import("std");

pub const Printer = struct {
    fd: u32,
    buf: [256]u8,
    index: usize,

    const Self = @This();

    pub fn init(fd: u32) Self {
        return .{
            .fd = fd,
            .buf = undefined,
            .index = 0,
        };
    }

    pub fn putc(self: *Self, c: u8) *Self {
        self.buf[self.index] = c;
        self.index = self.index + 1;
        if (self.index == @sizeOf(@TypeOf(self.buf))) {
            self.flush();
            self.index = 0;
        }
        return self;
    }

    pub fn putall(self: *Self, s: []const u8) *Self {
        for (s) |c| {
            self.putc(c).end();
        }
        return self;
    }

    pub inline fn putint(self: *Self, n: anytype) *Self {
        return self.int(n, true, 10);
    }

    pub inline fn puthex(self: *Self, n: anytype) *Self {
        return self.int(n, false, 16);
    }

    pub inline fn putptr(self: *Self, n: anytype) *Self {
        return self.puthex(@as(u32, @intFromPtr(n)));
    }

    pub fn put(self: *Self, x: anytype) *Self {
        const info = @typeInfo(@TypeOf(x));
        switch (info) {
            .Int, .ComptimeInt => return self.putint(x),
            .Array => |a| if (a.child == u8) {
                return self.putall(&x);
            } else {
                self.putall("{ ").end();
                for (x, 0..) |v, i| {
                    self.put(v).end();
                    if (i < x.len - 1) {
                        self.putall(", ").end();
                    }
                }
                return self.putall(" }");
            },
            .Pointer => |p| switch (p.size) {
                .One => switch (@typeInfo(p.child)) {
                    .Array => return self.put(x.*),
                    else => return self.putptr(x),
                },
                .Many, .C => if (p.sentinel) |_| {
                    return self.put(std.mem.span(x));
                } else {
                    return self.putptr(x);
                },
                .Slice => if (p.child == u8) {
                    return self.putall(x);
                } else {
                    self.putall("{ ").end();
                    for (x, 0..) |v, i| {
                        self.put(v).end();
                        if (i < x.len - 1) {
                            self.putall(", ").end();
                        }
                    }
                    return self.putall(" }");
                },
            },
            .Optional => if (x) |v| {
                return self.put(v);
            } else {
                return self.putall("null");
            },
            .Null => return self.putall("null"),
            else => @compileError("non-printable type"),
        }
    }

    pub fn flush(self: *Self) void {
        _ = ulib.write(1, &self.buf, self.index);
    }

    inline fn end(_: *Self) void {}

    fn int(self: *Self, n: anytype, sign: bool, base: u8) *Self {
        const static = struct {
            const digits = "0123456789ABCDEF";
            var buf: [16]u8 = [_]u8{0} ** 16;
        };
        switch (@typeInfo(@TypeOf(n))) {
            .Int, .ComptimeInt => {
                const neg = sign and n < 0;
                var x: u32 = @abs(n);
                var i: usize = 0;
                while (true) {
                    static.buf[i] = static.digits[x % base];
                    i += 1;
                    x /= base;
                    if (x == 0) {
                        break;
                    }
                }
                if (neg) {
                    static.buf[i] = '-';
                    i += 1;
                }
                while (i > 0) {
                    i -= 1;
                    self.putc(static.buf[i]).end();
                }
            },
            else => @compileError("invalid integer type"),
        }
        return self;
    }
};
