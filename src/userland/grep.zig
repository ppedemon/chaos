const ulib = @import("ulib.zig");
const std = @import("std");
const fcntl = @import("share").fcntl;

var buf: [1024]u8 = undefined;

fn grep(re: []const u8, fd: u32) void {
    var m: usize = 0;
    while (true) {
        const n = ulib.read(fd, @as([*]u8, @ptrCast(&buf[m])), @sizeOf(@TypeOf(buf)) - m);
        if (n <= 0) {
            return;
        }

        m += @intCast(n);
        var p: usize = 0;
        while (std.mem.indexOf(u8, buf[p..m], "\n")) |q| {
            if (match(re, buf[p .. p + q])) {
                _ = ulib.write(ulib.stdout, @as([*]const u8, @ptrCast(&buf[p])), q + 1);
            }
            p += q + 1;
        }

        if (p == 0) {
            m = 0;
        }
        if (m > 0) {
            std.mem.copyForwards(u8, &buf, buf[p..m]);
            m -= p;
        }
    }
}

fn match(re: []const u8, text: []const u8) bool {
    if (re[0] == '^') {
        return matchhere(re[1..], text);
    }
    var i: usize = 0;
    while (true) : (i += 1) {
        if (matchhere(re, text[i..])) {
            return true;
        }
        if (i == text.len) {
            break;
        }
    }
    return false;
}

fn matchhere(re: []const u8, text: []const u8) bool {
    if (re.len == 0) {
        return true;
    }
    if (re.len >= 2 and re[1] == '*') {
        return matchstar(re[0], re[2..], text);
    }
    if (re.len == 1 and re[0] == '$') {
        return text.len == 0;
    }
    if (text.len > 0 and (re[0] == '.' or re[0] == text[0])) {
        return matchhere(re[1..], text[1..]);
    }
    return false;
}

fn matchstar(c: u8, re: []const u8, text: []const u8) bool {
    var i: usize = 0;
    while (true) : (i += 1) {
        if (matchhere(re, text[i..])) {
            return true;
        }
        if (i == text.len or (c != '.' and c != text[i])) {
            break;
        }
    }
    return false;
}

pub export fn main(argc: u32, argv: [*][*:0]const u8) void {
    if (argc <= 1) {
        _ = ulib.fputs(ulib.stderr, "usage: grep pattern [file ...]\n");
        ulib.exit();
    }

    const re = std.mem.sliceTo(argv[1], 0);

    if (argc <= 2) {
        grep(re, ulib.stdin);
        ulib.exit();
    }

    for (2..argc) |i| {
        const result = ulib.open(argv[i], fcntl.O_RDONLY);
        if (result < 0) {
            ulib.fprint(ulib.stderr, "grep: cannot open {s}\n", .{argv[i]});
            ulib.exit();
        }
        const fd: u32 = @intCast(result);
        grep(re, fd);
        _ = ulib.close(fd);
    }
    ulib.exit();
}
