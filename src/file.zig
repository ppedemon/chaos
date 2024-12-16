const console = @import("console.zig");
const fs = @import("fs.zig");
const param = @import("param.zig");
const sleeplock = @import("sleeplock.zig");
const spinlock = @import("spinlock.zig");

pub const File = struct {
    ty: enum { FD_NONE, FD_PIPE, FI_INODE },
    ref: u32,
    readable: bool,
    writable: bool,
};

pub const DevSwitchTbl = struct {
    read: *const fn (ip: *fs.Inode, dst: []u8, n: u32) ?u32,
    write: *const fn (ip: *fs.Inode, buf: []const u8, n: u32) ?u32,
};

pub var devsw: [param.NDEV]DevSwitchTbl = init: {
    var init_value: [param.NDEV]DevSwitchTbl = undefined;
    for (0..init_value.len) |i| {
        if (i == CONSOLE) {
            init_value[i] = .{
                .read = console.consoleread,
                .write = console.consolewrite,
            };
        } else {
            init_value[i] = undefined;
        }
    }
    break :init init_value;
};

var ftable = struct {
    lock: spinlock.SpinLock,
    file: [param.NFILE]File,
}{
    .lock = spinlock.SpinLock.init("ftable"),
    .file = undefined,
};

pub const CONSOLE = 1;
