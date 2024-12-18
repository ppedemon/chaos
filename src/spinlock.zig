const memlayout = @import("memlayout.zig");
const mmu = @import("mmu.zig");
const proc = @import("proc.zig");
const string = @import("string.zig");
const x86 = @import("x86.zig");

pub const SpinLock = struct {
    locked: u32,
    name: []const u8,
    cpu: ?*proc.CPU,
    pcs: [10]usize, // Call stack (array of PCs) holding the lock

    const Self = @This();

    pub fn init(name: []const u8) Self {
        return .{
            .locked = 0,
            .name = name,
            .cpu = null,
            .pcs = [_]usize{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        };
    }

    pub fn acquire(self: *Self) void {
        pushcli();
        if (self.holding()) {
            @panic("acquire: already holding lock");
        }

        while (x86.xchg(&self.locked, 1) != 0) {}

        // TODO Memory fence here? xchg is supposed to act as a memory fence...

        self.cpu = proc.mycpu();
        getpcs(self.pcs[0..]);
    }

    pub fn release(self: *Self) void {
        if (!self.holding()) {
            @panic("release: not holding lock");
        }
        self.pcs[0] = 0;
        self.cpu = null;

        // TODO Memory fence here? xchg is supposed to act as a memory fence...

        _ = x86.xchg(&self.locked, 0);
        popcli();
    }

    pub fn holding(self: *Self) bool {
        pushcli();
        defer popcli();
        return self.locked != 0 and self.cpu == proc.mycpu();
    }
};

pub fn pushcli() void {
    const eflags = x86.readeflags();
    x86.cli();
    const mycpu = proc.mycpu();
    if (mycpu.ncli == 0) {
        mycpu.intena = (eflags & mmu.FL_IF) != 0;
    }
    mycpu.ncli += 1;
}

pub fn popcli() void {
    // Validation #1: interrupts must be disabled before discarding a previous cli()
    const eflags = x86.readeflags();
    if ((eflags & mmu.FL_IF) != 0) {
        @panic("popcli: interruptible");
    }

    const mycpu = proc.mycpu();
    mycpu.ncli -= 1;

    // Validation #2: don't pop more than you pushed
    if (mycpu.ncli < 0) {
        @panic("popcli: unbalanced");
    }

    if (mycpu.ncli == 0 and mycpu.intena) {
        x86.sti();
    }
}

pub fn getpcs(pcs: []usize) void {
    var ebp: usize = asm volatile ("mov %ebp, %eax"
        : [result] "={eax}" (-> u32),
    );

    var first = true;
    var i: usize = 0;

    // 0xFFFF_FFFF is a sentinel ebp value denoting the bottom of the kernel stack.
    // See start() in entry.zig
    while (ebp != 0 and ebp != 0xFFFF_FFFF and i < pcs.len) : (i += 1) {
        const p: [*]const usize = @ptrFromInt(ebp);
        ebp = p[0];
        // No point in storing getpcs %ebp
        if (first) {
            first = false;
        } else {
            pcs[i] = p[1];
        }
    }
    while (i < pcs.len) : (i += 1) {
        pcs[i] = 0;
    }
}
