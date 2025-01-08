const err = @import("err.zig");
const proc = @import("proc.zig");

pub fn sys_fork() err.SysErr!u32  {
  if (proc.fork()) |pid| {
    return pid;
  }
  return err.SysErr.ErrNoMem;
}

pub fn sys_wait() err.SysErr!u32 {
  if (proc.wait()) |pid| {
    return pid;
  }
  return err.SysErr.ErrChild;
}

pub fn sys_exit() err.SysErr!u32 {
  proc.exit();
  unreachable;
}
