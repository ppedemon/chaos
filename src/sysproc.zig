const console = @import("console.zig");
const proc = @import("proc.zig");
const syscall = @import("syscall.zig");

const err = @import("share").err;

pub fn sys_fork() err.SysErr!u32 {
    if (proc.fork()) |pid| {
        return pid;
    }
    return err.SysErr.ErrNoMem;
}

pub fn sys_wait() err.SysErr!u32 {
    if (proc.wait()) |pid| {
        return pid;
    }
    return err.SysErr.ErrChild;
}

pub fn sys_exit() err.SysErr!u32 {
    proc.exit();
    unreachable;
}

pub fn sys_sbrk() err.SysErr!u32 {
    var n: i32 = undefined;
    try syscall.argsgn(0, &n);

    if (proc.myproc()) |p| {
        const addr = p.sz;
        if (!proc.growproc(n)) {
            return err.SysErr.ErrNoMem;
        }
        return addr;
    }

    @panic("brk: no process");
}
