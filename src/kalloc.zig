const memlayout = @import("memlayout.zig");
const mmu = @import("mmu.zig");
const sh = @import("sh.zig");
const string = @import("string.zig");
const spinlock = @import("spinlock.zig");

extern const end: u8;

pub const Run = struct {
    next: ?*Run,
};

pub var kmem = struct {
    lock: spinlock.SpinLock,
    use_lock: bool,
    freelist: ?*Run,
}{
    .lock = spinlock.SpinLock.init("kmem"),
    .use_lock = false,
    .freelist = null,
};

pub fn kinit1(vstart: usize, vend: usize) void {
    freerange(vstart, vend);
}

fn freerange(vstart: usize, vend: usize) void {
    var p = mmu.pgroundup(vstart);
    while (p + mmu.PGSIZE <= vend) : (p += mmu.PGSIZE) {
        kfree(p);
    }
}

fn kfree(v: usize) void {
    if (v % mmu.PGSIZE != 0 or v < @intFromPtr(&end) or memlayout.v2p(v) >= memlayout.PHYSTOP) {
        // NOTE: Not safe to call console.panic here, as lapic might not have been initialized
        sh.panic("kfree");
    }

    string.memset(v, 1, mmu.PGSIZE);

    const run: *Run = @ptrFromInt(v);
    run.next = kmem.freelist;
    kmem.freelist = run;
}

pub fn kalloc() ?usize {
    const opt_ptr = kmem.freelist;
    if (opt_ptr) |ptr| {
        kmem.freelist = ptr.next;
        return @intFromPtr(ptr);
    }
    return null;
}
