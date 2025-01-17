pub const T_DIR: u32 = 1;
pub const T_FILE: u32 = 2;
pub const T_DEV: u32 = 3;

pub const Stat = struct {
  ty: u16,
  dev: u32,
  inum: u32,
  nlink: u16,
  size: u32, // Size of file in bytes
};
