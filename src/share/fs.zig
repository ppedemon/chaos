pub const DIRSIZE = 13;

pub const DirEnt = extern struct {
    inum: u16,
    name: [DIRSIZE:0]u8,
};