const console = @import("console.zig");
const err = @import("err.zig");
const proc = @import("proc.zig");
const sysfile = @import("sysfile.zig");
const sysproc = @import("sysproc.zig");

// TODO not going to be used? See if we can remove these constants in the future
const SYS_fork = 1;
const SYS_exit = 2;
const SYS_wait = 3;
const SYS_pipe = 4;
const SYS_read = 5;
const SYS_kill = 6;
const SYS_exec = 7;
const SYS_fstat = 8;
const SYS_chdir = 9;
const SYS_dup = 10;
const SYS_getpid = 11;
const SYS_sbrk = 12;
const SYS_sleep = 13;
const SYS_uptime = 14;
const SYS_open = 15;
const SYS_write = 16;
const SYS_mknod = 17;
const SYS_unlink = 18;
const SYS_link = 19;
const SYS_mkdir = 20;
const SYS_close = 21;

fn unimplemented() err.SysErr!u32 {
    const p: *proc.Proc = proc.myproc() orelse @panic("fetchint: no process");
    const n = p.tf.eax;
    console.cprintf("syscall not implemented: {}\n", .{n});
    @panic("syscall");
}

const syscalls = [_]*const fn () err.SysErr!u32{
    unimplemented,
    sysproc.sys_fork,
    sysproc.sys_exit,
    sysproc.sys_wait,
    unimplemented,
    unimplemented,
    unimplemented,
    sysfile.sys_exec,
    unimplemented,
    unimplemented,
    sysfile.sys_dup,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    sysfile.sys_open,
    sysfile.sys_write,
    sysfile.sys_mknod,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
};

const ERROR = 0xFFFF_FFFF; // That iss, -1 when interpreted as a signed integer

pub fn syscall() void {
    const currproc: *proc.Proc = proc.myproc() orelse @panic("syscall: no proc");
    const num = currproc.tf.eax;
    if (num > 0 and num < syscalls.len) {
        if (syscalls[num]()) |result| {
            currproc.tf.eax = result;
        } else |syserr| {
            console.cprintf("{} for syscall {}, setting eax = -1\n", .{ syserr, num });
            currproc.tf.eax = ERROR;
        }
    } else {
        console.cprintf("{d} {s}: unknow syscall {d}\n", .{ currproc.pid, currproc.name, num });
        currproc.tf.eax = ERROR;
    }
}

pub fn fetchint(addr: usize, ip: *u32) err.SysErr!void {
    const p: *proc.Proc = proc.myproc() orelse @panic("fetchint: no process");
    if (addr >= p.sz or addr + @sizeOf(u32) > p.sz) {
        return err.SysErr.ErrFault;
    }
    ip.* = @as(*u32, @ptrFromInt(addr)).*;
}

pub fn fetchstr(addr: usize, pp: *[]const u8) err.SysErr!void {
    const p: *proc.Proc = proc.myproc() orelse @panic("fetchstr: no process");
    if (addr >= p.sz) {
        return err.SysErr.ErrFault;
    }
    const buf: [*]const u8 = @ptrFromInt(addr);
    for (0..p.sz) |i| {
        if (buf[i] == 0) {
            pp.* = buf[0..i];
            return;
        }
    }
    return err.SysErr.ErrFault;
}

pub fn argint(n: usize, ip: *u32) err.SysErr!void {
    return fetchint(proc.myproc().?.tf.esp + @sizeOf(usize) + n * @sizeOf(usize), ip);
}

pub fn argptr(n: usize, pp: *[]const u8, size: usize) err.SysErr!void {
    const p: *proc.Proc = proc.myproc() orelse @panic("argptr: no process");

    var addr: u32 = undefined;
    try argint(n, &addr);
    if (size < 0 or addr > p.sz or addr + size > p.sz) {
        return err.SysErr.ErrFault;
    }

    const buf: [*]const u8 = @ptrFromInt(addr);
    pp.* = buf[0..size];
}

pub fn argstr(n: usize, pp: *[]const u8) err.SysErr!void {
    var addr: u32 = undefined;
    try argint(n, &addr);
    return fetchstr(@as(usize, @intCast(addr)), pp);
}
