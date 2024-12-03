const bio = @import("bio.zig");
const console = @import("console.zig");
const fs = @import("fs.zig");
const param = @import("param.zig");
const proc = @import("proc.zig");
const spinlock = @import("spinlock.zig");

const LogHeader = extern struct {
    n: u32,
    block: [param.LOGSIZE]u32,
};

const Log = struct {
    lock: spinlock.SpinLock,
    start: u32,
    size: u32,
    outstanding: u32,
    committing: bool,
    dev: u32,
    header: LogHeader,
};

var log: Log = undefined;
var sb: fs.SuperBlock = undefined;

pub fn init(dev: u32) void {
    if (@sizeOf(LogHeader) >= fs.BSIZE) {
        @panic("initlog: log header too big");
    }

    fs.readsb(dev, &sb);
    log.start = sb.log_start;
    log.size = sb.nlog;
    log.dev = dev;
    log.outstanding = 0;
    log.committing = false;
    log.lock = spinlock.SpinLock.init("log");

    recover();
}

fn recover() void {
    read_head();
    flush_txns();
    log.header.n = 0;
    write_head();
}

fn read_head() void {
    const buf = bio.Buf.read(log.dev, log.start);
    defer buf.release();

    const h: *LogHeader = @alignCast(@ptrCast(&buf.data));
    log.header.n = h.n;
    for (0..h.n) |i| {
        log.header.block[i] = h.block[i];
    }
}

fn write_head() void {
    const buf = bio.Buf.read(log.dev, log.start);
    defer buf.release();

    const h: *LogHeader = @alignCast(@ptrCast(&buf.data));
    h.n = log.header.n;
    for (0..h.n) |i| {
        h.block[i] = log.header.block[i];
    }
    buf.write();
}

fn flush_txns() void {
    for (0..log.header.n) |i| {
        const logbuf = bio.Buf.read(log.dev, log.start + i + 1);
        const dstbuf = bio.Buf.read(log.dev, log.header.block[i]);
        defer {
            logbuf.release();
            dstbuf.release();
        }
        @memcpy(dstbuf.data[0..], logbuf.data[0..]);
        dstbuf.write();
    }
}

pub fn begin_op() void {
    log.lock.acquire();
    defer log.lock.release();

    while (true) {
        if (log.committing) {
            proc.sleep(@intFromPtr(&log), &log.lock);
        } else if (1 + log.header.n + (log.outstanding + 1) * param.MAXOPBLOCKS > param.LOGSIZE) {
            proc.sleep(@intFromPtr(&log), &log.lock);
        } else {
            log.outstanding += 1;
            break;
        }
    }
}

pub fn end_op() void {
    var wants_commit = false;

    log.lock.acquire();

    log.outstanding -= 1;
    if (log.committing) {
        @panic("log: committing");
    }
    if (log.outstanding == 0) {
        wants_commit = true;
        log.committing = true;
    } else {
        proc.wakeup(@intFromPtr(&log));
    }

    log.lock.release();

    if (wants_commit) {
        commit();
        log.lock.acquire();
        defer log.lock.release();
        log.committing = false;
        proc.wakeup(@intFromPtr(&log));
    }
}

fn commit() void {
    if (log.header.n > 0) {
        persist_to_log(); // Put dirty sectors to modify in the log
        write_head();     // Persist log head
        flush_txns();     // Write sectors to disk
        log.header.n = 0;
        write_head();
    }
}

fn persist_to_log() void {
    for (0..log.header.n) |i| {
        const logbuf = bio.Buf.read(log.dev, log.start + i + 1);
        const srcbuf = bio.Buf.read(log.dev, log.header.block[i]);
        defer {
            logbuf.release();
            srcbuf.release();
        }
        @memcpy(logbuf.data[0..], srcbuf.data[0..]);
        logbuf.write();
    }
}

pub fn log_write(b: *bio.Buf) void {
    if (log.header.n >= param.LOGSIZE or log.header.n >= log.size - 1) {
        @panic("log: txn too big");
    }
    if (log.outstanding < 1) {
        @panic("log: write with no txn");
    }

    log.lock.acquire();
    defer log.lock.release();

    var i: u32 = 0;
    while (i < log.header.n) : (i += 1) {
        if (log.header.block[i] == b.blockno) {
            break;
        }
    }
    log.header.block[i] = b.blockno;
    if (i == log.header.n) {
        log.header.n += 1;
    }
    b.flags |= bio.B_DIRTY;
}
