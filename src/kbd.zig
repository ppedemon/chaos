const ascii = @import("std").ascii;
const console = @import("console.zig");
const ctrl_code = ascii.control_code;

const x86 = @import("x86.zig");

const bs = ctrl_code.bs;
const ht = ctrl_code.ht;

const KBSTAT_PORT = 0x64;
const KBDATA_PORT = 0x60;
const DIB = 0x01;

const NO = 0;

const SHIFT: u8 = 1 << 0;
const CTL: u8 = 1 << 1;
const ALT: u8 = 1 << 2;

// Toggable
const CAPS: u8 = 1 << 3;
const NUM: u8 = 1 << 4;
const SCROLL: u8 = 1 << 5;

// Special keycode follows
const E0ESC: u8 = 1 << 6;

const KEY_HOME = 0xE0;
const KEY_END = 0xE1;
const KEY_UP = 0xE2;
const KEY_DN = 0xE3;
const KEY_LF = 0xE4;
const KEY_RT = 0xE5;
const KEY_PGUP = 0xE6;
const KEY_PGDN = 0xE7;
const KEY_INS = 0xE8;
const KEY_DEL = 0xE9;

const shiftcode: [256]u8 = init: {
    var initial = [1]u8{NO} ** 256;
    initial[0x1D] = CTL;
    initial[0x2A] = SHIFT;
    initial[0x36] = SHIFT;
    initial[0x38] = ALT;
    initial[0x9D] = CTL;
    initial[0xB8] = ALT;
    break :init initial;
};

const togglecode: [256]u8 = init: {
    var initial = [1]u8{NO} ** 256;
    initial[0x3A] = CAPS;
    initial[0x45] = NUM;
    initial[0x46] = SCROLL;
    break :init initial;
};

const normalmap: [256]u8 = init: {
    var initial = [0x58]u8{
        NO,  0x1B, '1', '2', '3', '4', '5', '6', // 0x00
        '7', '8',  '9', '0', '-', '=', bs,  ht,
        'q', 'w', 'e', 'r', 't',  'y', 'u', 'i', // 0x10
        'o', 'p', '[', ']', '\n', NO,  'a', 's',
        'd',  'f', 'g', 'h',  'j', 'k', 'l', ';', // 0x20
        '\'', '`', NO,  '\\', 'z', 'x', 'c', 'v',
        'b', 'n', 'm', ',', '.', '/', NO, '*', // 0x30
        NO,  ' ', NO,  NO,  NO,  NO,  NO, NO,
        NO,  NO,  NO,  NO,  NO,  NO,  NO,  '7', // 0x40
        '8', '9', '-', '4', '5', '6', '+', '1',
        '2', '3', '0', '.', NO, NO, NO, NO, // 0x50
    } ++ ([1]u8{NO} ** (256 - 0x58));
    initial[0x9C] = '\n'; // KP_Enter
    initial[0xB5] = '/'; // KP_Div
    initial[0xC8] = KEY_UP;
    initial[0xD0] = KEY_DN;
    initial[0xC9] = KEY_PGUP;
    initial[0xD1] = KEY_PGDN;
    initial[0xCB] = KEY_LF;
    initial[0xCD] = KEY_RT;
    initial[0xC7] = KEY_HOME;
    initial[0xCF] = KEY_END;
    initial[0xD2] = KEY_INS;
    initial[0xD3] = KEY_DEL;
    break :init initial;
};

