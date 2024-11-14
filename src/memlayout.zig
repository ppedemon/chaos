pub const EXTMEM: usize = 0x10_0000; // Low 1 Mb
pub const PHYSTOP: usize = 0x0E00_0000; // Top physical memory arbitrarily set to 224 Mb
pub const DEVSPACE: usize = 0xFE00_0000; // Other hardware devices in the top region

pub const KERNBASE: usize = 0x8000_0000;
pub const KERNLINK: usize = EXTMEM + KERNBASE;

pub fn v2p(v: usize) usize {
    return v - KERNBASE;
}

pub fn p2v(p: usize) usize {
    return p + KERNBASE;
}
