const std = @import("std");

const fs = @import("src/fs.zig");
const param = @import("src/param.zig");

// Disk layout:
// [boot block | super block | log | inode blocks | free bitmap | data blocks]

// 200 inodes in our disk
const NINODES = 200;

const T_DIR = 1; // Directory inode type
const T_FILE = 2; // File inode type

// # of blocks required for the free bitmap of a disk with FSSIZE blocks
const nbitmap = param.FSSIZE / (fs.BSIZE * 8) + 1;

// # of blocks required for NINODES inodes
const ninodeblocks = NINODES / fs.IPB + 1;

// # of blocks for on-disk log
const nlog = param.LOGSIZE;

const static = struct {
    var fd: std.fs.File = undefined;
    var sb: fs.SuperBlock = undefined;

    var buf: [fs.BSIZE]u8 = undefined;
    var freeinode: u16 = 1;
    var freeblock: u32 = undefined;

    const zeroes: [fs.BSIZE]u8 = [1]u8{0} ** fs.BSIZE;
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: mkfs.zig fs.img [files...]\n", .{});
        return error.BadArguments;
    }

    std.debug.assert(fs.BSIZE % @sizeOf(fs.DiskInode) == 0);
    std.debug.assert(fs.BSIZE % @sizeOf(fs.DirEnt) == 0);

    static.fd = try std.fs.cwd().createFile(args[1], .{ .read = true });
    defer static.fd.close();

    // # of meta blocks = boot sector + super block + log blocks + inode blocks + bitmap blocks
    const nmeta = 2 + nlog + ninodeblocks + nbitmap;
    const nblocks = param.FSSIZE - nmeta;

    static.sb = fs.SuperBlock{
        .size = param.FSSIZE,
        .nblocks = nblocks,
        .ninodes = NINODES,
        .nlog = nlog,
        .log_start = 2,
        .inode_start = 2 + nlog,
        .bmap_start = 2 + nlog + ninodeblocks,
    };

    std.debug.print("nmeta = {d} (boot, super, log {d}, inode {d}, bitmap {d}), blocks = {d}, total = {d}\n", .{
        nmeta,
        nlog,
        ninodeblocks,
        nbitmap,
        nblocks,
        param.FSSIZE,
    });

    static.freeblock = nmeta;

    for (0..param.FSSIZE) |i| {
        try wsect(i, &static.zeroes);
    }

    try wstruct(static.sb, &static.buf);
    try wsect(1, &static.buf);

    const root = try ialloc(T_DIR);
    std.debug.assert(root == fs.ROOTINO);

    var de: fs.DirEnt = undefined;
    var dbuf: [@sizeOf(fs.DirEnt)]u8 = undefined;

    @memset(std.mem.asBytes(&de), 0);
    de.inum = root;
    std.mem.copyForwards(u8, &de.name, ".");
    try wstruct(de, &dbuf); // Need wstruct call in order to ensure little endianness
    try iappend(root, &dbuf);

    @memset(std.mem.asBytes(&de), 0);
    de.inum = root;
    std.mem.copyForwards(u8, &de.name, "..");
    try wstruct(de, &dbuf); // Need wstruct call in order to ensure little endianness
    try iappend(root, &dbuf);

    for (2..args.len) |i| {
        const fd = try std.fs.cwd().openFile(args[i], .{});
        defer fd.close();

        const filename = if (std.mem.lastIndexOf(u8, args[i], "/")) |pos|
            args[i][pos + 1 ..]
        else
            args[i];
        const name = if (filename[0] == '_') filename[1..] else filename;
        const inum = try ialloc(T_FILE);

        @memset(std.mem.asBytes(&de), 0);
        de.inum = inum;
        std.mem.copyForwards(u8, &de.name, name[0..@min(name.len, fs.DIRSIZE)]);
        try wstruct(de, &dbuf); // Need wstruct call in order to ensure little endianness
        try iappend(root, &dbuf);

        while (true) {
            const n = try fd.read(&static.buf);
            if (n == 0) {
                break;
            }
            try iappend(inum, static.buf[0..n]);
        }
    }

    // Round up to next block the size fo the root inode
    var rin = try rinode(root);
    rin.size = ((rin.size / fs.BSIZE) + 1) * fs.BSIZE;
    try winode(root, &rin);

    // Write free bitmap block
    try balloc(static.freeblock);
}

