const ulib = @import("ulib.zig");

pub export fn main() void {
  if (ulib.fork() > 0) {
    _ = ulib.sleep(5); // Child will exit before parent
  }
  ulib.exit();
}
