const ulib = @import("ulib.zig");

pub export fn main(argc: u32, argv: [*][*:0]const u8) void {
  if (argc < 2) {
    ulib.fputs(ulib.stderr, "usage: rm files...\n");
    ulib.exit();
  }

  for (1..argc) |i| {
    if (ulib.unlink(argv[i]) < 0) {
      ulib.fprint(ulib.stderr, "rm: {s} failed to delete\n", .{argv[i]});
      break;
    }
  }
  
  ulib.exit();
}
