const ulib = @import("ulib.zig");
const std = @import("std");

var buf: [128]u8 = undefined;
var aux: [128]u8 = undefined;

fn panic(s: []const u8) noreturn {
    ulib.fputs(ulib.stderr, s);
    ulib.exit();
}

fn getcmd() []u8 {
    ulib.puts("$ ");
    return ulib.gets(&buf);
}

fn cstr(s: []const u8) [*:0]const u8 {
    if (s.len + 1 > aux.len) {
        panic("filename too long");
    }
    @memcpy(aux[0..s.len], s);
    aux[s.len] = 0;
    return @ptrCast(&aux[0]);
}

fn fork1() i32 {
    const pid = ulib.fork();
    if (pid < 0) {
        panic("fork");
    }
    return pid;
}

fn parsecmd(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, " ");
}

fn runcmd(cmd: []const u8) noreturn {
    ulib.print("Running in separate process: {s}\n", .{cmd});
    ulib.exit();
}

export fn main() callconv(.C) void {
    var input: []u8 = undefined;

    while (true) {
        input = getcmd();
        if (input.len == 0) {
            break;
        }
        if (std.mem.eql(u8, input[0..input.len - 1], "cd")) {
            continue;
        }

        if (std.mem.startsWith(u8, input, "cd ")) {
            const path = std.mem.trimLeft(u8, input[2 .. input.len - 1], " ");
            if (ulib.chdir(cstr(path)) < 0) {
                ulib.fprint(2, "cannot cd to: {s}\n", .{path});
            }
            continue;
        }

        const cmd = parsecmd(input[0..input.len - 1]);
        if (cmd.len == 0) {
            continue;
        }

        if (fork1() == 0) {
            runcmd(cmd);
        } else {
            _ = ulib.wait();
        }
    }

    ulib.exit();
}
