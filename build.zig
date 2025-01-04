const std = @import("std");
const Target = std.Target;

const userProgs = [_][]const u8{
    "src/userland/init.zig",
    "src/userland/sh.zig",
};

fn execName(path: []const u8) []const u8 {
    const start = std.mem.lastIndexOf(u8, path, "/");
    const slice = if (start) |s| path[s + 1 ..] else path;
    return std.mem.sliceTo(slice, '.');
}

fn objName(path: []const u8, allocator: *const std.mem.Allocator) ![]const u8 {
    const ename = execName(path);
    var result = try allocator.alloc(u8, ename.len + 2);
    std.mem.copyForwards(u8, result[0..], ename);
    std.mem.copyForwards(u8, result[ename.len..], ".o");
    return result;
}

fn installName(path: []const u8, allocator: *const std.mem.Allocator) ![]const u8 {
    const ename = execName(path);
    const prefix = "zig-out/bin/";
    var result = try allocator.alloc(u8, prefix.len + ename.len);
    std.mem.copyForwards(u8, result[0..], prefix);
    std.mem.copyForwards(u8, result[prefix.len..], ename);
    return result;
}

fn mkfsCmd(allocator: *const std.mem.Allocator) ![]const []const u8 {
    const cmd = try allocator.alloc([]const u8, 5 + userProgs.len);
    cmd[0] = "zig";
    cmd[1] = "run";
    cmd[2] = "mkfs.zig";
    cmd[3] = "--";
    cmd[4] = "fs.img";
    for (userProgs, 5..) |prog, i| {
        cmd[i] = installName(prog, allocator) catch {
            @panic("out of memomry");
        };
    }
    return cmd;
}

fn buildUserland(b: *std.Build, target: std.Build.ResolvedTarget, allocator: *const std.mem.Allocator) *std.Build.Step {
    const step = b.step("userland", "build user programs");

    for (userProgs) |prog| {
        const exec_name = execName(prog);
        const obj_name = objName(prog, allocator) catch {
            @panic("build user progs: out of memory");
        };

        const obj = b.addObject(.{
            .name = obj_name,
            .root_source_file = b.path(prog),
            .target = target,
            .optimize = .ReleaseSmall,
        });
        const exec = b.addExecutable(.{
            .name = exec_name,
            .root_source_file = b.path("src/userland/start.zig"),
            .target = target,
            .optimize = .ReleaseSmall,
            .linkage = .static,
        });
        exec.addObject(obj);
        exec.setLinkerScriptPath(b.path("src/userland/userland.ld"));
        const install = b.addInstallArtifact(exec, .{});
        step.dependOn(&install.step);
    }

    return step;
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    var disabled_features = Target.Cpu.Feature.Set.empty;
    var enabled_features = Target.Cpu.Feature.Set.empty;

    disabled_features.addFeature(@intFromEnum(Target.x86.Feature.mmx));
    disabled_features.addFeature(@intFromEnum(Target.x86.Feature.sse));
    disabled_features.addFeature(@intFromEnum(Target.x86.Feature.sse2));
    disabled_features.addFeature(@intFromEnum(Target.x86.Feature.avx));
    disabled_features.addFeature(@intFromEnum(Target.x86.Feature.avx2));

    enabled_features.addFeature(@intFromEnum(Target.x86.Feature.soft_float));

    const target = b.resolveTargetQuery(.{
        .cpu_arch = Target.Cpu.Arch.x86,
        .os_tag = Target.Os.Tag.freestanding,
        .cpu_features_sub = disabled_features,
        .cpu_features_add = enabled_features,
    });

    // -------------------------------------------------------------------
    // Setup step for building userland programs
    // -------------------------------------------------------------------
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    const user_step = buildUserland(b, target, &allocator);

    // -------------------------------------------------------------------
    // Setup step for creating file system
    // -------------------------------------------------------------------
    const mkfs_str = mkfsCmd(&allocator) catch {
        @panic("out of memory");
    };
    const mkfs_cmd = b.addSystemCommand(mkfs_str);
    mkfs_cmd.step.dependOn(user_step);

    const mkfs_step = b.step("mkfs", "create file system image");
    mkfs_step.dependOn(&mkfs_cmd.step);

    // -------------------------------------------------------------------
    // initCode: embedded assembly to run first OS process
    // -------------------------------------------------------------------
    const initCode = b.addAssembly(.{
        .name = "initcode",
        .source_file = b.path("src/init/initcode.S"),
        .target = target,
        .optimize = .ReleaseSmall,
    });
    initCode.setLinkerScriptPath(b.path("src/init/initcode.ld"));

    const initCodeBin = b.addObjCopy(initCode.getEmittedBin(), .{
        .basename = "initcode.bin",
        .format = .bin,
    });
    const initCodeInstall = b.addInstallFile(initCodeBin.getOutput(), "../src/init/initcode.bin");

    // -------------------------------------------------------------------
    // Build kernel. This is associated to install step, so depending on
    // the install step build the kernel binary.
    // -------------------------------------------------------------------
    const main = b.addObject(.{
        .name = "main",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_source_file = b.path("src/entry.zig"),
        .target = target,
        .optimize = optimize,
        .linkage = .static,
    });
    kernel.addObject(main);
    kernel.addAssemblyFile(b.path("src/trap.S"));
    kernel.addAssemblyFile(b.path("src/vector.S"));
    kernel.addAssemblyFile(b.path("src/swtch.S"));
    kernel.setLinkerScriptPath(b.path("kernel.ld"));
    kernel.step.dependOn(&initCodeInstall.step);
    b.installArtifact(kernel);

    // -------------------------------------------------------------------
    // Run step: depend on the file system setup and the kernel binary.
    // Runs Qemu with the filesystem image on ide0 and the kernel.
    // -------------------------------------------------------------------
    const qemu_str = [_][]const u8{
        "qemu-system-i386",
        "-kernel",
        b.getInstallPath(.prefix, "bin/kernel.elf"),
        "-serial",
        "mon:stdio",
        "-drive",
        "file=fs.img,index=0,media=disk,format=raw",
        "-m",
        "512",
        "-smp",
        "cpus=2,cores=1,threads=1,sockets=2",
    };

    const qemu_cmd = b.addSystemCommand(&qemu_str);
    qemu_cmd.step.dependOn(mkfs_step);
    qemu_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "run the kernel on qemu");
    run_step.dependOn(&qemu_cmd.step);

    // quick run variant: run kernel without making user progs not file system
    const quick_qemu_cmd = b.addSystemCommand(&qemu_str);
    quick_qemu_cmd.step.dependOn(b.getInstallStep());
    
    const quick_run_step = b.step("quickrun", "run the kernel on quemu (no user progs or fs built)");
    quick_run_step.dependOn(&quick_qemu_cmd.step);
}
