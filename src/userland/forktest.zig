const ulib = @import("ulib.zig");

const N = 61; // NPROC - init - sh - forktest

fn forktest() void {
    var n: usize = 0;
    while (n < N) : (n += 1) {
      const pid = ulib.fork();
      if (pid < 0) {
        break;
      }
      if (pid == 0) {
        ulib.exit();
      }
    }

    if (n == N) {
      ulib.print("fork claimed to work {} times\n", .{N});
    }

    for (0..n) |_| {
      if (ulib.wait() < 0) {
        ulib.puts("wait stopped early\n");
        ulib.exit();
      }
    }

    if (ulib.wait() != -1) {
      ulib.puts("wait got too many\n");
      ulib.exit();
    }

    ulib.puts("fork test ok!\n");
}

pub export fn main() void {
    forktest();
    ulib.exit();
}
