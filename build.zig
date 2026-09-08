//! This build belongs to your app, written once by `native eject`:
//! the `native` CLI stops generating a build graph and
//! drives this file through `zig build` instead, and it will
//! never rewrite it. `addAppArtifacts` wires the complete standard app
//! build — executable, `zig build run`, `zig build test`, and
//! the -Dplatform/-Dweb-engine/-Dautomation/-Doptimize flags —
//! from the framework's build/app.zig, so a framework upgrade
//! still upgrades your build.
//!
//! `terminal_sessions = true` opts into the emulator, resolving the
//! lazy `ghostty` pin in this app's own `build.zig.zon` — the
//! consumer-safe seam from `examples/workbench`. Ejected apps still
//! use `native build --yes` / `native test --yes`.

const std = @import("std");
const native_sdk = @import("native_sdk");

pub fn build(b: *std.Build) void {
    _ = native_sdk.addAppArtifacts(b, b.dependency("native_sdk", .{}), .{
        .name = "faku",
        .manifest = "app.json",
        .terminal_sessions = true,
    });
}
