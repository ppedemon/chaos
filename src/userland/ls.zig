const ulib = @import("ulib.zig");
const std = @import("std");

const share = @import("share");
const fcntl = share.fcntl;
const stat = share.stat;

// Hack: duplicated from src/fs.zig 
pub const DIRSIZE = 13;

// Hack: duplicated from src/fs.zig 
pub const DirEnt = extern struct {
    inum: u16,
    name: [DIRSIZE:0]u8,
};

// Global buffers
var namebuf: [DIRSIZE + 1]u8 = undefined;
var pathbuf: [512]u8 = undefined;

fn fmtname(path: [*:0]const u8) []const u8 {
    @memset(&namebuf, ' ');
    const slice = std.mem.sliceTo(path, 0);
    const i = std.mem.lastIndexOf(u8, slice, "/");
    const filename: []const u8 = if (i) |start| slice[start + 1 ..] else slice;
    const len = @min(namebuf.len, filename.len);
    @memcpy(namebuf[0..len], filename[0..len]);
    return &namebuf;
}

fn ls(path: [*:0]const u8) void {
    var fd: u32 = undefined;
    var st: stat.Stat = undefined;

    var result = ulib.open(path, fcntl.O_RDONLY);
    if (result < 0) {
        ulib.fprint(ulib.stderr, "ls: cannot open {s}\n", .{path});
        return;
    }

    fd = @intCast(result);
    result = ulib.fstat(fd, &st);
    if (result < 0) {
        ulib.fprint(ulib.stderr, "ls: cannot stat {s}\n", .{path});
        return;
    }

    var de: DirEnt = undefined;

    switch (st.ty) {
        stat.T_FILE => ulib.print("{s} {} {} {}\n", .{ fmtname(path), st.ty, st.inum, st.size }),
        stat.T_DIR => {
            const slice: []const u8 = std.mem.sliceTo(path, 0);
            if (slice.len + 1 + DIRSIZE + 1 > @sizeOf(@TypeOf(pathbuf))) {
                ulib.fputs(ulib.stderr, "ls: path too long\n");
            } else {
                @memset(&pathbuf, 0);
                @memcpy(pathbuf[0..slice.len], slice);
                pathbuf[slice.len] = '/';

                while (ulib.read(fd, std.mem.asBytes(&de), @sizeOf(DirEnt)) == @sizeOf(DirEnt)) {
                    if (de.inum == 0) {
                        continue;
                    }

                    const name: []const u8 = std.mem.sliceTo(&de.name, 0);
                    var fname: []u8 = pathbuf[0 .. slice.len + 1 + name.len + 1];
                    @memcpy(fname[slice.len + 1 .. slice.len + 1 + name.len], name);
                    fname[fname.len - 1] = 0;
                    const pname: [*:0]const u8 = @ptrCast(fname.ptr);

                    result = ulib.stat(pname, &st);
                    if (result < 0) {
                        ulib.fprint(ulib.stderr, "ls: cannot stat {s}\n", .{fmtname(pname)});
                        continue;
                    }
                    ulib.print("{s} {} {} {}\n", .{ fmtname(pname), st.ty, st.inum, st.size });
                }
            }
        },
        else => {},
    }
    _ = ulib.close(fd);
}

export fn main(argc: u32, argv: [*][*:0]const u8) void {
    if (argc < 2) {
        ls(".");
        ulib.exit();
    }
    for (1..argc) |i| {
        ls(argv[i]);
    }
}
