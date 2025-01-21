const ulib = @import("ulib.zig");
const fcntl = @import("share").fcntl;
const std = @import("std");

var buf: [256]u8 = undefined;

fn wc(fd: u32, name: [*:0]const u8) void {
    var l: u32 = 0;
    var w: u32 = 0;
    var c: u32 = 0;
    var inword = false;

    while (true) {
        const n = ulib.read(fd, @as([*]u8, @ptrCast(&buf[0])), @sizeOf(@TypeOf(buf)));
        if (n < 0) {
            ulib.fputs(ulib.stderr, "wc: read error\n");
            ulib.exit();
        }
        if (n == 0) {
          break;
        }
        for (buf[0..@intCast(n)]) |ch| {
          c += 1;
          if (ch == '\n') {
            l += 1;
          }
          if (std.mem.indexOfScalar(u8, " \r\n\t", ch)) |_| {
            inword = false;
          } else if (!inword) {
            inword = true;
            w += 1;
          }
        }
    }
    ulib.print("{} {} {} {s}\n", .{l, w, c, name});
}

pub export fn main(argc: u32, argv: [*][*:0]const u8) void {
  if (argc <= 1) {
    wc(ulib.stdin, "");
    ulib.exit();
  }

  for (1..argc) |i| {
    const fd = ulib.open(argv[i], fcntl.O_RDONLY);
    if (fd < 0) {
      ulib.fprint(ulib.stderr, "wc: cannot open {s}\n", .{argv[i]});
      ulib.exit();
    }
    wc(@intCast(fd), argv[i]);
    _ = ulib.close(@intCast(fd));
  }
  ulib.exit();
}
