const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const FLib = b.dependency("FLib", .{ .target = target, .optimize = optimize }).module("FLib");

    const FEventExe = b.addExecutable(.{
        .name = "FEvent",
        .root_source_file = b.path("src/Test.zig"),
        .target = target,
        .optimize = optimize,
    });
    FEventExe.root_module.addImport("FLib", FLib);

    const FEventTests = b.addTest(.{
        .root_source_file = b.path("src/Test.zig"),
        .target = target,
        .optimize = optimize,
    });
    FEventTests.root_module.addImport("FLib", FLib);

    const FEventTestsRun = b.addRunArtifact(FEventTests);

    const TestStep = b.step("test", "Run unit tests");
    TestStep.dependOn(&FEventTestsRun.step);

    b.installArtifact(FEventExe);
}
