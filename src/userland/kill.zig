const ulib = @import("ulib.zig");
const std = @import("std");

pub export fn main(argc: u32, argv: [*][*:0]const u8) void {
  if (argc < 2) {
    ulib.fputs(ulib.stderr, "usage: kill pid...\n");
    ulib.exit();
  }
  
  for (1..argc) |i| {
    const pid = std.fmt.parseInt(u32, std.mem.sliceTo(argv[i], 0), 10) catch {
      ulib.fprint(ulib.stderr, "invalid pid: {s}\n", .{argv[i]});
      ulib.exit();
    };
    _ = ulib.kill(pid);
  }
  ulib.exit();
}
