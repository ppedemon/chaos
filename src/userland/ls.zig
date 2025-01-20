const ulib = @import("ulib.zig");

const share = @import("share");
const fcntl = share.fcntl;
const fs = share.fs;
const stat = share.stat;

const std = @import("std");

// Global buffers
var nmbuf: [fs.DIRSIZE + 1]u8 = undefined;
var lsbuf: [512]u8 = undefined;
var debuf: [@sizeOf(fs.DirEnt)]u8 align(@alignOf(fs.DirEnt)) = undefined;

fn fmtname(path: [*:0]const u8) []const u8 {
    @memset(&nmbuf, ' ');
    const slice = std.mem.sliceTo(path, 0);
    const i = std.mem.lastIndexOf(u8, slice, "/");
    const filename: []const u8 = if (i) |start| slice[start + 1 ..] else slice;
    const len = @min(nmbuf.len, filename.len);
    @memcpy(nmbuf[0..len], filename[0..len]);
    return &nmbuf;
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

    switch (st.ty) {
        stat.T_FILE => ulib.print("{s} {} {} {}\n", .{ fmtname(path), st.ty, st.inum, st.size }),
        stat.T_DIR => {
            const slice: []const u8 = std.mem.sliceTo(path, 0);
            if (slice.len + 1 + fs.DIRSIZE + 1 > @sizeOf(@TypeOf(lsbuf))) {
                ulib.fputs(ulib.stderr, "ls: path too long\n");
            } else {
                @memset(&lsbuf, 0);
                @memcpy(lsbuf[0..slice.len], slice);
                lsbuf[slice.len] = '/';

                while (ulib.read(fd, &debuf, @sizeOf(fs.DirEnt)) == @sizeOf(fs.DirEnt)) {
                    const de: *fs.DirEnt = @ptrCast(&debuf);
                    if (de.inum == 0) {
                        continue;
                    }

                    const name: []const u8 = std.mem.sliceTo(&de.name, 0);
                    var fname: []u8 = lsbuf[0 .. slice.len + 1 + name.len + 1];
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
