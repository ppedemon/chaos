//! To understand what's going on here, check:
//!   - https://pdos.csail.mit.edu/6.828/2011/readings/ia32/MPspec.pdf

const lapic = @import("lapic.zig");
const memlayout = @import("memlayout.zig");
const param = @import("param.zig");
const proc = @import("proc.zig");
const x86 = @import("x86.zig");

const std = @import("std");

pub var cpus: [param.NCPU]proc.CPU = undefined;
pub var ncpu: u8 = 0;
pub var ioapicid: u8 = 0;

const MP = extern struct {
    signature1: u8 = 0,
    signature2: u8 = 0,
    signature3: u8 = 0,
    signature4: u8 = 0,
    physaddr: u32 = 0,
    length: u8 = 0,
    specrev: u8 = 0,
    checksum: u8 = 0,
    ty: u8 = 0,
    imcrp: u8 = 0,
    reserved: [3]u8 = 0,

    const Self = @This();

    fn isvalid(self: *Self) bool {
        if (self.signature1 != '_' or
            self.signature2 != 'M' or
            self.signature3 != 'P' or
            self.signature4 != '_')
        {
            return false;
        }

        const bytes = @as([*]const u8, @ptrCast(self))[0..@sizeOf(Self)];
        return sum(bytes) == 0;
    }
};

const MPConf = extern struct {
    signature1: u8,
    signature2: u8,
    signature3: u8,
    signature4: u8,
    length: u16,
    version: u8,
    checksum: u8,
    product: [20]u8,
    oemtable: *u32,
    oemlength: u16,
    entry: u16,
    lapicaddr: [*]u32,
    xlength: u16,
    xchecksum: u8,
    reserved: u8,

    const Self = @This();

    fn isvalid(self: *Self) bool {
        if (self.signature1 != 'P' or
            self.signature2 != 'C' or
            self.signature3 != 'M' or
            self.signature4 != 'P')
        {
            return false;
        }

        if (self.version != 1 and self.version != 4) {
            return false;
        }

        const bytes = @as([*]const u8, @ptrCast(self))[0..self.length];
        return sum(bytes) == 0;
    }
};

const MPProc = extern struct {
    ty: Entry,
    apicid: u8,
    version: u8,
    flags: u8,
    signature: u32,
    feature: u32,
    reserved: u64,
};

const MPIOApic = extern struct {
    ty: Entry,
    apicno: u8,
    version: u8,
    flags: u8,
    addr: *u32,
};

const Entry = enum(u8) {
    MPPROC = 0x00,
    MPBUS = 0x01,
    MPIOAPIC = 0x02,
    MPIOINTR = 0x03,
    MPLINTR = 0x04,
};

inline fn sum(bytes: []const u8) u8 {
    var s: u8 = 0;
    for (bytes) |b| {
        s = s +% b;
    }
    return s;
}

fn mpsearch1(a: usize, len: usize) ?*MP {
    const addr = memlayout.p2v(a);
    const slice = @as([*]MP, @ptrFromInt(addr))[0 .. len / @sizeOf(MP)];
    for (slice) |*p| {
        if (p.isvalid()) {
            return p;
        }
    }
    return null;
}

fn mpsearch() ?*MP {
    const bda: [*]const u8 = @ptrFromInt(memlayout.p2v(0x400));

    var p: usize = (@as(usize, @intCast(bda[0x0F])) << 8) | @as(usize, @intCast(bda[0x0E]));
    var result = mpsearch1(p, 1024);
    if (result) |mp| {
        return mp;
    }

    p = ((@as(usize, @intCast(bda[0x14])) << 8) | @as(usize, @intCast(bda[0x13]))) * 1024;
    result = mpsearch1(p, 1024);
    if (result) |mp| {
        return mp;
    }

    return mpsearch1(0xF_0000, 0x1_0000);
}

fn mpconfig(p: **MP) ?*MPConf {
    const pmp = mpsearch() orelse return null;
    if (pmp.physaddr == 0) {
        return null;
    }

    const conf: *MPConf = @ptrFromInt(memlayout.p2v(pmp.physaddr));
    if (!conf.isvalid()) {
        return null;
    }

    p.* = pmp;
    return conf;
}

pub fn mpinit() void {
    var pmp: *MP = undefined;
    const conf = mpconfig(&pmp) orelse return;

    lapic.lapic = conf.lapicaddr;

    var p = @intFromPtr(conf) + @sizeOf(MPConf);
    const e = @intFromPtr(conf) + conf.length;
    while (p < e) {
        const ty: Entry = @enumFromInt(@as(*u8, @ptrFromInt(p)).*);
        switch (ty) {
            .MPPROC => {
                const proc_entry: *MPProc = @ptrFromInt(p);
                if (ncpu < param.NCPU) {
                    @memset(std.mem.asBytes(&cpus[ncpu]), 0);
                    cpus[ncpu].apicid = proc_entry.apicid;
                    ncpu += 1;
                }
                p += @sizeOf(MPProc);
            },
            .MPIOAPIC => {
                const ioapic_entry: *MPIOApic = @ptrFromInt(p);
                ioapicid = ioapic_entry.apicno;
                p += @sizeOf(MPIOApic);
            },
            else => p += 8,
        }
    }

    if (pmp.imcrp != 0) {
        x86.out(0x22, @as(u8, 0x70));
        x86.out(0x23, x86.in(u8, 0x23) | 1);
    }
}
