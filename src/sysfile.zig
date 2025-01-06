const console = @import("console.zig");
const dir = @import("dir.zig");
const err = @import("err.zig");
const exec = @import("exec.zig");
const file = @import("file.zig");
const fs = @import("fs.zig");
const log = @import("log.zig");
const param = @import("param.zig");
const proc = @import("proc.zig");
const stat = @import("stat.zig");
const string = @import("string.zig");
const syscall = @import("syscall.zig");

const std = @import("std");

fn fdalloc(f: *file.File) err.SysErr!usize {
    const currproc: *proc.Proc = proc.myproc() orelse @panic("fdalloc: no current process");
    for (0..currproc.ofile.len) |fd| {
        if (currproc.ofile[fd] == null) {
            currproc.ofile[fd] = f;
            return fd;
        }
    }
    return err.SysErr.ErrMaxOpen;
}

// Attempt to create an inode for either a file, directory, or device.
// Returns *locked* inode if successfull, err.SysErr otherwise.
fn create(path: []const u8, ty: u16, major: u16, minor: u16) err.SysErr!*fs.Inode {
    var namebuf: [fs.DIRSIZE]u8 = undefined;

    if (dir.nameiparent(path, &namebuf)) |dp| {
        dp.ilock();
        defer dp.iunlockput();

        // File to create already exists: this is ok only if we intend to create
        // an actual filesystem file (that is, not a dir, not a device). In this
        // case, just return its inode.
        const name = string.safeslice(@as([:0]u8, @ptrCast(&namebuf)));
        if (dir.dirlookup(dp, name, null)) |ip| {
            ip.ilock();
            if (ty == stat.T_FILE and ip.ty == stat.T_FILE) {
                return ip;
            }
            ip.iunlockput();
            return err.SysErr.ErrExists;
        }

        const ip = fs.Inode.ialloc(dp.dev, ty);
        ip.ilock();
        ip.major = major;
        ip.minor = minor;
        ip.nlink = 1;
        ip.iupdate();

        if (ty == stat.T_DIR) {
            dp.nlink += 1; // new directory will reference parent via ".."
            dp.iupdate();
            if (!dir.dirlink(ip, ".", ip.inum) or !dir.dirlink(ip, "..", dp.inum)) {
                @panic("create: dots");
            }
        }

        if (!dir.dirlink(dp, name, ip.inum)) {
            @panic("create: dirlink");
        }

        return ip;
    }

    // No parent inode for the file we intend to create
    return err.SysErr.ErrNoEnt;
}

pub fn sys_open() err.SysErr!u32 {
    var path: []const u8 = undefined;
    try syscall.argstr(0, &path);

    var omode: u32 = undefined;
    try syscall.argint(1, &omode);

    var ip: *fs.Inode = undefined;

    log.begin_op();
    defer log.end_op();

    if (omode & file.O_CREATE != 0) {
        ip = try create(path, stat.T_FILE, 0, 0);
    } else {
        if (dir.namei(path)) |result| {
            console.cputs(">>> HERE\n");
            ip = result;
        } else {
            return err.SysErr.ErrNoEnt;
        }
        ip.ilock();
        if (ip.ty == stat.T_DIR and omode != file.O_RDONLY) {
            ip.iunlockput();
            return err.SysErr.ErrInval;
        }
    }

    if (file.File.falloc()) |f| {
        defer ip.iunlockput();
        errdefer f.fclose();
        const fd = try fdalloc(f);
        f.ty = file.FileType.FD_INODE;
        f.inode = ip;
        f.off = 0;
        f.readable = (omode & file.O_WRONLY) == 0;
        f.writable = (omode & file.O_WRONLY) != 0 or (omode & file.O_RDWR) != 0;
        console.cprintf("All good, returning file handler {}\n", .{fd});
        return fd;
    } else {
        ip.iunlockput();
        return err.SysErr.ErrMaxOpen;
    }
}

pub fn sys_exec() err.SysErr!u32 {
    var path: []const u8 = undefined;
    var argv: [param.MAXARG][]const u8 = undefined;

    var uargv: u32 = undefined;
    var uarg: u32 = undefined;

    try syscall.argstr(0, &path);
    try syscall.argint(1, &uargv);
    @memset(std.mem.asBytes(&argv), 0);

    var i: usize = 0;
    while (true) : (i += 1) {
        if (i >= argv.len) {
            return err.SysErr.ErrArgs;
        }
        try syscall.fetchint(@as(usize, @intCast(uargv)) + 4 * i, &uarg);
        if (uarg == 0) {
            break;
        }
        try syscall.fetchstr(@as(usize, @intCast(uarg)), &argv[i]);
    }

    const exec_argv: []const []const u8 = argv[0..i];

    console.cprintf("path = {s}\n", .{path});
    for (exec_argv, 0..) |arg, j| {
        console.cprintf("argv[{}] = {s}\n", .{ j, arg });
    }

    return exec.exec(path, exec_argv);
}
