const ulib = @import("ulib.zig");
const std = @import("std");

var buf: [128]u8 = undefined;
var aux: [32]u8 = undefined;

fn getcmd() []u8 {
    ulib.puts("$ ");
    return ulib.gets(&buf);
}

fn cstr(s: []const u8) [*:0]const u8 {
    @memcpy(aux[0..s.len], s);
    aux[s.len] = 0;
    return @ptrCast(&aux[0]);
}

export fn main() callconv(.C) void {
    var input: []u8 = undefined;

    while (true) {
        input = getcmd();
        if (input.len == 0) {
            break;
        }

        if (std.mem.startsWith(u8, input, "cd ")) {
            const path = std.mem.trimLeft(u8, input[2..input.len - 1], " ");
            if (ulib.chdir(cstr(path)) < 0) {
                ulib.fprint(2, "cannot cd to: {s}\n", .{path});
                continue;
            }
        }
    }

    ulib.exit();
}