fn wstruct(value: anytype, buf: []u8) !void {
    var stream = std.io.fixedBufferStream(buf);
    try stream.writer().writeStructEndian(value, .little);
}

fn rstruct(comptime T: type, buf: []const u8) !T {
    var stream = std.io.fixedBufferStream(buf);
    return stream.reader().readStructEndian(T, .little);
}

fn rsect(sect: usize, buf: []u8) !void {
    try static.fd.seekTo(sect * fs.BSIZE);
    const n = try static.fd.read(buf);
    if (n != fs.BSIZE) {
        return error.ReadError;
    }
}

fn wsect(sect: usize, buf: []const u8) !void {
    try static.fd.seekTo(sect * fs.BSIZE);
    const n = try static.fd.write(buf);
    if (n != fs.BSIZE) {
        return error.WriteError;
    }
}

fn rinode(inum: u32) !fs.DiskInode {
    var buf: [fs.BSIZE]u8 = undefined;
    const blocknum = fs.iblock(inum, &static.sb);
    try rsect(blocknum, &buf);
    return rstruct(fs.DiskInode, buf[@sizeOf(fs.DiskInode) * (inum % fs.IPB) ..]);
}

fn winode(inum: u32, ip: *fs.DiskInode) !void {
    var buf: [fs.BSIZE]u8 = undefined;
    const blocknum = fs.iblock(inum, &static.sb);
    try rsect(blocknum, &buf);
    try wstruct(ip.*, buf[@sizeOf(fs.DiskInode) * (inum % fs.IPB) ..]);
    try wsect(blocknum, &buf);
}

fn ialloc(ty: u16) !u16 {
    const inum: u16 = static.freeinode;
    static.freeinode += 1;

    var din: fs.DiskInode = undefined;
    @memset(std.mem.asBytes(&din), 0);
    din.ty = ty;
    din.nlink = 1;
    din.size = 0;
    try winode(inum, &din);
    return inum;
}

fn iappend(inum: u32, data: []const u8) !void {
    var din = try rinode(inum);

    var off = din.size;
    var n = data.len;
    var targetblock: u32 = undefined;
    var buf: [fs.BSIZE]u8 = undefined;
    var indirect: [fs.NINDIRECT]u32 = undefined;

    while (n > 0) {
        const fblocknum = off / fs.BSIZE; // # of blocks taken by the dir/file was are appending to
        std.debug.assert(fblocknum < fs.MAXFILE);
        if (fblocknum < fs.NDIRECT) {
            if (din.addrs[fblocknum] == 0) {
                din.addrs[fblocknum] = static.freeblock;
                static.freeblock += 1;
            }
            targetblock = din.addrs[fblocknum];
        } else {
            if (din.addrs[fs.NDIRECT] == 0) {
                din.addrs[fs.NDIRECT] = static.freeblock;
                static.freeblock += 1;
            }
            const tempbuf: []u8 = std.mem.asBytes(&indirect);
            try rsect(din.addrs[fs.NDIRECT], tempbuf);
            if (indirect[fblocknum - fs.NDIRECT] == 0) {
                indirect[fblocknum - fs.NDIRECT] = static.freeblock;
                static.freeblock += 1;
                try wsect(din.addrs[fs.NDIRECT], std.mem.asBytes(&indirect));
            }
            targetblock = indirect[fblocknum - fs.NDIRECT];
        }

        // Adjust n to how many bytes we can write to until hitting the end of block #fblocknum
        const adjn = @min(n, (fblocknum + 1) * fs.BSIZE - off);
        try rsect(targetblock, &buf);

        const srcoff = data.len - n;
        const dstoff = off - (fblocknum * fs.BSIZE);
        std.mem.copyForwards(u8, buf[dstoff..], data[srcoff .. srcoff + adjn]);

        try wsect(targetblock, &buf);

        n -= adjn;
        off += adjn;
    }

    din.size = off;
    try winode(inum, &din);
}

fn balloc(used: u32) !void {
    std.debug.print("balloc: first {d} blocks allocated\n", .{used});

    // We really want the free bitmap to take at most a single block
    std.debug.assert(used < fs.BSIZE * 8);

    @memset(&static.buf, 0);
    for (0..used) |i| {
        static.buf[i / 8] = static.buf[i / 8] | (@as(u8, 1) << @intCast(i % 8));
    }

    std.debug.print("balloc: write free bitmap block at sector {d}\n", .{static.sb.bmap_start});
    try wsect(static.sb.bmap_start, &static.buf);
}
