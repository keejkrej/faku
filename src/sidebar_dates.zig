//! Sidebar date-bucket and relative-time helpers.
//!
//! UTC-day grouping and last-activity labels live here. `Model` and
//! sidebar row wiring stay in `main.zig`. Behavior is unchanged from
//! the former `main` date helpers.

const std = @import("std");

/// Ungrouped-session date bucket. UTC civil days from unix ms — Zig std
/// has no tz database, and Faku does not invent one. `updated_at` 0 or
/// omitted is Today so existing catalogs stay in one bucket. This week
/// is after yesterday and still in the current UTC week (Monday start).
/// This month is the same UTC month, older than this week. This year
/// is the same UTC calendar year, older than this month. Not full
/// Waku grouping: no More / Project sort.
pub const DateBucket = enum(u32) {
    today = 0,
    yesterday = 1,
    this_week = 2,
    this_month = 3,
    this_year = 4,
    older = 5,

    pub fn title(self: DateBucket) []const u8 {
        return switch (self) {
            .today => "Today",
            .yesterday => "Yesterday",
            .this_week => "This week",
            .this_month => "This month",
            .this_year => "This year",
            .older => "Older",
        };
    }
};

const ms_per_minute: i64 = 60_000;
const ms_per_hour: i64 = 3_600_000;
const ms_per_day: i64 = 86_400_000;

/// UTC-day bucket for an ungrouped session. Future timestamps count as Today.
/// Week starts Monday (unix day 0 is Thursday, so Monday=0 is `(day + 3) % 7`).
pub fn sessionDateBucket(updated_at: i64, now_ms: i64) DateBucket {
    if (updated_at <= 0 or now_ms <= 0) return .today;
    const today = @divFloor(now_ms, ms_per_day);
    const day = @divFloor(updated_at, ms_per_day);
    if (day >= today) return .today;
    if (day + 1 == today) return .yesterday;
    const weekday = @mod(today + 3, 7);
    const week_start = today - weekday;
    if (day >= week_start) return .this_week;
    const now_ymd = utcYmd(now_ms) orelse return .older;
    const then_ymd = utcYmd(updated_at) orelse return .older;
    if (then_ymd.year == now_ymd.year and then_ymd.month == now_ymd.month) return .this_month;
    if (then_ymd.year == now_ymd.year) return .this_year;
    return .older;
}

/// Short last-activity label from `updated_at` vs wall ms. Missing/0
/// returns null so chrome does not invent a time. Same UTC-day rules
/// as `sessionDateBucket`. Static: last `now_ms`, not a live ticker.
pub fn sessionRelativeTime(updated_at: i64, now_ms: i64, buf: []u8) ?[]const u8 {
    if (updated_at <= 0 or now_ms <= 0) return null;
    const age = now_ms - updated_at;
    if (age < ms_per_minute) return "just now";
    if (age < ms_per_hour) {
        const n = @divTrunc(age, ms_per_minute);
        if (n < 1) return "just now";
        return std.fmt.bufPrint(buf, "{d}m", .{n}) catch null;
    }
    const today = @divFloor(now_ms, ms_per_day);
    const day = @divFloor(updated_at, ms_per_day);
    const days = today - day;
    if (days <= 0) {
        const n = @divTrunc(age, ms_per_hour);
        if (n < 1) return "just now";
        return std.fmt.bufPrint(buf, "{d}h", .{n}) catch null;
    }
    if (days == 1) return "Yesterday";
    if (days < 7) return std.fmt.bufPrint(buf, "{d}d", .{days}) catch null;
    return formatUtcYmd(updated_at, buf);
}

const CivilDate = struct { year: i64, month: u8, day: u8 };

fn utcYmd(ms: i64) ?CivilDate {
    const z0 = @divFloor(ms, ms_per_day);
    const z = z0 + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    var year = yoe + era * 400;
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const day_i = doy - @divFloor(153 * mp + 2, 5) + 1;
    const month_i = if (mp < 10) mp + 3 else mp - 9;
    if (month_i <= 2) year += 1;
    if (day_i < 1 or day_i > 31) return null;
    if (month_i < 1 or month_i > 12) return null;
    return .{
        .year = year,
        .month = @intCast(month_i),
        .day = @intCast(day_i),
    };
}

fn formatUtcYmd(ms: i64, buf: []u8) ?[]const u8 {
    const ymd = utcYmd(ms) orelse return null;
    return std.fmt.bufPrint(buf, "{d}-{d:0>2}-{d:0>2}", .{ ymd.year, ymd.month, ymd.day }) catch null;
}
