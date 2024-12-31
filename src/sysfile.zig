const console = @import("console.zig");
const param = @import("param.zig");
const exec = @import("exec.zig");
const syscall = @import("syscall.zig");
const std = @import("std");

pub fn sys_exec() i32 {
    var path: []const u8 = undefined;
    var argv: [param.MAXARG][]const u8 = undefined;

    var uargv: i32 = undefined;
    var uarg: i32 = undefined;

    if (syscall.argstr(0, &path) < 0 or syscall.argint(1, &uargv) < 0) {
        return -1;
    }

    @memset(std.mem.asBytes(&argv), 0);

    var i: usize = 0;
    while (true) : (i += 1) {
        if (i >= argv.len) {
            return -1;
        }
        if (syscall.fetchint(@as(usize, @intCast(uargv)) + 4 * i, &uarg) < 0) {
            return -1;
        }
        if (uarg == 0) {
            break;
        }
        if (syscall.fetchstr(@as(usize, @intCast(uarg)), &argv[i]) < 0) {
            return -1;
        }
    }

    const exec_argv: []const []const u8 = argv[0..i];

    console.cprintf("path = {s}\n", .{path});
    for (exec_argv, 0..) |arg, j| {
        console.cprintf("argv[{}] = {s}\n", .{ j, arg });
    }

    return exec.exec(path, exec_argv);
}
