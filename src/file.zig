const fs = @import("fs.zig");
const param = @import("param.zig");
const spinlock = @import("spinlock.zig");

pub const File = struct {
    ty: enum { FD_NONE, FD_PIPE, FI_INODE },
    ref: u32,
    readable: bool,
    writable: bool,
};

var ftable = struct {
    lock: spinlock.SpinLock,
    file: [param.NFILE]File,
}{
    .lock = spinlock.SpinLock.init("ftable"),
    .file = undefined,
};

pub const DevSwitchTbl = struct {
    read: *const fn (ip: *fs.Inode, dst: []u8, n: u32) ?u32,
    write: *const fn (ip: *fs.Inode, buf: []const u8, n: u32) ?u32,
};

pub var devsw: [param.NDEV]DevSwitchTbl = undefined;

pub const CONSOLE = 1;
