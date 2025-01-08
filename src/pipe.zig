const file = @import("file.zig");
const kalloc = @import("kalloc.zig");
const proc = @import("proc.zig");
const spinlock = @import("spinlock.zig");

const PIPESIZE = 512;

pub const Pipe = struct {
    lock: spinlock.SpinLock,
    data: [PIPESIZE]u8,
    nread: u32, // number of bytes read
    nwrite: u32, // number of bytes written
    readopen: bool,
    writeopen: bool,

    const Self = @This();

    inline fn cleanup(fr: *?*file.File, fw: *?*file.File) void {
        if (fr.*) |f| {
            f.fclose();
        }
        if (fw.*) |f| {
            f.fclose();
        }
    }

    pub fn palloc(fr: *?*file.File, fw: *?*file.File) bool {
        fr.* = file.File.falloc();
        fw.* = file.File.falloc();
        if (fr.* == null or fw.* == null) {
            cleanup(fr, fw);
            return false;
        }

        const p = kalloc.kalloc() orelse return false;
        const pipe: *Self = @alignCast(@as(*Self, @ptrFromInt(p)));
        pipe.nwrite = 0;
        pipe.nread = 0;
        pipe.readopen = true;
        pipe.writeopen = true;
        pipe.lock.init("pipe");

        if (fr.*) |f| {
            f.ty = .FD_PIPE;
            f.readable = true;
            f.writable = false;
            f.pipe = pipe;
        }
        if (fw.*) |f| {
            f.ty = .FD_PIPE;
            f.readable = false;
            f.writable = true;
            f.pipe = pipe;
        }

        return true;
    }

    pub fn pclose(self: *Self, writable: bool) void {
        self.lock.acquire();

        if (writable) {
            self.writeopen = false;
            proc.wakeup(@intFromPtr(&self.nread)); // Flush reader file
        } else {
            self.readopen = false;
            proc.wakeup(@intFromPtr(&self.nwrite)); // Flush writer file
        }

        // NOTE can't use defer self.lock.release(), since we
        // might be kfree-ing self before leaving the function
        if (!self.readopen and !self.writeopen) {
            self.lock.release();
            kalloc.kfree(@intFromPtr(self));
        } else {
            self.lock.release();
        }
    }

    pub fn pwrite(self: *Self, buf: []const u8, n: u32) ?u32 {
        self.lock.acquire();
        defer self.lock.release();

        for (0..n) |i| {
            // written bytes exceeds consumed bytes by PIPESIZE:
            // pipe buffer is full, wait for reader to consume
            while (self.nwrite == self.nread + PIPESIZE) {
                // Reader is closed or we've been killed, we can only leave
                if (!self.readopen or proc.myproc().?.killed) {
                    return null;
                }
                // Reader active, give it a chance to consume fron the pipe
                proc.wakeup(@intFromPtr(&self.nread));
                proc.sleep(@intFromPtr(&self.nwrite), &self.lock);
            }
            // There's room in pipe buffer: write
            self.data[self.nwrite % PIPESIZE] = buf[i];
            self.nwrite += 1;
        }

        proc.wakeup(@intFromPtr(&self.nread));
        return n;
    }

    pub fn pread(self: *Self, buf: []u8, n: u32) ?u32 {
        self.lock.acquire();
        defer self.lock.release();

        // Nothing to read, sleep until there's something in the pipe
        while (self.nread == self.nwrite and self.writeopen) {
            // We've been killed, leave
            if (proc.myproc().?.killed) {
                return null;
            }
            proc.sleep(@intFromPtr(&self.nread), &self.lock);
        }
        var i: u32 = 0;
        while (i < n) : (i += 1) {
            if (self.nread == self.nwrite) {
                break;
            }
            buf[i] = self.data[self.nread % PIPESIZE];
            self.nread += 1;
        }
        proc.wakeup(@intFromPtr(&self.nwrite));
        return i;
    }
};
