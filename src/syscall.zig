const SYS_fork = 1;
const SYS_exit = 2;
const SYS_wait = 3;
const SYS_pipe = 4;
const SYS_read = 5;
const SYS_kill = 6;
const SYS_exec = 7;
const SYS_fstat = 8;
const SYS_chdir = 9;
const SYS_dup = 10;
const SYS_getpid = 11;
const SYS_sbrk = 12;
const SYS_sleep = 13;
const SYS_uptime = 14;
const SYS_open = 15;
const SYS_write = 16;
const SYS_mknod = 17;
const SYS_unlink = 18;
const SYS_link = 19;
const SYS_mkdir = 20;
const SYS_close = 21;

fn unimplemented() i32 {
  @panic("system call not implemented");
}

const syscalls = [_]*const fn()i32 {
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
  unimplemented,
};
