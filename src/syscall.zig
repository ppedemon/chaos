const console = @import("console.zig");
const proc = @import("proc.zig");

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

fn unimplemented() i32 {
    const p: *proc.Proc = proc.myproc() orelse @panic("fetchint: no process");
    const n = p.tf.eax;
    console.cprintf("syscall not implemented: {}\n", .{n});
    @panic("syscall");
}

const syscalls = [_]*const fn () i32{
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
    unimplemented,
};

pub fn fetchint(addr: usize, ip: *i32) i32 {
    const p: proc.Proc = proc.myproc() orelse @panic("fetchint: no process");
    if (addr >= p.sz or addr + @sizeOf(i32) > p.sz) {
        return -1;
    }
    ip.* = @as(*i32, @ptrFromInt(addr)).*;
    return 0;
}

pub fn fetchstr(addr: usize, pp: *[]const u8) i32 {
    const p: proc.Proc = proc.myproc() orelse @panic("fetchstr: no process");
    if (addr >= p.sz) {
        return -1;
    }
    const buf: [*]const u8 = @ptrFromInt(addr);
    for (0..p.sz) |i| {
        if (buf[i] == 0) {
            pp.* = buf[0..i];
            return @as(i32, @intCast(i));
        }
    }
    return -1;
}

pub fn argint(n: usize, ip: *i32) i32 {
    return fetchint(proc.myproc().?.tf.esp + @sizeOf(usize) + n * @sizeOf(usize), ip);
}

pub fn argptr(n: usize, pp: *[]const u8, size: usize) i32 {
    const p: proc.Proc = proc.myproc() orelse @panic("argptr: no process");

    var i: i32 = undefined;
    if (argint(n, &i) < 0) {
        return -1;
    }

    const addr: u32 = @intCast(i);
    if (size < 0 or addr > p.sz or addr + size > p.sz) {
        return -1;
    }

    const buf: [*]const u8 = @ptrFromInt(addr);
    pp.* = buf[0..size];
    return 0;
}

pub fn argstr(n: usize, pp: *[]const u8) i32 {
    var i: i32 = undefined;
    if (argint(n, &i) < 0) {
        return -1;
    }
    return fetchstr(@as(usize, @intCast(i)), pp);
}
