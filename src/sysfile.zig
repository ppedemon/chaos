const console = @import("console.zig");
const err = @import("err.zig");
const param = @import("param.zig");
const exec = @import("exec.zig");
const syscall = @import("syscall.zig");
const std = @import("std");

pub fn sys_exec() err.SysErr!u32 {
    var path: []const u8 = undefined;
    var argv: [param.MAXARG][]const u8 = undefined;

    var uargv: u32 = undefined;
    var uarg: u32 = undefined;

    syscall.argstr(0, &path) catch |syserr| {
        return syserr;
    };
    syscall.argint(1, &uargv) catch |syserr| {
        return syserr;
    };

    @memset(std.mem.asBytes(&argv), 0);

    var i: usize = 0;
    while (true) : (i += 1) {
        if (i >= argv.len) {
            return err.SysErr.ErrArgs;
        }
        syscall.fetchint(@as(usize, @intCast(uargv)) + 4 * i, &uarg) catch |syserr| {
            return syserr;
        };
        if (uarg == 0) {
            break;
        }
        syscall.fetchstr(@as(usize, @intCast(uarg)), &argv[i]) catch |syserr| {
            return syserr;
        };
    }

    const exec_argv: []const []const u8 = argv[0..i];

    console.cprintf("path = {s}\n", .{path});
    for (exec_argv, 0..) |arg, j| {
        console.cprintf("argv[{}] = {s}\n", .{ j, arg });
    }

    return exec.exec(path, exec_argv);
}
