//! Spawn / stream effect keys and related runtime constants.
//!
//! Fixed Native effect keys for the demo stream timer (1), one-shot
//! `fx ask` / ACP child (2), daemon-proxy band start (4), and overlapping
//! fx spawn band start (64). Probe stays on `fx_probe_key` (3) in
//! `fx_probe.zig`. Sidecar line cap, demo stream tick, and transcript
//! pin overshoot live here too. Re-exported from `main.zig` so
//! `main.stream_timer_key` / `main.fx_ask_key` call sites keep working.
//! Behavior is unchanged from the former `main` constants.

const std = @import("std");

pub const stream_timer_key: u64 = 1;
pub const fx_ask_key: u64 = 2;
pub const daemon_proxy_key_first: u64 = 4;
/// Overlapping one-shot `fx acp` / `fx ask` children (queue drain while
/// the previous process has not exited yet). Avoids probe/daemon keys.
pub const fx_spawn_overlap_key_first: u64 = 64;
pub const acp_cwd_fallback = ".";
pub const daemon_line_bytes: usize = 64 * 1024;
pub const stream_interval_ms: u64 = 90;
pub const stream_chunk_bytes: usize = 8;
/// Overshoot for a programmatic jump to the transcript end. Native
/// clamps `scroll` `value` against the content edge
/// (`content_extent_y - viewport_extent_y`), so a large source offset
/// lands on the newest turn after layout. Verified: native-sdk.dev
/// scroll docs + engine clamp.
pub const transcript_pin_offset: f32 = 1_000_000;

test "spawn/stream effect keys and runtime sizes match known values" {
    try std.testing.expectEqual(@as(u64, 1), stream_timer_key);
    try std.testing.expectEqual(@as(u64, 2), fx_ask_key);
    try std.testing.expectEqual(@as(u64, 4), daemon_proxy_key_first);
    try std.testing.expectEqual(@as(u64, 64), fx_spawn_overlap_key_first);
    try std.testing.expectEqual(@as(usize, 65536), daemon_line_bytes);
    try std.testing.expectEqual(@as(u64, 90), stream_interval_ms);
    try std.testing.expectEqual(@as(usize, 8), stream_chunk_bytes);
    try std.testing.expectEqual(@as(f32, 1_000_000), transcript_pin_offset);
    try std.testing.expectEqualStrings(".", acp_cwd_fallback);
}
