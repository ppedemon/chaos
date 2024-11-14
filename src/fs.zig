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
pub inline fn bblock8(b: u32, sb: SuperBlock) u32 {
    return b / BPB + sb.bmap_start;
}

pub const DIRSIZE = 13;

// A directory is a file containing a sequence of DirEnt structures 
pub const DirEnt = extern struct {
    inum: u16,
    name: [DIRSIZE:0]u8,
};
