# Chaos: Hardly An Operative System
Chaos is my rendition of the [xv86](https://github.com/mit-pdos/xv6-public) project, ported to Zig so I learn the language as part of the process.

# How to Run It
Prerequisites:

  * **Zig compiler:** version 0.13.0. As Zig is still evolving a lot, a newer version might require patching the code. Older versions will definitely not work.
  * **Qemu:** version 9.1.1.

Once you have Zig and Qemu installed, you can run `zig build` with any of the following:

  * `install`: produce kernel binaries.
  * `userland`: build user programs, assumed to be in `src/userland` folder.
  * `mkfs`: `userland` + create file system image with user programs. The filesystem's name will be `fs.img`, and it will be located in the project's root folder.
  * `quickrun`: `install` + run the kernel with `fs.img` (assumed to exist) mounted as the first IDE device. Useful if you previously built the file system and just changed kernel code. A qemu `i386` instance will boot the kernel from ROM.
  * `run`: `install` + `mkfs` + run the kernel as explained above. This is what you should execute if you changed userland code and want to check how it is executed by the kernel.

*Note:* the kernel is theoretically bootable from grub. Yet, I didn't try making a grub rescue disk because I don't feel like installing grub on my development laptop.

# What to Expect
On execution you will find a console executing a shell. The console supports scrolling, clearing up the current line with `Crtl+U` and getting the list of processes with `Ctrl+P`. The control sequence `Ctrl+D` is interpreted as EOF, as usual. The shell allows to execute the following commands, bundled in the file system by the build process:

  * cat
  * echo
  * grep
  * kill
  * ln
  * ls
  * mkdir
  * rm
  * sleep

In addition, the shell supports:

  * Redirecting `stdin` and `stdout`: `cat < ls > out.txt`.
  * Piping: `ls | grep zombie | wc`
  * Sequencing: `sleep 100 ; echo Done sleeping`
  * Background: `(sleep 100; echo Done seeping) & ; cat`

# Credits
This is not, by any means, the first port of xv86 to Zig. At its beginnings, this project was based on [xv86-zig](https://github.com/saza-ku/xv6-zig). Albeit quite incomplete, the cited project gave me an idea of where to start the port and in which order to do things.
