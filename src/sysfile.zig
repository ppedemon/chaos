const console = @import("console.zig");
const dir = @import("dir.zig");
const err = @import("err.zig");
const exec = @import("exec.zig");
const file = @import("file.zig");
const fs = @import("fs.zig");
const log = @import("log.zig");
const param = @import("param.zig");
const pipe = @import("pipe.zig");
const proc = @import("proc.zig");
const string = @import("string.zig");
const syscall = @import("syscall.zig");

const std = @import("std");
const fcntl = @import("share").fcntl;
const stat = @import("share").stat;

fn argfd(n: usize, pfd: ?*u32, pf: ?**file.File) err.SysErr!void {
    const curproc: *proc.Proc = proc.myproc() orelse @panic("argfd: no process");

    var fd: u32 = undefined;
    try syscall.argint(n, &fd);
    if (fd < 0 or fd >= param.NPROCFILE or curproc.ofile[fd] == null) {
        return err.SysErr.ErrBadFd;
    }
    if (pfd) |p| {
        p.* = fd;
    }
    if (pf) |p| {
        p.* = curproc.ofile[fd].?;
    }
}

fn fdalloc(f: *file.File) err.SysErr!usize {
    const curproc: *proc.Proc = proc.myproc() orelse @panic("fdalloc: no process");
    for (0..curproc.ofile.len) |fd| {
        if (curproc.ofile[fd] == null) {
            curproc.ofile[fd] = f;
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

fn isdirempty(dp: *fs.Inode) bool {
    var dirent: fs.DirEnt = undefined;
    var off: usize = 2 * @sizeOf(fs.DirEnt);
    while (off < dp.size) : (off += @sizeOf(fs.DirEnt)) {
        if (dp.readi(std.mem.asBytes(&dirent), off, @sizeOf(fs.DirEnt)) != @sizeOf(fs.DirEnt)) {
            @panic("isdirempty: readi");
        }
        if (dirent.inum != 0) {
            return false;
        }
    }
    return true;
}

pub fn sys_pipe() err.SysErr!u32 {
    var buf: []u8 = undefined;
    try syscall.argptr(0, &buf, @sizeOf([2]u32));
    var p: [*]u32 = @alignCast(@ptrCast(buf.ptr));

    var rf: *file.File = undefined;
    var wf: *file.File = undefined;
    const ok = pipe.Pipe.palloc(&rf, &wf);
    if (!ok) {
        return err.SysErr.ErrMaxOpen;
    }

    errdefer {
        rf.fclose();
        wf.fclose();
    }

    const fd0 = try fdalloc(rf);
    const fd1 = fdalloc(wf) catch |syserr| {
        proc.myproc().?.ofile[fd0] = null;
        return syserr;
    };

    p[0] = fd0;
    p[1] = fd1;
    return 0;
}

pub fn sys_read() err.SysErr!u32 {
    var n: u32 = undefined;
    var f: *file.File = undefined;
    var buf: []u8 = undefined;

    try argfd(0, null, &f);
    try syscall.argint(2, &n);
    try syscall.argptr(1, &buf, n);

    return if (f.fread(buf, n)) |nr| nr else err.SysErr.ErrIO;
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
    return exec.exec(path, exec_argv);
}

pub fn sys_fstat() err.SysErr!u32 {
    var f: *file.File = undefined;
    var buf: []u8 = undefined;

    try argfd(0, null, &f);
    try syscall.argptr(1, &buf, @sizeOf(stat.Stat));

    const st: *stat.Stat = @alignCast(@ptrCast(buf.ptr));
    if (f.fstat(st)) {
        return 0;
    }
    return err.SysErr.ErrBadFd;
}

pub fn sys_chdir() err.SysErr!u32 {
    const curproc: *proc.Proc = proc.myproc() orelse @panic("chdir: no process");

    log.begin_op();
    defer log.end_op();

    var path: []const u8 = undefined;
    try syscall.argstr(0, &path);

    const ip: *fs.Inode = dir.namei(path) orelse {
        return err.SysErr.ErrNoEnt;
    };

    ip.ilock();
    if (ip.ty != stat.T_DIR) {
        ip.iunlockput();
        return err.SysErr.ErrNotDir;
    }
    ip.iunlock();
    curproc.cwd.?.iput();
    curproc.cwd = ip;
    return 0;
}

pub fn sys_dup() err.SysErr!u32 {
    var f: *file.File = undefined;
    try argfd(0, null, &f);

    const fd = try fdalloc(f);
    _ = f.fdup();
    return fd;
}

pub fn sys_open() err.SysErr!u32 {
    var path: []const u8 = undefined;
    try syscall.argstr(0, &path);

    var omode: u32 = undefined;
    try syscall.argint(1, &omode);

    var ip: *fs.Inode = undefined;

    log.begin_op();
    defer log.end_op();

    if (omode & fcntl.O_CREATE != 0) {
        ip = try create(path, stat.T_FILE, 0, 0);
    } else {
        if (dir.namei(path)) |result| {
            ip = result;
        } else {
            return err.SysErr.ErrNoEnt;
        }
        ip.ilock();
        if (ip.ty == stat.T_DIR and omode != fcntl.O_RDONLY) {
            ip.iunlockput();
            return err.SysErr.ErrInval;
        }
    }

    if (file.File.falloc()) |f| {
        errdefer {
            f.fclose();
            ip.iunlockput();
        }
        const fd = try fdalloc(f);
        f.ty = file.FileType.FD_INODE;
        f.inode = ip;
        f.off = 0;
        f.readable = (omode & fcntl.O_WRONLY) == 0;
        f.writable = (omode & fcntl.O_WRONLY) != 0 or (omode & fcntl.O_RDWR) != 0;
        ip.iunlock();
        return fd;
    } else {
        ip.iunlockput();
        return err.SysErr.ErrMaxOpen;
    }
}

pub fn sys_write() err.SysErr!u32 {
    var n: u32 = undefined;
    var f: *file.File = undefined;
    var buf: []const u8 = undefined;

    try argfd(0, null, &f);
    try syscall.argint(2, &n);
    try syscall.argptr(1, &buf, n);

    return if (f.fwrite(buf, n)) |nw| nw else err.SysErr.ErrIO;
}

pub fn sys_mknod() err.SysErr!u32 {
    var path: []u8 = undefined;
    var major: u32 = undefined;
    var minor: u32 = undefined;

    try syscall.argstr(0, &path);
    try syscall.argint(1, &major);
    try syscall.argint(2, &minor);

    log.begin_op();
    defer log.end_op();

    const ip = try create(
        path,
        stat.T_DEV,
        @as(u16, @intCast(major)),
        @as(u16, @intCast(minor)),
    );
    ip.iunlockput();
    return 0;
}

pub fn sys_unlink() err.SysErr!u32 {
    var path: []u8 = undefined;
    try syscall.argstr(0, &path);

    log.begin_op();
    defer log.end_op();

    var name: [fs.DIRSIZE:0]u8 = undefined;
    if (dir.nameiparent(path, &name)) |dp| {
        dp.ilock();
        defer dp.iunlockput();

        const cname: [:0]u8 = @as([:0]u8, @ptrCast(&name));
        if (dir.namecmp(cname, ".") or dir.namecmp(cname, "..")) {
            return err.SysErr.ErrIsDir;
        }

        var off: u32 = undefined;
        const fname: []u8 = string.safeslice(cname);
        if (dir.dirlookup(dp, fname, &off)) |ip| {
            ip.ilock();
            defer ip.iunlockput();

            if (ip.nlink < 1) {
                @panic("unlink: link < 1");
            }
            if (ip.ty == stat.T_DIR and !isdirempty(ip)) {
                return err.SysErr.ErrIsDir;
            }

            var de: fs.DirEnt = undefined;
            const slice = std.mem.asBytes(&de);
            @memset(slice, 0);
            if (dp.writei(slice, off, @sizeOf(fs.DirEnt)) != @sizeOf(fs.DirEnt)) {
                @panic("unlink: writei");
            }
            if (ip.ty == stat.T_DIR) {
                dp.nlink -= 1; // dp lost a child referencing it via ".."
                dp.iupdate();
            }

            ip.nlink -= 1;
            ip.iupdate();

            return 0;
        }
    }

    //No parent inode or inode for the file we intend to delete
    return err.SysErr.ErrNoEnt;
}

// Create new path as a link to the inode for the old path
pub fn sys_link() err.SysErr!u32 {
    var old: []u8 = undefined;
    var new: []u8 = undefined;
    try syscall.argstr(0, &old);
    try syscall.argstr(1, &new);

    log.begin_op();
    defer log.end_op();

    if (dir.namei(old)) |ip| {
        ip.ilock();
        if (ip.ty == stat.T_DIR) {
            ip.iunlockput();
            return err.SysErr.ErrIsDir;
        }

        defer ip.iput();

        ip.nlink += 1;
        ip.iupdate();
        ip.iunlock();

        var name: [fs.DIRSIZE:0]u8 = undefined;
        if (dir.nameiparent(new, &name)) |dp| {
            dp.ilock();
            defer dp.iunlockput();

            const fname = string.safeslice(@as([:0]u8, @ptrCast(&name)));
            if (dp.dev != ip.dev or !dir.dirlink(dp, fname, ip.inum)) {
                return err.SysErr.ErrNoEnt;
            }

            return 0;
        } else {
            // Error handling when no parent for new path: undo link increment in ip
            ip.ilock();
            ip.nlink -= 1;
            ip.iupdate();
            ip.iunlock();
        }
    }

    // no inode for old or new
    return err.SysErr.ErrNoEnt;
}

pub fn sys_mkdir() err.SysErr!u32 {
    var path: []u8 = undefined;
    try syscall.argstr(0, &path);

    log.begin_op();
    defer log.end_op();

    const ip = try create(path, stat.T_DIR, 0, 0);
    ip.iunlockput();
    return 0;
}

pub fn sys_close() err.SysErr!u32 {
    var fd: u32 = undefined;
    var f: *file.File = undefined;
    try argfd(0, &fd, &f);
    if (proc.myproc()) |p| {
        p.ofile[fd] = null;
        f.fclose();
        return 0;
    }
    @panic("close: no process");
}
