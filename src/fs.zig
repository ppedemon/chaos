const bio = @import("bio.zig");
const console = @import("console.zig");
const file = @import("file.zig");
const log = @import("log.zig");
const param = @import("param.zig");
const sleeplock = @import("sleeplock.zig");
const spinlock = @import("spinlock.zig");
const stat = @import("stat.zig");
const string = @import("string.zig");

const std = @import("std");

pub const ROOTINO = 1;
pub const BSIZE = 512;

// Disk layout:
// [boot block | super block | log | inode blocks | free bitmap | data blocks]

pub const SuperBlock = extern struct {
    size: u32, // Filesystem size in blocks
    nblocks: u32, // # of data blocks
    ninodes: u32, // # of inodes
    nlog: u32, // # of log blocks
    log_start: u32, // Block # of first log block
    inode_start: u32, // Block # of first inode block
    bmap_start: u32, // Block # of first bitmap block
};

pub const NDIRECT = 12;
pub const NINDIRECT = BSIZE / @sizeOf(u32);
pub const MAXFILE = NDIRECT + NINDIRECT;

// @sizeOf(DiskInode) = 64
pub const DiskInode = extern struct {
    ty: u16,
    major: u16,
    minor: u16,
    nlink: u16,
    size: u32, // Size of the file/dir represented by this inode, in bytes
    addrs: [NDIRECT + 1]u32,
};

// Inodes per block
pub const IPB = BSIZE / @sizeOf(DiskInode);

// # of block containing inode #i
pub inline fn iblock(i: u32, sb: *SuperBlock) u32 {
    return i / IPB + sb.inode_start;
}

// Bitmap bits per block
pub const BPB = BSIZE * 8;

// Block of free bitmap containing bit for block #b
pub inline fn bblock(b: u32, sb: *SuperBlock) u32 {
    return b / BPB + sb.bmap_start;
}

pub const DIRSIZE = 13;

// A directory is a file containing a sequence of DirEnt structures
pub const DirEnt = extern struct {
    inum: u16,
    name: [DIRSIZE:0]u8,
};

// -----------------------------------------------------------------------
// Disk blocks
// -----------------------------------------------------------------------

pub var superblock: SuperBlock = undefined;

pub fn readsb(dev: u32, sb: *SuperBlock) void {
    const b = bio.Buf.read(dev, 1);
    defer b.release();
    string.memmove(@intFromPtr(sb), @intFromPtr(&b.data[0]), @sizeOf(SuperBlock));
}

fn bzero(dev: u32, blockno: u32) void {
    var b = bio.Buf.read(dev, blockno);
    defer b.release();
    @memset(&b.data, 0);
    log.log_write(b);
}

fn balloc(dev: u32) u32 {
    var b: u32 = 0;
    while (b < superblock.size) : (b += BPB) {
        var bp = bio.Buf.read(dev, bblock(b, &superblock));
        var bi: u32 = 0;
        while (bi < BPB and b + bi < superblock.size) : (bi += 1) {
            const n: u8 = @as(u8, 1) << @intCast(bi % 8);
            if ((bp.data[bi / 8] & n) == 0) {
                bp.data[bi / 8] |= n;
                log.log_write(bp);
                bp.release();
                bzero(dev, b + bi);
                return b + bi;
            }
        }
        bp.release();
    }
    @panic("balloc: no free blocks");
}

fn bfree(dev: u32, blockno: u32) void {
    var bp = bio.Buf.read(dev, bblock(blockno, &superblock));
    const bi = blockno % BPB;
    const n = @as(u8, 1) << @intCast(bi % 8);
    if (bp.data[bi / 8] & n == 0) {
        @panic("bfree: block not in use");
    }
    bp.data[bi / 8] &= ~n;
    log.log_write(bp);
    bp.release();
}

// -----------------------------------------------------------------------
// Inodes
// -----------------------------------------------------------------------

var itable = struct {
    inode: [param.NINODE]Inode,
    lock: spinlock.SpinLock,
}{
    .lock = spinlock.SpinLock.init("icache"),
    .inode = undefined,
};

