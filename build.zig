const std = @import("std");

pub fn build(b: *std.Build) !void {
    const wardrobe_mod = b.addModule("wardrobe", .{
        .root_source_file = b.path("src/root.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });

    const test_artifact = b.addTest(.{
        .root_module = wardrobe_mod,
    });

    const test_step = b.step("test", "test wardrobe");
    test_step.dependOn(&b.addRunArtifact(test_artifact).step);
}
