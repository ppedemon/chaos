# Chaos: Hardly An Operative System

Chaos is my rendition of the [xv86](https://github.com/mit-pdos/xv6-public) project, ported to Zig so I learn the language as part of the process.

This is work in progress.

# How to Run It

Prerequisites:

  * **Zig compiler:** version 0.13.0. As Zig is still evolving a lot, a newer version might require patching the code. Older versions will definitely not work.
  * **Qemu:** version 9.1.1.

Once you have Zig and Qemu installed, first create a file system image. In the example below, the file system image will be `fs.img`, and it will contain the files `README.md` and `mkfs.zig` in its root directory.

```bash
zig run mkfs.zig -- fs.img README.md mkfs.zig
```

Then:

```bash
zig build run
```

This will compile the kernel, and startup a 2 CPU Qemu VM booting the kernel binary from ROM. The VM will use `fs.img` as the first IDE device (`disk0`). You will find a very poor man's console where you can type stuff. The console supports scrolling and clearing up the current line with `Crtl+U`. Not spectacular by any means, but shows that the initial setup (pagination, segmentation, and interrupts) is working so far. 

*Note:* the kernel is theoretically bootable from grub. Yet, I didn't try making a grub rescue disk because I don't feel like installing grub on my development laptop.

# Credits
This is not, by any means, the first port of xv86 to Zig. This project is heavily based on [xv86-zig](https://github.com/saza-ku/xv6-zig), which gave me an idea of where to start the port and in which order to do things.
