const ulib = @import("ulib.zig");
const std = @import("std");

fn panic(s: []const u8) noreturn {
    ulib.fprint(ulib.stderr, "{s}\n", .{s});
    ulib.exit();
}

fn fork1() i32 {
    const pid = ulib.fork();
    if (pid < 0) {
        panic("fork");
    }
    return pid;
}

// -----------------------------------------------------------------------
// Cmd line interpreter
// -----------------------------------------------------------------------

const MAXARGS = 10;

const CmdKind = enum(u32) {
    EXEC,
    REDIR,
    PIPE,
    LIST,
    BACK,
};

const Cmd = extern struct {
    kind: CmdKind,
};

const CmdExec = extern struct {
    kind: CmdKind,
    argv: [MAXARGS]?[*:0]u8,
    alen: [MAXARGS]usize,

    pub fn init() *Cmd {
        const c: *CmdExec = @ptrFromInt(ulib.malloc(@sizeOf(CmdExec)));
        c.kind = CmdKind.EXEC;
        return @ptrCast(c);
    }
};

const CmdRedir = extern struct {
    kind: CmdKind,
    cmd: *Cmd,
    file: [*:0]u8,
    flen: usize,
    mode: u32,
    fd: u32,

    pub fn init(subcmd: *Cmd, file: []u8, mode: u32, fd: u32) *Cmd {
        const c: *CmdRedir = @ptrFromInt(ulib.malloc(@sizeOf(CmdRedir)));
        c.kind = CmdKind.REDIR;
        c.cmd = subcmd;
        c.file = @ptrCast(file.ptr);
        c.flen = file.len;
        c.mode = mode;
        c.fd = fd;
        return @ptrCast(c);
    }
};

const CmdPipe = extern struct {
    kind: CmdKind,
    left: *Cmd,
    right: *Cmd,

    pub fn init(leftcmd: *Cmd, rightcmd: *Cmd) *Cmd {
        const c: *CmdPipe = @ptrFromInt(ulib.malloc(@sizeOf(CmdPipe)));
        c.kind = CmdKind.PIPE;
        c.left = leftcmd;
        c.right = rightcmd;
        return @ptrCast(c);
    }
};

const CmdList = extern struct {
    kind: CmdKind,
    head: *Cmd,
    tail: *Cmd,

    pub fn init(headcmd: *Cmd, tailcmd: *Cmd) *Cmd {
        const c: *CmdList = @ptrFromInt(ulib.malloc(@sizeOf(CmdList)));
        c.kind = CmdKind.LIST;
        c.head = headcmd;
        c.tail = tailcmd;
        return @ptrCast(c);
    }
};

const CmdBack = extern struct {
    kind: CmdKind,
    cmd: *Cmd,

    pub fn init(subcmd: *Cmd) *Cmd {
        const c: *CmdBack = @ptrFromInt(ulib.malloc(@sizeOf(CmdBack)));
        c.kind = CmdKind.BACK;
        c.cmd = subcmd;
        return @ptrCast(c);
    }
};

fn runcmd(cmd: *Cmd) noreturn {
    switch (cmd.kind) {
        .EXEC => {
            const exec: *CmdExec = @ptrCast(cmd);
            if (exec.argv[0] == null) {
                ulib.exit();
            }
            _ = ulib.exec(exec.argv[0].?, &exec.argv);
            ulib.fprint(2, "exec {s} failed\n", .{exec.argv[0].?});
            ulib.exit();
        },
        .REDIR => {
            const redir: *CmdRedir = @ptrCast(cmd);
            ulib.print("redir file = {s} end = {} mode = {} fd = {}\n", .{ redir.file[0..redir.flen], redir.file[redir.flen], redir.mode, redir.fd });
            runcmd(redir.cmd);
        },
        .PIPE => {
            const pipe: *CmdPipe = @ptrCast(cmd);
            ulib.print("pipe left = {} right = {}\n", .{ pipe.left.kind, pipe.right.kind });
            ulib.exit();
        },
        .BACK => {
            const back: *CmdBack = @ptrCast(cmd);
            ulib.print("background child = {}\n", .{back.cmd.kind});
            runcmd(back.cmd);
        },
        .LIST => {
            const list: *CmdList = @ptrCast(cmd);
            ulib.print("list head = {}\n", .{list.head.kind});
            runcmd(list.tail);
        },
    }
}

// -----------------------------------------------------------------------
// Cmd line parser
// -----------------------------------------------------------------------

const whitespace = " \t\r\n";
const symbols = "<|>&;()";

fn peek(input: *[]u8, toks: []const u8) bool {
    if (std.mem.indexOfNone(u8, input.*, whitespace)) |start| {
        input.* = input.*[start..];
        return std.mem.indexOfAny(u8, toks, input.*[0..1]) != null;
    }
    input.* = input.*[input.len..];
    return false;
}

fn gettok(input: *[]const u8, tok: ?*[]const u8) u8 {
    var s = std.mem.trim(u8, input.*, whitespace);
    if (tok != null) {
        tok.?.* = s;
    }
    var ret: u8 = 0;
    var len: usize = 0;
    if (s.len > 0) {
        ret = s[0];
        switch (s[0]) {
            '|', '(', ')', ';', '&', '<' => {
                len = 1;
                s = s[1..];
            },
            '>' => {
                len = 1;
                s = s[1..];
                if (s.len > 0 and s[0] == '>') {
                    len = 2;
                    ret = '+'; // file append
                    s = s[1..];
                }
            },
            else => {
                ret = 'a'; // alphanum
                len = std.mem.indexOfAny(u8, s, whitespace ++ symbols) orelse s.len;
                s = s[len..];
            },
        }
        if (tok != null) {
            tok.?.* = tok.?.*[0..len];
        }
        s = std.mem.trim(u8, s, whitespace);
    }
    input.* = s;
    return ret;
}

