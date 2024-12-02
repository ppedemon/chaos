pub const KSTACKSIZE: usize = 4096; // Size of per-process kernel stack

pub const NCPU = 8; // Max # of CPUs
pub const NPROC = 64; // Max # of processes
pub const NPROCFILE = 16; // Max # of open files per process
pub const NFILE = 100; // Max global # of open files
pub const NINODE = 50; // Max # of active inodes
pub const NDEV = 10; // Max major device number

pub const FSSIZE = 1000; // Size of file system in blocks
pub const MAXOPBLOCKS = 10; // Max # of blocks that file system op writes
pub const LOGSIZE = MAXOPBLOCKS * 3; // Max data blocks in on-disk log
pub const NBUF = MAXOPBLOCKS * 3; // Size of disk block cache

pub const ROOTDEV = 0; // Device # of file system root disk

pub const MAXARG = 32; // max exec arguments
