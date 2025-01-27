const ulib = @import("ulib.zig");
const share = @import("share");
const fcntl = share.fcntl;

var buf: [512]u8 = undefined;
var path: [9:0]u8 = undefined;

pub export fn main() void {
    ulib.puts("stressfs starting\n");
    @memset(&buf, 'a');
    @memset(&path, 0);
    @memcpy(&path, "stressfs0");

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        if (ulib.fork() > 0) {
            break;
        }
    }

    ulib.print("write {}\n", .{i});

    path[8] += @intCast(i);
    var fd = ulib.open(@ptrCast(&path[0]), fcntl.O_CREATE | fcntl.O_RDWR);
    for (0..20) |_| {
        _ = ulib.write(@intCast(fd), @ptrCast(&buf[0]), @sizeOf(@TypeOf(buf)));
    }
    _ = ulib.close(@intCast(fd));

    fd = ulib.open(@ptrCast(&path[0]), fcntl.O_RDONLY);
    for (0..20) |_| {
        _ = ulib.read(@intCast(fd), @as([*]u8, @ptrCast(&buf[0])), @sizeOf(@TypeOf(buf)));
    }
    _ = ulib.close(@intCast(fd));

    if (i == 4) {
        for (0..4) |_| {
            _ = ulib.wait();
        }
    }

    ulib.exit();
}
