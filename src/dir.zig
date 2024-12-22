const fs = @import("fs.zig");
const param = @import("param.zig");
const proc = @import("proc.zig");
const stat = @import("stat.zig");
const string = @import("string.zig");

const std = @import("std");

pub fn namecmp(cstr: [:0]u8, str: []const u8) bool {
    return std.mem.eql(u8, string.safeslice(cstr), str);
}

// Lookup for an entry with the given name in the directory inode dp.
// If found, return the inode for the entry and set poff_opt to the byte
// offset of the entry in dp.
pub fn dirlookup(dp: *fs.Inode, name: []const u8, poff_opt: ?*u32) ?*fs.Inode {
    if (dp.ty != stat.T_DIR) {
        @panic("dirlookup: not dir");
    }

    var off: u32 = 0;
    var buf: [@sizeOf(fs.DirEnt)]u8 = undefined;
    while (off < dp.size) : (off += @sizeOf(fs.DirEnt)) {
        if (dp.readi(&buf, off, @sizeOf(fs.DirEnt)) != @sizeOf(fs.DirEnt)) {
            @panic("dirlookup: read");
        }
        const de: *fs.DirEnt = @alignCast(@ptrCast(&buf));
        if (de.inum == 0) {
            continue;
        }
        if (namecmp(&de.name, name)) {
            if (poff_opt) |poff| {
                poff.* = off;
            }
            return fs.Inode.iget(dp.dev, de.inum);
        }
    }

    return null;
}

// Write a directory entry (name, inum) into the directory inode dp.
// Returns 0 if the directory was linked, -1 if it already existed
pub fn dirlink(dp: *fs.Inode, name: []const u8, inum: u32) i32 {
    if (dirlookup(dp, name, null)) |ip| {
        ip.iput();
        return -1;
    }

    var off: u32 = 0;
    var buf: [@sizeOf(fs.DirEnt)]u8 = undefined;
    while (off < dp.size) : (off += @sizeOf(fs.DirEnt)) {
        if (dp.readi(&buf, off, @sizeOf(fs.DirEnt)) != @sizeOf(fs.DirEnt)) {
            @panic("dirlookup: read");
        }
        const de: *fs.DirEnt = @alignCast(@ptrCast(&buf));
        if (de.inum == 0) {
            break;
        }
    }

    var de: *fs.DirEnt = @alignCast(@ptrCast(&buf));
    de.inum = @intCast(inum);
    string.safecpy(&de.name, name);

    if (dp.writei(&buf, off, @sizeOf(fs.DirEnt)) != @sizeOf(fs.DirEnt)) {
        @panic("dirlink: write failure");
    }

    return 0;
}

// Copy the next path element from path into name, and return
// a slice starting at the next element after the copied one.
// If there's no next path element, return null. The returned
// slice won't have leading slashes.
fn skipelem(path: []const u8, name: []u8) ?[]const u8 {
    var i: usize = 0;

    while (i < path.len and path[i] == '/') : (i += 1) {}
    if (i == path.len) {
        return null;
    }

    const start = i;
    while (i < path.len and path[i] != '/') : (i += 1) {}

    const len = @min(i - start, fs.DIRSIZE);
    @memset(name, 0);
    @memcpy(name[0..len], path[start .. start + len]);

    while (i < path.len and path[i] == '/') : (i += 1) {}
    return path[i..];
}

// Lookup and return the inode for a path name.
// If stop_at_parent is set, return the inode for the parent and set name
// to the final path element. This must be called from a log transaction,
// since it calls iput().
//
// Gotcha: name will be right padded with zeros. Be sure to get the proper
// slice after calling this function in parent mode. Do it like this:
//
//    const right_name = string.safeslice(@as([:0]u8, @ptrCast(&name)))
//
//  or, alternatively:
//
//    const right_name = std.mem.slice(@as([:0]u8, @ptrCast(&name)))
//
fn namex(path: []const u8, stop_at_parent: bool, name: []u8) ?*fs.Inode {
    var ip: *fs.Inode = undefined;
    if (path.len > 0 and path[0] == '/') {
        ip = fs.Inode.iget(param.ROOTDEV, fs.ROOTINO);
    } else {
        ip = proc.myproc().?.cwd.?.idup();
    }

    var p: []u8 = @constCast(path);
    while (skipelem(p, name)) |curr| {
        ip.ilock();

        // curr path not exhausted, but current inode isn't a dir: we must leave
        if (ip.ty != stat.T_DIR) {
            ip.iunlockput();
            return null;
        }

        // Only a name remains in p, it means we are at desired item's parent.
        // So, return if we must stop at parent.
        if (stop_at_parent and curr.len == 0) {
            ip.iunlock();
            return ip;
        }

        // Result might be right padded with zeroes. Get the right name for lookup:
        const n: []u8 = string.safeslice(@as([:0]u8, @ptrCast(name)));

        if (dirlookup(ip, n, null)) |next| {
            ip.iunlockput();
            ip = next;
            p = @constCast(curr);
        } else {
            ip.iunlockput();
            return null;
        }
    }

    // This conditional is only reachable if we never entered the while,
    // that is, if path is empty or root. In this case, we put the inode
    // back and return null, since empty or root paths have no parent.
    if (stop_at_parent) {
        ip.iput();
        return null;
    }

    return ip;
}

pub fn namei(path: []const u8) ?*fs.Inode {
    var name: [fs.DIRSIZE]u8 = undefined;
    return namex(path, false, &name);
}

pub fn nameiparent(path: []const u8, name: []u8) ?*fs.Inode {
    return namex(path, true, name);
}
