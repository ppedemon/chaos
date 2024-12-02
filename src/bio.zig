const fs = @import("fs.zig");
const ide = @import("ide.zig");
const param = @import("param.zig");
const sleeplock = @import("sleeplock.zig");
const spinlock = @import("spinlock.zig");

pub const Buf = struct {
    flags: u32,
    dev: u32,
    blockno: u32,
    lock: sleeplock.SleepLock,
    refcnt: u32,
    prev: *Buf,
    next: *Buf,
    qnext: ?*Buf,
    data: [fs.BSIZE]u8,

    const Self = @This();

    fn used(self: *Self) bool {
        return self.refcnt != 0 or (self.flags & B_DIRTY) != 0;
    }

    pub fn read(dev: u32, blockno: u32) *Self {
        const b = bget(dev, blockno);
        if ((b.flags & B_VALID) == 0) {
            ide.iderw(b);
        }
        return b;
    }

    pub fn write(self: *Self) void {
        if (!self.lock.holding()) {
            @panic("bwrite: not holding lock");
        }
        self.flags |= B_DIRTY;
        ide.iderw(self);
    }

    pub fn release(self: *Self) void {
        if (!self.lock.holding()) {
            @panic("brelease: not holding lock");
        }
        self.lock.release();

        bcache.lock.acquire();
        defer bcache.lock.release();

        self.refcnt -= 1;
        if (self.refcnt == 0) {
            self.next.prev = self.prev;
            self.prev.next = self.next;
            self.next = bcache.head.next;
            self.prev = &bcache.head;
            bcache.head.next.prev = self;
            bcache.head.next = self;
        }
    }
};

pub const B_VALID = 0x2; // Buffer read from disk
pub const B_DIRTY = 0x4; // Buffer must be flushed to disk

var bcache = struct {
    lock: spinlock.SpinLock,
    buf: [param.NBUF]Buf,
    head: Buf,
}{
    .lock = spinlock.SpinLock.init("bcache"),
    .buf = undefined,

    // Circular doubly linked list of all buffers through prev/next.
    // Field head is just a sentinel value, head.next is MRU buffer.
    .head = undefined,
};

pub fn binit() void {
    bcache.head.prev = &bcache.head;
    bcache.head.next = &bcache.head;

    for (0..bcache.buf.len) |i| {
        var b = &bcache.buf[i];
        b.next = bcache.head.next;
        b.prev = &bcache.head;
        b.lock = sleeplock.SleepLock.init("buffer");

        bcache.head.next.prev = b;
        bcache.head.next = b;
    }
}

fn bget(dev: u32, blockno: u32) *Buf {
    bcache.lock.acquire();

    var b = bcache.head.next;
    while (b != &bcache.head) : (b = b.next) {
        if (b.dev == dev and b.blockno == blockno) {
            b.refcnt += 1;
            bcache.lock.release();
            b.lock.acquire();
            return b;
        }
    }

    b = bcache.head.prev;
    while (b != &bcache.head) : (b = b.prev) {
        if (!b.used()) {
            b.dev = dev;
            b.blockno = blockno;
            b.flags = 0;
            b.refcnt = 1;
            bcache.lock.release();
            b.lock.acquire();
            return b;
        }
    }

    // Not supposed to get here
    @panic("bget: no buffers");
}
