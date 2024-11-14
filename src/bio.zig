const fs = @import("fs.zig");
const sleeplock = @import("sleeplock.zig");

pub const Buf = struct {
    flags: u32,
    dev: u32,
    blockno: u32,
    lock: sleeplock.SleepLock,
    refcnt: u32,
    prev: *Buf,
    next: *Buf,
    qnext: *Buf,
    data: [fs.BSIZE]u8,
};

const B_VALID = 0x2; // Buffer read from disk
const B_DIRTY = 0x4; // Buffer must be flushed to disk
