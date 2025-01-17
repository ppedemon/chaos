const ulib = @import("ulib.zig");

const share = @import("share");
const fcntl = share.fcntl;
const fs = share.fs;
const stat = share.stat;

const std = @import("std");

fn fmtname(path: [*:0]const u8) []const u8 {
    const static = struct {
        var buf: [fs.DIRSIZE + 1]u8 = undefined;
    };

    @memset(&static.buf, ' ');
    const slice = std.mem.sliceTo(path, 0);
    const i = std.mem.lastIndexOf(u8, slice, "/");
    const filename: []const u8 = if (i) |start| slice[start + 1 ..] else slice;
    const len = @min(static.buf.len, filename.len);
    @memcpy(static.buf[0..len], filename[0..len]);
    return &static.buf;
}

fn ls(path: [*:0]const u8) void {
    const static = struct {
        var buf: [512]u8 = undefined;
        var de: [128]u8 align(@alignOf(fs.DirEnt)) = undefined;
    };

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
            if (slice.len + 1 + fs.DIRSIZE + 1 > @sizeOf(@TypeOf(static.buf))) {
                ulib.fputs(ulib.stderr, "ls: path too long\n");
            } else {
                @memset(&static.buf, 0);
                @memcpy(static.buf[0..slice.len], slice);
                static.buf[slice.len] = '/';

                while (ulib.read(fd, &static.de, @sizeOf(fs.DirEnt)) == @sizeOf(fs.DirEnt)) {
                    const de: *fs.DirEnt = @ptrCast(&static.de);
                    if (de.inum == 0) {
                        continue;
                    }

                    const name: []const u8 = std.mem.sliceTo(&de.name, 0);
                    var fname: []u8 = static.buf[0 .. slice.len + 1 + name.len + 1];
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