fn parseexec(input: *[]u8) *Cmd {
    if (peek(input, "(")) {
        return parseblock(input);
    }

    var ret = CmdExec.init();
    var cmd: *CmdExec = @ptrCast(ret);

    var argc: usize = 0;
    ret = parseredirs(ret, input);
    while (!peek(input, "|)&;")) {
        var q: []u8 = undefined;
        const tok = gettok(input, &q);
        if (tok == 0) {
            break;
        }
        if (tok != 'a') {
            panic("syntax");
        }
        cmd.argv[argc] = @ptrCast(q.ptr);
        cmd.alen[argc] = q.len;
        argc += 1;
        if (argc >= MAXARGS) {
            panic("too many args");
        }
        ret = parseredirs(ret, input);
    }
    cmd.argv[argc] = null;
    cmd.alen[argc] = 0;

    return ret;
}

fn parseredirs(cmd: *Cmd, input: *[]u8) *Cmd {
    var q: []u8 = undefined;
    var c = cmd;
    while (peek(input, "<>")) {
        const tok = gettok(input, null);
        if (gettok(input, &q) != 'a') {
            panic("missing file for redierection");
        }
        c = switch (tok) {
            '<' => CmdRedir.init(c, q, ulib.O_RDONLY, 0),
            '>' => CmdRedir.init(c, q, ulib.O_WRONLY | ulib.O_CREATE, 1),
            '+' => CmdRedir.init(c, q, ulib.O_WRONLY | ulib.O_CREATE, 1),
            else => unreachable,
        };
    }
    return c;
}

fn parsepipe(input: *[]u8) *Cmd {
    var cmd = parseexec(input);
    if (peek(input, "|")) {
        _ = gettok(input, null);
        cmd = CmdPipe.init(cmd, parsepipe(input));
    }
    return cmd;
}

fn parseline(input: *[]u8) *Cmd {
    var cmd = parsepipe(input);
    while (peek(input, "&")) {
        _ = gettok(input, null);
        cmd = CmdBack.init(cmd);
    }
    if (peek(input, ";")) {
        _ = gettok(input, null);
        cmd = CmdList.init(cmd, parseline(input));
    }
    return cmd;
}

fn parseblock(input: *[]u8) *Cmd {
    if (!peek(input, "(")) {
        panic("parseblock");
    }
    _ = gettok(input, null);
    var cmd = parseline(input);
    if (!peek(input, ")")) {
        panic("syntax - missing )");
    }
    _ = gettok(input, null);
    cmd = parseredirs(cmd, input);
    return cmd;
}

fn parsecmd(input: *[]u8) *Cmd {
    const cmd = parseline(input);
    _ = peek(input, "");
    if (input.len != 0) {
        ulib.print("leftover: {s}\n", .{input});
        panic("syntax");
    }
    nullterminate(cmd);
    return cmd;
}

fn nullterminate(cmd: *Cmd) void {
    switch (cmd.kind) {
        .EXEC => {
            var exec: *CmdExec = @ptrCast(cmd);
            var i: usize = 0;
            while (exec.argv[i] != null) : (i += 1) {
                exec.argv[i].?[exec.alen[i]] = 0;
            }
        },
        .REDIR => {
            const redir: *CmdRedir = @ptrCast(cmd);
            nullterminate(redir.cmd);
            redir.file[redir.flen] = 0;
        },
        .PIPE => {
            const pipe: *CmdPipe = @ptrCast(cmd);
            nullterminate(pipe.left);
            nullterminate(pipe.right);
        },
        .BACK => {
            const back: *CmdBack = @ptrCast(cmd);
            nullterminate(back.cmd);
        },
        .LIST => {
            const list: *CmdList = @ptrCast(cmd);
            nullterminate(list.head);
            nullterminate(list.tail);
        },
    }
}

// -----------------------------------------------------------------------
// Main loop
// -----------------------------------------------------------------------

var buf: [128]u8 = undefined;

fn getinput() []u8 {
    ulib.puts("$ ");
    return ulib.gets(&buf);
}

fn parsedir(input: *[]u8) [*:0]const u8 {
    _ = peek(input, "");
    const dir: [*:0]u8 = @ptrCast(input.ptr);
    dir[input.len - 1] = 0; // last char is '\n', replace with 0
    return dir;
}

export fn main() callconv(.C) void {
    var input: []u8 = undefined;

    while (true) {
        input = getinput();
        if (input.len == 0) {
            break;
        }

        _ = peek(&input, whitespace);
        if (input.len == 0 or std.mem.eql(u8, input, "cd\n")) {
            continue;
        }

        if (std.mem.startsWith(u8, input, "cd ")) {
            const path = parsedir(@constCast(&input[2..]));
            if (ulib.chdir(path) < 0) {
                ulib.fprint(2, "cannot cd to: {s}\n", .{path});
            }
            continue;
        }

        if (fork1() == 0) {
            runcmd(parsecmd(&input));
        } else {
            _ = ulib.wait();
        }
    }

    ulib.exit();
}
