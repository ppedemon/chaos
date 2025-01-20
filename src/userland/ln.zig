const ulib = @import("ulib.zig");

pub export fn main(argc: u32, argv: [*][*:0]const u8) void {
  if (argc != 3) {
    ulib.fputs(ulib.stderr, "usage: ln old new\n");
    ulib.exit();
  }
  if (ulib.link(argv[1], argv[2]) < 0) {
    ulib.fprint(ulib.stderr, "link {s} {s}: failed \n", .{argv[1], argv[2]});
  }
  ulib.exit();
}
