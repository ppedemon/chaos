pub const ELF_MAGIC = 0x464C457F;

pub const ElfHdr = extern struct {
    magic: u32,
    elf: [12]u8,
    ty: u16,
    machine: u16,
    version: u32,
    entry: u32,
    phoff: u32,
    shoff: u32,
    flags: u32,
    ehsize: u16,
    phentisize: u16,
    phnum: u16,
    shentsize: u16,
    shnum: u16,
    shstrndx: u16,
};

pub const ProgHdr = extern struct {
  ty: u32,
  off: u32,
  vaddr: u32,
  paddr: u32,
  filesz: u32,
  memsz: u32,
  flags: u32,
  algn: u32,
};

pub const ELF_PROG_LOAD = 1;

pub const ELF_PROG_FLAG_EXEC = 1;
pub const ELF_PROG_FLAG_WRITE = 2;
pub const ELF_PROG_FLAG_READ = 4;
