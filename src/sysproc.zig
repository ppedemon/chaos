const console = @import("console.zig");
const err = @import("err.zig");
const proc = @import("proc.zig");
const syscall = @import("syscall.zig");
const trap = @import("trap.zig");

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

pub fn sys_kill() err.SysErr!u32 {
    var pid: u32 = undefined;
    try syscall.argint(0, &pid);
    if (proc.kill(pid)) {
        return 0;
    }
    return err.SysErr.ErrSrch;
}

pub fn sys_getpid() err.SysErr!u32 {
    return proc.myproc().?.pid;
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

pub fn sys_sleep() err.SysErr!u32 {
    var n: u32 = undefined;
    try syscall.argint(0, &n);

    trap.tickslock.acquire();
    defer trap.tickslock.release();

    const start: u32 = trap.ticks;
    while (trap.ticks - start < n) {
        if (proc.myproc().?.killed) {
            return err.SysErr.ErrIntr;
        }
        proc.sleep(@intFromPtr(&trap.ticks), &trap.tickslock);
    }

    return 0;
}

pub fn sys_uptime() err.SysErr!u32 {
    trap.tickslock.acquire();
    defer trap.tickslock.release();
    return trap.ticks;
}
