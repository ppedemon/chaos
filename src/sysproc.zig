const err = @import("err.zig");
const proc = @import("proc.zig");

pub fn sys_exit() err.SysErr!u32 {
  proc.exit();
  unreachable;
}
