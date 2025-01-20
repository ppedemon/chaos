const ulib = @import("ulib.zig");
const share = @import("share");
const fcntl = share.fcntl;
const fs = share.fs;
const stat = share.stat;

const std = @import("std");

var namebuf: [fs.DIRSIZE + 1]u8 = undefined;

fn fmtname(path: [*:0]const u8) []const u8 {
    @memset(&namebuf, ' ');
    const slice = std.mem.sliceTo(path, 0);
    const i = std.mem.lastIndexOf(u8, slice, "/");
    const filename: []const u8 = if (i) |start| slice[start + 1 ..] else slice;
    const len = @min(namebuf.len, filename.len);
    @memcpy(namebuf[0..len], filename[0..len]);
    return &namebuf;
}

var buf: [512]u8 = undefined;
var dirent: [128]u8 align(@alignOf(fs.DirEnt)) = undefined;

fn ls(path: [*:0]const u8) !void {
    const fd: u32 = ulib.open(path, fcntl.O_RDONLY) catch {
        try ulib.fprint(ulib.stderr, "ls: cannot open {s}\n", .{path});
        return;
    };

    var st: stat.Stat = undefined;
    ulib.fstat(fd, &st) catch {
        try ulib.fprint(ulib.stderr, "ls: cannot stat {s}\n", .{path});
        return;
    };

    switch (st.ty) {
        stat.T_FILE => {
            try ulib.print("{s} {} {} {}\n", .{ fmtname(path), st.ty, st.inum, st.size });
        },
        stat.T_DIR => {
            const slice: []const u8 = std.mem.sliceTo(path, 0);
            if (slice.len + 1 + fs.DIRSIZE + 1 > @sizeOf(@TypeOf(buf))) {
                try ulib.fputs(ulib.stderr, "ls: path too long\n");
            } else {
                @memset(&buf, 0);
                @memcpy(buf[0..slice.len], slice);
                buf[slice.len] = '/';

                while (try ulib.read(fd, &dirent, @sizeOf(fs.DirEnt)) == @sizeOf(fs.DirEnt)) {
                    const de: *fs.DirEnt = @ptrCast(&dirent);
                    if (de.inum == 0) {
                        continue;
                    }

                    const name: []const u8 = std.mem.sliceTo(&de.name, 0);
                    var fname: []u8 = buf[0 .. slice.len + 1 + name.len + 1];
                    @memcpy(fname[slice.len + 1 .. slice.len + 1 + name.len], name);
                    fname[fname.len - 1] = 0;
                    const pname: [*:0]const u8 = @ptrCast(fname.ptr);

                    ulib.stat(pname, &st) catch {
                        try ulib.fprint(ulib.stderr, "ls: cannot stat {s}\n", .{fmtname(pname)});
                        continue;
                    };
                    try ulib.print("{s} {} {} {}\n", .{ fmtname(pname), st.ty, st.inum, st.size });
                }
            }
        },
        else => {},
    }
    try ulib.close(fd);
}

export fn main(argc: u32, argv: [*][*:0]const u8) void {
    if (argc < 2) {
        ls(".") catch unreachable;
        ulib.exit();
    }
    for (1..argc) |i| {
        ls(argv[i]) catch unreachable;
    }
}
