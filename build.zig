const std = @import("std");
const Target = std.Target;

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
    const prog = b.addObject(.{
        .name = "_prog",
        .root_source_file = b.path("src/userland/prog.zig"),
        .target = target,
        .optimize = optimize,
    });

    const userCode = b.addExecutable(.{
        .name = "prog",
        .root_source_file = b.path("src/userland/crt.zig"),
        .target = target,
        .optimize = optimize,
    });
    userCode.addObject(prog);
    userCode.setLinkerScriptPath(b.path("src/userland/userland.ld"));
    const userCodeInstall = b.addInstallBinFile(userCode.getEmittedBin(), "../../prog");
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
    qemu_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "run the kernel on qemu");
    run_step.dependOn(&qemu_cmd.step);

    const user_step = b.step("userland", "build user programs");
    user_step.dependOn(&userCodeInstall.step);
}