pub const Inode = struct {
    dev: u32, // Device number
    inum: u32, // Inode number
    ref: u32, // Reference count
    lock: sleeplock.SleepLock, // Protects data below

    valid: bool, // Has node been read from disk?
    ty: u16, // Type of disk inode
    major: u16,
    minor: u16,
    nlink: u16,
    size: u32,
    addrs: [NDIRECT + 1]u32,

    const Self = @This();

    // Allocate an empty disk inode of the given type on a device.
    // Also allocate a corresponding empty in-memory inode in itable.
    pub fn ialloc(dev: u32, ty: u16) *Self {
        var inum: u32 = 1;
        while (inum < superblock.ninodes) : (inum += 1) {
            var b = bio.Buf.read(dev, iblock(inum, &superblock));
            const p: [*]DiskInode = @alignCast(@ptrCast(&b.data));
            var dip = &p[inum % IPB];
            if (dip.ty == 0) {
                string.memset(@intFromPtr(dip), 0, @sizeOf(DiskInode));
                dip.ty = ty;
                log.log_write(b);
                b.release();
                return iget(dev, inum);
            }
            b.release();
        }
        @panic("ialloc: no free inodes");
    }

    // Find a slot in itable for an inode with number inum on device dev
    pub fn iget(dev: u32, inum: u32) *Inode {
        itable.lock.acquire();
        defer itable.lock.release();

        var empty: ?*Inode = null;

        for (&itable.inode) |*ip| {
            if (ip.ref > 0 and ip.dev == dev and ip.inum == inum) {
                ip.ref += 1;
                return ip;
            }
            if (empty == null and ip.ref == 0) {
                empty = ip;
            }
        }

        if (empty) |ip| {
            ip.dev = dev;
            ip.inum = inum;
            ip.ref = 1;
            ip.valid = false;
            return ip;
        } else {
            @panic("iget: no inodes");
        }
    }

    // Dump contents of in-memory inode to disk.
    // Precondition: this updates protected inode data, so caller must hold self.lock.
    pub fn iupdate(self: *Self) void {
        const b = bio.Buf.read(self.dev, iblock(self.inum, &superblock));
        const p: [*]DiskInode = @alignCast(@ptrCast(&b.data));
        var dip = &p[self.inum % IPB];
        dip.ty = self.ty;
        dip.major = self.major;
        dip.minor = self.minor;
        dip.nlink = self.nlink;
        dip.size = self.size;
        @memcpy(&dip.addrs, &self.addrs);
        log.log_write(b);
        b.release();
    }

    pub fn idup(self: *Self) *Self {
        itable.lock.acquire();
        defer itable.lock.release();
        self.ref += 1;
        return self;
    }

    // Lock inode. If not valid, grab data from disk inode.
    pub fn ilock(self: *Self) void {
        if (self.ref < 1) {
            @panic("ilock: attempt to lock unrefenced inode");
        }

        self.lock.acquire();

        if (!self.valid) {
            const b = bio.Buf.read(self.dev, iblock(self.inum, &superblock));
            defer b.release();
            const p: [*]DiskInode = @alignCast(@ptrCast(&b.data));
            const dip = &p[self.inum % IPB];
            self.ty = dip.ty;
            self.major = dip.major;
            self.minor = dip.minor;
            self.nlink = dip.nlink;
            self.size = dip.size;
            @memcpy(&self.addrs, &dip.addrs);
            self.valid = true;
            if (self.ty == 0) {
                @panic("ilock: no type");
            }
        }
    }

    pub fn iunlock(self: *Self) void {
        if (self.ref < 1 or !self.lock.holding()) {
            @panic("iunlock: not holding lock");
        }
        self.lock.release();
    }

    // Drop reference to in-memory inode. When ref becomes zero it can be used by a
    // posterior call to iget. If it happens that ref becomes zero, the inode is
    // valid and has no links, we can drop the inode from disk as well.
    //
    // Precondition: since we might write to disk, this call must occur in a log txn.
    pub fn iput(self: *Self) void {
        self.lock.acquire();
        if (self.valid and self.nlink == 0) {
            itable.lock.acquire();
            const r = self.ref;
            itable.lock.release();
            if (r == 1) {
                self.itrunc();
                self.ty = 0;
                self.iupdate();
                self.valid = false;
            }
        }
        self.lock.release();

        itable.lock.acquire();
        self.ref -= 1;
        itable.lock.release();
    }

    pub fn iunlockput(self: *Self) void {
        self.iunlock();
        self.iput();
    }

    // Free inode contents, only called when inode doesn't have:
    //  - in-memory references (ref = 0, not an open file or current directory)
    //  - no directory entries references (nlink = 0)
    fn itrunc(self: *Self) void {
        for (0..NDIRECT) |i| {
            if (self.addrs[i] != 0) {
                bfree(self.dev, self.addrs[i]);
                self.addrs[i] = 0;
            }
        }

        if (self.addrs[NDIRECT] != 0) {
            const b = bio.Buf.read(self.dev, self.addrs[NDIRECT]);
            const addrs: [*]u32 = @alignCast(@ptrCast(&b.data));
            for (0..NINDIRECT) |i| {
                if (addrs[i] != 0) {
                    bfree(self.dev, addrs[i]);
                }
            }
            b.release();
            bfree(self.dev, self.addrs[NDIRECT]);
            self.addrs[NDIRECT] = 0;
        }

        self.size = 0;
        self.iupdate();
    }

    pub fn stati(self: *Self, st: *stat.Stat) void {
        st.dev = self.dev;
        st.inum = self.inum;
        st.ty = self.ty;
        st.nlink = self.nlink;
        st.size = self.size;
    }

    // Return the block number of the nth block in this inode.
    // If there is no such block, allocate it.
    fn mapblock(self: *Self, n: u32) u32 {
        var bn = n;

        if (bn < NDIRECT) {
            if (self.addrs[bn] == 0) {
                self.addrs[bn] = balloc(self.dev);
            }
            return self.addrs[bn];
        }

        bn -= NDIRECT;
        if (bn < NINDIRECT) {
            var addr = self.addrs[NDIRECT];
            if (addr == 0) {
                self.addrs[NDIRECT] = balloc(self.dev);
                addr = self.addrs[NDIRECT];
            }
            const b = bio.Buf.read(self.dev, self.addrs[NDIRECT]);
            const addrs: [*]u32 = @alignCast(@ptrCast(&b.data));
            addr = addrs[bn];
            if (addr == 0) {
                addrs[bn] = balloc(self.dev);
                addr = addrs[bn];
                log.log_write(b);
            }
            b.release();
            return addr;
        }

        @panic("blocknum: out of range");
    }

    pub fn readi(self: *Self, dst: []u8, offset: u32, n: u32) ?u32 {
        if (self.ty == stat.T_DEV) {
            if (self.major < 0 or self.major > param.NDEV) {
                return null;
            }
            return file.devsw[self.major].read(self, dst, n);
        }

        if (offset > self.size or offset + n < offset) {
            return null;
        }

        var off = offset;
        var limit = n;
        if (off + limit > self.size) {
            limit = self.size - off;
        }

        var m: u32 = 0;
        var total: u32 = 0;
        var dst_ix = @intFromPtr(&dst[0]);
        while (total < limit) : ({
            total += m;
            off += m;
            dst_ix += m;
        }) {
            const b = bio.Buf.read(self.dev, self.mapblock(off / BSIZE));
            m = @min(limit - total, BSIZE - off % BSIZE);
            string.memmove(dst_ix, @intFromPtr(&b.data[off % BSIZE]), m);
            b.release();
        }

        return limit;
    }

    pub fn writei(self: *Self, src: []const u8, offset: u32, n: u32) ?u32 {
        if (self.ty == stat.T_DEV) {
            if (self.major < 0 or self.major > param.NDEV) {
                return null;
            }
            return file.devsw[self.major].write(self, src, n);
        }

        if (offset > self.size or offset + n < offset) {
            return null;
        }
        if (offset + n > MAXFILE * BSIZE) {
            return null;
        }

        var m: u32 = 0;
        var total: u32 = 0;
        var off = offset;
        var src_ix = @intFromPtr(&src[0]);
        while (total < n) : ({
            total += m;
            off += m;
            src_ix += m;
        }) {
            const b = bio.Buf.read(self.dev, self.mapblock(off / BSIZE));
            m = @min(n - total, BSIZE - off % BSIZE);
            string.memmove(@intFromPtr(&b.data[off % BSIZE]), src_ix, m);
            log.log_write(b);
            b.release();
        }

        if (n > 0 and off > self.size) {
            self.size = off;
            self.iupdate();
        }

        return n;
    }
};

pub fn iinit(dev: u32) void {
    for (&itable.inode) |*inode| {
        inode.lock = sleeplock.SleepLock.init("inode");
    }
    readsb(dev, &superblock);
    console.cprintf(
        \\superblock:
        \\  size = {d} nblocks = {d} ninodes = {d} nlog = {d}
        \\  logstart = {d} inodestart = {d} bmapstart = {d}
        \\
    , .{
        superblock.size,
        superblock.nblocks,
        superblock.ninodes,
        superblock.nlog,
        superblock.log_start,
        superblock.inode_start,
        superblock.bmap_start,
    });
}
