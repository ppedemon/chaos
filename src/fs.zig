const bio = @import("bio.zig");
const console = @import("console.zig");
const file = @import("file.zig");
const param = @import("param.zig");
const sleeplock = @import("sleeplock.zig");
const spinlock = @import("spinlock.zig");
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
pub inline fn iblock(i: u32, sb: SuperBlock) u32 {
    return i / IPB + sb.inode_start;
}

// Bitmap bits per block
pub const BPB = BSIZE * 8;

// Block of free bitmap containing bit for block #b
pub inline fn bblock(b: u32, sb: SuperBlock) u32 {
    return b / BPB + sb.bmap_start;
}

pub const DIRSIZE = 13;

// A directory is a file containing a sequence of DirEnt structures
pub const DirEnt = extern struct {
    inum: u16,
    name: [DIRSIZE:0]u8,
};

pub var superblock: SuperBlock = undefined;

pub fn readsb(dev: u32, sb: *SuperBlock) void {
    const b = bio.Buf.read(dev, 1);
    defer b.release();
    string.memmove(@intFromPtr(sb), @intFromPtr(&b.data), @sizeOf(SuperBlock));
}

fn bzero(dev: u32, blockno: u32) void {
    var b = bio.Buf.read(dev, blockno);
    defer b.release();
    @memset(&b.data, 0);
    // TODO Write to log
}

fn balloc(dev: u32) u32 {
    var b: u32 = 0;
    while (b < superblock.size) : (b += BPB) {
        var bp = bio.Buf.read(dev, bblock(b, superblock));
        var bi: u32 = 0;
        while (bi < BPB and b + bi < superblock.size) : (bi += 1) {
            const n: u8 = @as(u8, 1) << @intCast(bi % 8);
            if ((bp.data[bi / 8] & n) == 0) {
                bp.data[bi / 8] |= n;
                // TODO Write to log
                bp.release();
                bzero(dev, b + bi);
                return b + bi;
            }
        }
        bp.release();
    }
    console.panic("balloc: no free blocks");
}

fn bfree(dev: u32, blockno: u32) void {
    var bp = bio.Buf.read(dev, bblock(blockno, superblock));
    const bi = blockno % BPB;
    const n = @as(u8, 1) << @intCast(bi % 8);
    if (bp.data[bi / 8] & n == 0) {
        console.panic("bfree: block not in use");
    }
    bp.data[bi / 8] &= ~n;
    // TODO Write to log
    bp.release();
}

// -----------------------------------------------------------------------
// Inode tables
// -----------------------------------------------------------------------

var itable = struct {
    inode: [param.NINODE]file.Inode,
    lock: spinlock.SpinLock,
}{
    .lock = spinlock.SpinLock.init("icache"),
    .inode = init: {
        var initial: [param.NINODE]file.Inode = undefined;
        for (0..initial.len) |i| {
            initial[i].lk = sleeplock.SleepLock.init("inode");
        }
        break :init initial;
    },
};

// Allocate an inode of the given type on a device
pub fn ialloc(dev: u32, ty: u16) *file.Inode {
    var i: u32 = 1;
    while (i < superblock.ninodes) : (i += 1) {
        var b = bio.Buf.read(dev, iblock(i, superblock));
        const p: [*]DiskInode = @alignCast(@ptrCast(&b.data));
        var din = p[i % IPB];
        if (din.ty == 0) {
            string.memset(@intFromPtr(&din), 0, @sizeOf(DiskInode));
            din.ty = ty;
            // TODO Write to log
            b.release();
            // TODO return iget from here
            return &itable.inode[0];
        }
        b.release();
    }
    console.panic("ialloc: no free inodes");
}
