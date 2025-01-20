const err = @import("share").err;
const ulib = @import("ulib.zig");

const Header = extern struct {
    next: *Header,
    size: usize,
};

var base: Header = .{
    .next = undefined,
    .size = 0,
};

var freep: ?*Header = null;

inline fn many(p: *Header) [*]Header {
  return @ptrCast(p);
}

inline fn int(p: *const Header) usize {
  return @intFromPtr(p);
}

pub fn free(ap: usize) void {
    const bp: [*]Header = @as([*]Header, @ptrFromInt(ap)) - 1;
    var bphead: *Header = &bp[0];

    var p = freep orelse unreachable;
    while (int(bphead) <= int(p) or int(bphead) >= int(p.next)) : (p = p.next) {
        if (int(p) >= int(p.next) and (int(bphead) > int(p) or int(bphead) < int(p.next))) {
            break;
        }
    }

    if (bp + bphead.size == many(p.next)) {
        bphead.size += p.next.size;
        bphead.next = p.next.next;
    } else {
        bphead.next = p.next;
    }

    if (many(p) + p.size == bp) {
        p.size += bphead.size;
        p.next = bphead.next;
    } else {
        p.next = bphead;
    }

    freep = p;
}

fn morecore(nu: usize) err.SysErr!?*Header {
    const units = @max(4096, nu);

    const p = try ulib.sbrk(@intCast(units * @sizeOf(Header)));
    var hp: *Header = @alignCast(@as(*Header, @ptrFromInt(p)));
    hp.size = units;
    free(@intFromPtr(many(hp) + 1));
    return freep;
}

pub fn malloc(nbytes: usize) err.SysErr!usize {
    const nunits = (nbytes + @sizeOf(Header) - 1) / @sizeOf(Header) + 1;

    if (freep == null) {
      base.next = &base;
      freep = base.next;
    }

    var prevp = freep.?;
    var p = prevp.next;
    while (true) : ({
        prevp = p;
        p = p.next;
    }) {
        if (p.size >= nunits) {
            if (p.size == nunits) {
                prevp.next = p.next;
            } else {
                p.size -= nunits;
                p = &(many(p) + p.size)[0];
                p.size = nunits;
            }
            freep = prevp;
            return @intFromPtr(many(p) + 1);
        }
        if (p == freep) {
            p = try morecore(nunits) orelse return 0;
        }
    }
}
