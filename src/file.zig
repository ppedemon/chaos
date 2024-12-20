const fs = @import("fs.zig");
const log = @import("log.zig");
const param = @import("param.zig");
const pipe = @import("pipe.zig");
const spinlock = @import("spinlock.zig");
const stat = @import("stat.zig");

pub const File = struct {
    ty: enum { FD_NONE, FD_PIPE, FD_INODE },
    ref: u32,
    readable: bool,
    writable: bool,
    pipe: ?*pipe.Pipe,
    inode: ?*fs.Inode,
    off: u32,

    const Self = @This();

    pub fn falloc() ?*Self {
        ftable.lock.acquire();
        defer ftable.lock.release();

        for (&ftable.file) |*file| {
            if (file.ref == 0) {
                file.ref = 1;
                return file;
            }
        }
        return null;
    }

    pub fn fdup(self: *Self) *Self {
        ftable.lock.acquire();
        defer ftable.lock.release();

        if (self.ref < 1) {
            @panic("fdup: fd not in use");
        }
        self.ref += 1;
        return self;
    }

    pub fn fclose(self: *Self) void {
        var closed: File = undefined;

        {
            ftable.lock.acquire();
            defer ftable.lock.release();

            if (self.ref < 1) {
                @panic("fclose: fd not in use");
            }
            self.ref -= 1;
            if (self.ref > 0) {
                return;
            }
            closed = self.*;
            self.ref = 0;
            self.ty = .FD_NONE;
        }

        if (closed.ty == .FD_PIPE) {
            self.pipe.?.pclose(self.writable);
        } else if (closed.ty == .FD_INODE) {
            log.begin_op();
            closed.inode.?.iput();
            log.end_op();
        }
    }

    pub fn fstat(self: *Self, st: *stat.Stat) bool {
        if (self.ty == .FD_INODE) {
            const inode: *fs.Inode = self.inode orelse @panic("fstat: no inode");
            inode.ilock();
            inode.stati(st);
            inode.iunlock();
            return true;
        }
        return false;
    }

    pub fn fread(self: *Self, buf: []u8, n: u32) ?u32 {
        if (!self.readable) {
            return null;
        }
        if (self.ty == .FD_PIPE) {
            if (self.pipe) |p| {
                return p.pread(buf, n);
            }
            @panic("fread: no pipe");
        }
        if (self.ty == .FD_INODE) {
            const inode: *fs.Inode = self.inode orelse @panic("fread: no inode");
            inode.ilock();
            defer inode.iunlock();
            const result = inode.readi(buf, self.off, n);
            if (result) |r| {
                self.off += r;
            }
            return result;
        }
        @panic("fread: invalid fd");
    }

    pub fn fwrite(self: *Self, buf: []const u8, n: u32) ?u32 {
        if (!self.writable) {
            return null;
        }
        if (self.ty == .FD_PIPE) {
            if (self.pipe) |p| {
                return p.pwrite(buf, n);
            }
            @panic("fwrite: no pipe");
        }
        if (self.ty == .FD_INODE) {
            const inode: *fs.Inode = self.inode orelse @panic("fwrite: no inode");

            // Maximum number of bytes to write. This is quite magical.
            // Rationale: to avoid exceeding the max blocks for a log txn
            // account for the following possible extra block writes:
            //  - inode and indirect block
            //  - 2 extra blocks in case of non-aligned writes
            // NOTE: shouldn't be polluting this layer, but oh well
            const max: u32 = ((param.MAXOPBLOCKS - 1 - 1 - 2) / 2) * 512;

            var i: u32 = 0;
            while (i < n) {
                log.begin_op();
                inode.ilock();
                defer {
                    inode.iunlock();
                    log.end_op();
                }

                const adjusted_n = @min(n - i, max);
                const result = inode.writei(buf[i..], self.off, adjusted_n);
                if (result) |r| {
                    self.off += r;
                    if (r != adjusted_n) {
                        @panic("fwrite: short write");
                    }
                    i += r;
                } else {
                    break;
                }
            }
            return if (i == n) n else null;
        }
        @panic("fwrite: invalid fd");
    }
};

var ftable = struct {
    lock: spinlock.SpinLock,
    file: [param.NFILE]File,
}{
    .lock = spinlock.SpinLock.init("ftable"),
    .file = undefined,
};

pub const DevSwitchTbl = struct {
    read: *const fn (ip: *fs.Inode, dst: []u8, n: u32) ?u32,
    write: *const fn (ip: *fs.Inode, buf: []const u8, n: u32) ?u32,
};

pub var devsw: [param.NDEV]DevSwitchTbl = undefined;

pub const CONSOLE = 1;
