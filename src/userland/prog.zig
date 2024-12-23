export fn main(argc: usize, argv: [*][*:0]u8) callconv(.C) u32 {
  var i: u32 = 0;
  while (i < argc) : (i += 1) {
    argv[i][2] = 'A';
  }
  return 0;
}
