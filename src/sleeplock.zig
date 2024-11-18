const proc = @import("proc.zig");
const spinlock = @import("spinlock.zig");

pub const SleepLock = struct {
  locked: bool,
  lk: spinlock.SpinLock,
  name: []const u8,
  pid: u32,

  const Self = @This();

  pub fn init(name: []const u8) Self {
    return .{
      .locked = false,
      .lk = spinlock.SpinLock.init("sleep lock"),
      .name = name,
      .pid = 0,
    };
  }

  pub fn acquire(self: *Self) void {
    self.lk.acquire();
    defer self.lk.release();
    while (self.locked) {
      proc.sleep(@intFromPtr(self), &self.lk);
    }
    self.locked = true;
    
    // TODO Enable back after testing
    //self.pid = proc.myproc().pid;
  }

  pub fn release(self: *Self) void {
    self.lk.acquire();
    defer self.lk.release();
    self.pid = 0;
    proc.wakeup(@intFromPtr(self));
  }

  pub fn holding(self: *Self) bool {
    self.lk.acquire();
    defer self.lk.release();

    // TODO Enable back after testing
    // return self.locked and (self.pid == proc.myproc().pid);
    return true;
  }
};