const shiftmap: [256]u8 = init: {
    var initial = [0x58]u8{
        NO,  0x1B, '!', '@', '#', '$', '%', '^', // 0x00
        '&', '*',  '(', ')', '_', '+', bs,  ht,
        'Q', 'W', 'E', 'R', 'T',  'Y', 'U', 'I', // 0x10
        'O', 'P', '{', '}', '\n', NO,  'A', 'S',
        'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', // 0x20
        '"', '~', NO,  '|', 'Z', 'X', 'C', 'V',
        'B', 'N', 'M', '<', '>', '?', NO, '*', // 0x30
        NO,  ' ', NO,  NO,  NO,  NO,  NO, NO,
        NO,  NO,  NO,  NO,  NO,  NO,  NO,  '7', // 0x40
        '8', '9', '-', '4', '5', '6', '+', '1',
        '2', '3', '0', '.', NO, NO, NO, NO, // 0x50
    } ++ ([1]u8{NO} ** (256 - 0x58));
    initial[0x9C] = '\n'; // KP_Enter
    initial[0xB5] = '/'; // KP_Div
    initial[0xC8] = KEY_UP;
    initial[0xD0] = KEY_DN;
    initial[0xC9] = KEY_PGUP;
    initial[0xD1] = KEY_PGDN;
    initial[0xCB] = KEY_LF;
    initial[0xCD] = KEY_RT;
    initial[0xC7] = KEY_HOME;
    initial[0xCF] = KEY_END;
    initial[0xD2] = KEY_INS;
    initial[0xD3] = KEY_DEL;
    break :init initial;
};

const ctlmap: [256]u8 = init: {
    var initial = [0x38]u8{
        NO,        NO,        NO,        NO,         NO,        NO,        NO,        NO,
        NO,        NO,        NO,        NO,         NO,        NO,        NO,        NO,
        ctrl('Q'), ctrl('W'), ctrl('E'), ctrl('R'),  ctrl('T'), ctrl('Y'), ctrl('U'), ctrl('I'),
        ctrl('O'), ctrl('P'), NO,        NO,         '\r',      NO,        ctrl('A'), ctrl('S'),
        ctrl('D'), ctrl('F'), ctrl('G'), ctrl('H'),  ctrl('J'), ctrl('K'), ctrl('L'), NO,
        NO,        NO,        NO,        ctrl('\\'), ctrl('Z'), ctrl('X'), ctrl('C'), ctrl('V'),
        ctrl('B'), ctrl('N'), ctrl('M'), NO,         NO,        NO,        NO,        NO,
    } ++ ([1]u8{NO} ** (256 - 0x38));
    initial[0x9C] = '\r'; // KP_Enter
    initial[0xC8] = KEY_UP;
    initial[0xD0] = KEY_DN;
    initial[0xC9] = KEY_PGUP;
    initial[0xD1] = KEY_PGDN;
    initial[0xCB] = KEY_LF;
    initial[0xCD] = KEY_RT;
    initial[0xC7] = KEY_HOME;
    initial[0xCF] = KEY_END;
    initial[0xD2] = KEY_INS;
    initial[0xD3] = KEY_DEL;
    break :init initial;
};

const charcode = [4][256]u8{ normalmap, shiftmap, ctlmap, ctlmap };

pub fn ctrl(x: u8) u8 {
    return x - '@';
}

fn getc() ?u8 {
    const static = struct {
        var shift: u8 = 0;
    };

    const st = x86.in(u8, KBSTAT_PORT);
    if ((st & DIB) == 0) {
        return null;
    }

    var data = x86.in(u8, KBDATA_PORT);
    
    if (data == 0xE0) {
        static.shift |= E0ESC;
        return 0;
    } else if (data & 0x80 != 0) {
        data = if (static.shift & 0xE0 != 0) data else data & 0x7F;
        static.shift &= ~(shiftcode[data] | E0ESC);
        return 0;
    } else if (static.shift & E0ESC != 0) {
        data |= 0x80;
        static.shift &= ~E0ESC;
    }

    static.shift |= shiftcode[data];
    static.shift ^= togglecode[data];

    var c = charcode[static.shift & (CTL | SHIFT)][data];
    if (static.shift & CAPS != 0) {
        if (ascii.isLower(c)) {
            c = ascii.toUpper(c);
        } else if (ascii.isUpper(c)) {
            c = ascii.toLower(c);
        }
    }

    return c;
}

pub fn kbdintr() void {
    console.consoleintr(getc);
}
