const console = @import("console.zig");
const param = @import("param.zig");
const sleeplock = @import("sleeplock.zig");
const spinlock = @import("spinlock.zig");

pub const File = struct {
    ty: enum { FD_NONE, FD_PIPE, FI_INODE },
    ref: u32,
    readable: bool,
    writable: bool,
};

pub const Inode = struct {
    dev: u32, // Device number
    inum: u32, // Inode number
    ref: u32, // Reference count
    lk: sleeplock.SleepLock, // Protects data below

    valid: u32, // Has node been read from disk?
    ty: u16, // Type of disk inode
    major: u16,
    minor: u16,
    nlink: u16,
    size: u32,
    addrs: [13]u32,

    const Self = @This();

    pub fn lock(self: *Self) void {
      // TODO Implement
      _ = self;
    }

    pub fn unlock(self: *Self) void {
      // TODO Implement
      _ = self;
    }
};

pub const DevSwitchTbl = struct {
  read: *const fn(ip: *Inode, dst: [*]u8, n: u32) ?u32,
  write: *const fn(ip: *Inode, buf: []const u8, n: u32) u32,
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
} {
  .lock = spinlock.SpinLock.init("ftable"),
  .file = undefined,
};

pub const CONSOLE = 1;
