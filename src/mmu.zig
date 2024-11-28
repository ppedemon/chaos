pub const FL_IF = 0x0000_0200; // Mask for interrupt enabled flag

pub const CR0_PE = 0x0000_0001; // Protected mode enable
pub const CR0_WP = 0x0001_0000; // Write protect: forbid writing to read only pages with privilege level = 0
pub const CR0_PG = 0x8000_0000; // Enable paging

pub const CR4_PSE = 0x0000_0010; // Page size extension

pub const SEG_KCODE = 1; // Kernel code
pub const SEG_KDATA = 2; // Kernel data + stack
pub const SEG_UCODE = 3; // User code
pub const SEG_UDATA = 4; // User data + stack
pub const SEG_TSS = 5; // Current process' task state

pub const NSEGS = 6; // 1 + segments above

pub const DPL_KERNEL = 0;
pub const DPL_USER = 3;

// Application segment type bits
pub const STA_X: u4 = 0x8; // Executable segment
pub const STA_W: u4 = 0x2; // Writeable (use with non-executable segments)
pub const STA_R: u4 = 0x2; // Readable (use with executable segments)

// System segment type bits
pub const STS_T32A: u4 = 0x9; // Available 32-bit TSS
pub const STS_IG32: u4 = 0xE; // 32-bit Interrupt Gate
pub const STS_TG32: u4 = 0xF; // 32-bit Trap Gate

// Safe to use packed struct sinze size = multiple of 8.
// Also more convenient, since we can use bit fields.
pub const SegDesc = packed struct {
    lim15_0: u16,
    base15_0: u16,
    base23_16: u8,
    ty: u4, // Segment type (see STS constants)
    s: u1, // 0 = System (segment defining a TSS or a LDT), 1 = application (code or data segment)
    dpl: u2, // Descriptor Privilege Level
    p: u1, // Present flag
    lim19_16: u4,
    avl: u1, // Unused (AVaiLable for SW use)
    rsv1: u1, // Reserved
    db: u1, // 0 = (default) 16 bit segment, 1 = (big) 32 bit segment
    g: u1, // Granularity (limit = limit * 4k when set)
    base31_24: u8,

    const Self = @This();

    pub fn new(ty: u4, base: u32, lim: u32, dpl: u2) Self {
        return .{
            .lim15_0 = @intCast((lim >> 12) & 0xFFFF),
            .base15_0 = @intCast(base & 0xFFFF),
            .base23_16 = @intCast((base >> 16) & 0xFF),
            .ty = ty,
            .s = 1,
            .dpl = dpl,
            .p = 1,
            .lim19_16 = @intCast((lim >> 28) & 0x0F),
            .avl = 0,
            .rsv1 = 0,
            .db = 1,
            .g = 1,
            .base31_24 = @intCast((base >> 24) & 0xFF),
        };
    }

    pub fn new16(ty: u4, base: u32, lim: u32, dpl: u2) Self {
        return .{
            .lim15_0 = @intCast((lim & 0xFFFF) & 0xFFFF),
            .base15_0 = @intCast(base & 0xFFFF),
            .base23_16 = @intCast((base >> 16) & 0xFF),
            .ty = ty,
            .s = 1,
            .dpl = dpl,
            .p = 1,
            .lim19_16 = @intCast((lim >> 16) & 0x0F),
            .avl = 0,
            .rsv1 = 0,
            .db = 1,
            .g = 0,
            .base31_24 = @intCast((base >> 24) & 0xFF),
        };
    }
};

// Same as above: size here is 64 bits, multiple of 8 as well. So
// we can safely use a packed struct, as opposed to an extern one.
pub const GateDesc = packed struct {
    off15_0: u16, // low 16 bits of offset in cs segment
    cs: u16, // cs segment selector
    args: u5, // # of args, 0 for interrupt and trap gates
    rsv1: u3, // reserved, set to 0
    ty: u4, // type: 32 bits Interrupt or Trap gate (STS_IG32 or STS_TG32)
    s: u1, // this is a system descriptor, so it must be set to zero
    dpl: u2, // Privilege levels allowed to access this interrupt
    p: u1, // Present flag
    off31_16: u16, // hi 16 bits of offset in cs segment

    const Self = @This();

    pub fn new(isTrap: bool, sel: u16, off: u32, d: u2) Self {
        return .{
            .off15_0 = @intCast(off & 0xFFFF),
            .cs = sel,
            .args = 0,
            .rsv1 = 0,
            .ty = if (isTrap) STS_TG32 else STS_IG32,
            .s = 0,
            .dpl = d,
            .p = 1,
            .off31_16 = @intCast(off >> 16),
        };
    }
};

pub const NPDENTRIES = 1024;
pub const NPTENTRIES = 1024;
pub const PGSIZE: usize = 4096;

pub const PTXSHIFT = 12;
pub const PDXSHIFT = 22;

pub const PTE_P = 0x001; // Present flag
pub const PTE_W = 0x002; // Writeable flag
pub const PTE_U = 0x004; // User/Supervisor flag
pub const PTE_S = 0x080; // Size flag (1 = 4Mb pages, 0 = 4kb pages)

pub const PdEntry = usize;
pub const PtEntry = usize;

pub fn pdx(v: usize) usize {
    return (v >> PDXSHIFT) & 0x3FF;
}

pub fn ptx(v: usize) usize {
    return (v >> PTXSHIFT) & 0x3FF;
}

pub fn pgroundup(sz: usize) usize {
    return (sz + PGSIZE - 1) & ~(PGSIZE - 1);
}

pub fn pgrounddown(sz: usize) usize {
    return sz & ~(PGSIZE - 1);
}

pub fn pteaddr(pte: usize) usize {
    return pte & ~@as(usize, 0xFFF);
}

pub fn pteflags(pte: usize) usize {
    return pte & @as(usize, 0xFFF);
}

// Data held by a Task State Segment, all unused except:
//  - ss0:esp0, pointing to current process kstack
//  - I/O map base address, which we disable
pub const TaskState = extern struct {
    link: u32, // Prev task state selector
    esp0: u32, // Stack pointer after increase in privilege level
    ss0: u16, // Stack segment descriptor after increase in privilege level
    padding0: u16,
    esp1: u32,
    ss1: u16,
    padding1: u16,
    esp2: u32,
    ss2: u16,
    padding2: u16,
    cr3: u32,
    eip: u32,
    eflags: u32,
    eax: u32,
    ecx: u32,
    edx: u32,
    ebx: u32,
    esp: u32,
    ebp: u32,
    esi: u32,
    edi: u32,
    es: u16,
    padding3: u16,
    cs: u16,
    padding4: u16,
    ss: u16,
    padding5: u16,
    ds: u16,
    padding6: u16,
    fs: u16,
    padding7: u16,
    gs: u16,
    padding8: u16,
    ldtr: u16,
    padding9: u16,
    t: u16,
    iomb: u16
};
