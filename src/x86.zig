pub inline fn stos(comptime Type: type, dst: usize, data: Type, count: usize) void {
    switch (Type) {
        u8 => asm volatile (
            \\ cld
            \\ rep stosb
            :
            : [_] "{edi}" (dst),
              [_] "{al}" (data),
              [_] "{ecx}" (count),
            : "memory", "cc"
        ),
        u16 => asm volatile (
            \\ cld
            \\ rep stosw
            :
            : [_] "{edi}" (dst),
              [_] "{ax}" (data),
              [_] "{ecx}" (count),
            : "memory", "cc"
        ),
        u32 => asm volatile (
            \\ cld
            \\ rep stosl
            :
            : [_] "{edi}" (dst),
              [_] "{eax}" (data),
              [_] "{ecx}" (count),
            : "memory", "cc"
        ),
        else => @compileError("Invalid data type. Only u8, u16 or u32 allowed, found: " ++ @typeName(Type)),
    }
}

pub inline fn in(comptime Type: type, port: u16) Type {
    return switch (Type) {
        u8 => asm volatile (
            \\ inb %[port], %[result]
            : [result] "={al}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        u16 => asm volatile (
            \\ inw %[port], %[result]
            : [result] "={ax}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        u32 => asm volatile (
            \\ inl %[port], %[result]
            : [result] "={eax}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        else => @compileError("Invalid data type. Only u8, u16 or u32 allowed, found: " ++ @typeName(Type)),
    };
}

pub inline fn out(port: u16, data: anytype) void {
    return switch (@TypeOf(data)) {
        u8 => asm volatile (
            \\ outb %[data], %[port]
            :
            : [port] "N{dx}" (port),
              [data] "{al}" (data),
        ),
        u16 => asm volatile (
            \\ outw %[data], %[port]
            :
            : [port] "N{dx}" (port),
              [data] "{ax}" (data),
        ),
        u32 => asm volatile (
            \\ outl %[data], %[port]
            :
            : [port] "N{dx}" (port),
              [data] "{eax}" (data),
        ),
        else => @compileError("Invalid data type. Only u8, u16 or u32 allowed, found: " ++ @typeName(@TypeOf(data))),
    };
}

pub inline fn lgdt(p: usize, size: u16) void {
    const pd = [_]u16{
        size - 1,
        @as(u16, @intCast(p & 0xFFFF)),
        @as(u16, @intCast(p >> 16)),
    };
    asm volatile (
        \\ lgdt (%[data])
        :
        : [data] "{eax}" (@as(u32, @intFromPtr(&pd))),
    );
}

pub inline fn lidt(p: usize, size: u16) void {
    const pd = [_]u16{
        size - 1,
        @as(u16, @intCast(p & 0xFFFF)),
        @as(u16, @intCast(p >> 16)),
    };
    asm volatile (
        \\ lidt (%[data])
        :
        : [data] "{eax}" (@as(u32, @intFromPtr(&pd))),
    );
}

pub inline fn lcr3(addr: usize) void {
    asm volatile (
        \\ mov %[addr], %cr3
        :
        : [addr] "{eax}" (addr),
    );
}

pub inline fn readeflags() u32 {
    return asm volatile (
        \\ pushfl
        \\ popl %[eflags]
        : [eflags] "={eax}" (-> u32),
    );
}

pub inline fn cli() void {
    asm volatile ("cli");
}

pub inline fn sti() void {
    asm volatile ("sti");
}

pub inline fn xchg(addr: *u32, newval: u32) u32 {
    return asm volatile (
        \\ lock xchgl (%[addr]), %[newval]
        : [result] "={eax}" (-> u32),
        : [addr] "r" (addr),
          [newval] "{eax}" (newval),
        : "memory"
    );
}

pub const TrapFrame = extern struct {
    edi: u32,
    esi: u32,
    ebp: u32,
    oesp: u32, // Useless and ignored
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,

    // Rest of trap frame
    gs: u16,
    padding1: u16,
    fs: u16,
    padding2: u16,
    es: u16,
    padding3: u16,
    ds: u16,
    padding4: u16,
    trapno: u32,

    // Defined by x86 hardware
    err: u32,
    eip: u32,
    cs: u16,
    padding5: u16,
    eflags: u32,

    // Defined by x86 hardware only when crossing rings (e.g., user → kernel)
    esp: u32,
    ss: u16,
    padding6: u16,
};
