//! Sidebar date-bucket and relative-time helpers.
//!
//! Local civil-day grouping and last-activity labels live here. `Model`
//! and sidebar row wiring stay outside this file. Bucket math uses
//! process-local civil Y-M-D from libc `localtime` (`localtime_r` /
//! Windows `localtime_s`) applied **per timestamp** so DST boundaries
//! between `updated_at` and `now_ms` stay correct. Zig has no tz
//! database, and Faku does not invent one, vendor a tzdb, spawn
//! `date(1)`, or add Native NSLocale APIs. Header titles (and the
//! static relative-time words) take an `i18n.Dates` catalog from the
//! caller's resolved Appearance language. This file does not read
//! process env. Callers import this module directly (`sidebar_dates.DateBucket` /
//! `sidebar_dates.sessionDateBucket` / `sidebar_dates.sessionRelativeTime`).
//! Not re-exported from `main`.

const std = @import("std");
const builtin = @import("builtin");
const i18n = @import("i18n.zig");

/// Ungrouped-session date bucket. Local civil days from unix ms via
/// libc localtime — Zig std has no tz database, and Faku does not
/// invent one. `updated_at` 0 or omitted is Today so existing catalogs
/// stay in one bucket. This week is after yesterday and still in the
/// current local week (Monday start). This month is the same local
/// month, older than this week. This year is the same local calendar
/// year, older than this month. Not full Waku grouping: no More /
/// Project sort.
pub const DateBucket = enum(u32) {
    today = 0,
    yesterday = 1,
    this_week = 2,
    this_month = 3,
    this_year = 4,
    older = 5,

    /// English default. Callers that follow Appearance pass `titleFor`.
    pub fn title(self: DateBucket) []const u8 {
        return self.titleFor(i18n.datesFor(.english, ""));
    }

    pub fn titleFor(self: DateBucket, dates: i18n.Dates) []const u8 {
        return switch (self) {
            .today => dates.today,
            .yesterday => dates.yesterday,
            .this_week => dates.this_week,
            .this_month => dates.this_month,
            .this_year => dates.this_year,
            .older => dates.older,
        };
    }
};

/// Process-local civil Y-M-D. Bucket math takes two of these so tests
/// can pin Today / Yesterday / week / month / year / older without the
/// CI host timezone.
pub const CivilDate = struct {
    year: i64,
    month: u8,
    day: u8,

    /// Proleptic Gregorian day ordinal (unix day of this Y-M-D if it
    /// were UTC). Same-calendar weekday math; not a timezone offset.
    pub fn dayOrdinal(self: CivilDate) i64 {
        return daysFromCivil(self.year, self.month, self.day);
    }
};

const ms_per_minute: i64 = 60_000;
const ms_per_hour: i64 = 3_600_000;

const time_t = if (builtin.os.tag == .windows) i64 else std.c.time_t;

/// libc `struct tm`. POSIX (glibc/musl/Darwin) carries `tm_gmtoff` /
/// `tm_zone`; Windows CRT does not.
const Tm = if (builtin.os.tag == .windows)
    extern struct {
        tm_sec: c_int,
        tm_min: c_int,
        tm_hour: c_int,
        tm_mday: c_int,
        tm_mon: c_int,
        tm_year: c_int,
        tm_wday: c_int,
        tm_yday: c_int,
        tm_isdst: c_int,
    }
else
    extern struct {
        tm_sec: c_int,
        tm_min: c_int,
        tm_hour: c_int,
        tm_mday: c_int,
        tm_mon: c_int,
        tm_year: c_int,
        tm_wday: c_int,
        tm_yday: c_int,
        tm_isdst: c_int,
        tm_gmtoff: c_long,
        tm_zone: ?[*:0]const u8,
    };

/// Date bucket from two local civil dates. Future `then` counts as Today.
/// Week starts Monday (`dayOrdinal` 0 is Thursday 1970-01-01, so
/// Monday=0 is `(ordinal + 3) % 7`).
pub fn dateBucketFromCivil(then: CivilDate, now: CivilDate) DateBucket {
    const today = now.dayOrdinal();
    const day = then.dayOrdinal();
    if (day >= today) return .today;
    if (day + 1 == today) return .yesterday;
    const weekday = @mod(today + 3, 7);
    const week_start = today - weekday;
    if (day >= week_start) return .this_week;
    if (then.year == now.year and then.month == now.month) return .this_month;
    if (then.year == now.year) return .this_year;
    return .older;
}

/// Local-civil day delta (`now - then`). Same-day and future are `<= 0`.
pub fn civilDayDelta(then: CivilDate, now: CivilDate) i64 {
    return now.dayOrdinal() - then.dayOrdinal();
}

/// Local civil Y-M-D for a unix-ms timestamp via libc localtime.
pub fn localCivilDate(ms: i64) ?CivilDate {
    const seconds = @divFloor(ms, 1000);
    var timer: time_t = std.math.cast(time_t, seconds) orelse return null;
    var tm: Tm = undefined;
    if (!fillLocalTm(&timer, &tm)) return null;
    const month_i = tm.tm_mon + 1;
    const day_i = tm.tm_mday;
    if (month_i < 1 or month_i > 12) return null;
    if (day_i < 1 or day_i > 31) return null;
    return .{
        .year = @as(i64, tm.tm_year) + 1900,
        .month = @intCast(month_i),
        .day = @intCast(day_i),
    };
}

/// Unix ms for a local civil Y-M-D at local noon via libc `mktime`.
/// Noon avoids DST spring-forward gaps at 02:00. Tests use this to pin
/// local civil dates without depending on the host TZ.
pub fn localMsFromCivil(date: CivilDate) ?i64 {
    const year_c = std.math.cast(c_int, date.year - 1900) orelse return null;
    if (date.month < 1 or date.month > 12) return null;
    if (date.day < 1 or date.day > 31) return null;
    var tm: Tm = undefined;
    tm.tm_sec = 0;
    tm.tm_min = 0;
    tm.tm_hour = 12;
    tm.tm_mday = date.day;
    tm.tm_mon = @as(c_int, date.month) - 1;
    tm.tm_year = year_c;
    tm.tm_wday = 0;
    tm.tm_yday = 0;
    tm.tm_isdst = -1;
    if (builtin.os.tag != .windows) {
        tm.tm_gmtoff = 0;
        tm.tm_zone = null;
    }
    const t = libcMktime(&tm);
    if (t == @as(time_t, -1)) return null;
    const seconds: i64 = t;
    return seconds * 1000;
}

/// Local-day bucket for an ungrouped session. Future timestamps count as Today.
pub fn sessionDateBucket(updated_at: i64, now_ms: i64) DateBucket {
    if (updated_at <= 0 or now_ms <= 0) return .today;
    const now = localCivilDate(now_ms) orelse return .older;
    const then = localCivilDate(updated_at) orelse return .older;
    return dateBucketFromCivil(then, now);
}

/// Short last-activity label from `updated_at` vs wall ms. Missing/0
/// returns null so chrome does not invent a time. Same local-civil-day
/// rules as `sessionDateBucket` for yesterday / `Nd` / date fallback.
/// First-cut 1s chrome tick (`effect_keys.chrome_tick_key`) stamps
/// `now_ms` while idle so labels can advance; still computed from last
/// `now_ms` at paint, not a per-row timer. English default;
/// Appearance callers pass `sessionRelativeTimeFor`.
pub fn sessionRelativeTime(updated_at: i64, now_ms: i64, buf: []u8) ?[]const u8 {
    return sessionRelativeTimeFor(updated_at, now_ms, buf, i18n.datesFor(.english, ""));
}

pub fn sessionRelativeTimeFor(updated_at: i64, now_ms: i64, buf: []u8, dates: i18n.Dates) ?[]const u8 {
    if (updated_at <= 0 or now_ms <= 0) return null;
    const age = now_ms - updated_at;
    if (age < ms_per_minute) return dates.just_now;
    if (age < ms_per_hour) {
        const n = @divTrunc(age, ms_per_minute);
        if (n < 1) return dates.just_now;
        return std.fmt.bufPrint(buf, "{d}m", .{n}) catch null;
    }
    const now = localCivilDate(now_ms) orelse return null;
    const then = localCivilDate(updated_at) orelse return null;
    const days = civilDayDelta(then, now);
    if (days <= 0) {
        const n = @divTrunc(age, ms_per_hour);
        if (n < 1) return dates.just_now;
        return std.fmt.bufPrint(buf, "{d}h", .{n}) catch null;
    }
    if (days == 1) return dates.yesterday;
    if (days < 7) return std.fmt.bufPrint(buf, "{d}d", .{days}) catch null;
    return formatCivilYmd(then, buf);
}

/// ISO `YYYY-MM-DD` from a local civil date (relative-time fallback).
pub fn formatCivilYmd(date: CivilDate, buf: []u8) ?[]const u8 {
    return std.fmt.bufPrint(buf, "{d}-{d:0>2}-{d:0>2}", .{ date.year, date.month, date.day }) catch null;
}

fn fillLocalTm(timer: *time_t, out: *Tm) bool {
    if (builtin.os.tag == .windows) {
        const windows = struct {
            extern "c" fn localtime_s(buf: *Tm, timep: *const time_t) c_int;
        };
        return windows.localtime_s(out, timer) == 0;
    }
    const posix = struct {
        extern "c" fn localtime_r(timep: *const time_t, buf: *Tm) ?*Tm;
    };
    return posix.localtime_r(timer, out) != null;
}

fn libcMktime(tm: *Tm) time_t {
    const c = struct {
        extern "c" fn mktime(tm: *Tm) time_t;
    };
    return c.mktime(tm);
}

/// Howard Hinnant `days_from_civil`. Civil Y-M-D → day ordinal.
fn daysFromCivil(year_in: i64, month: u8, day: u8) i64 {
    var year = year_in;
    const m: i64 = month;
    const d: i64 = day;
    if (m <= 2) year -= 1;
    const era = @divFloor(year, 400);
    const yoe = year - era * 400;
    const mp = if (m > 2) m - 3 else m + 9;
    const doy = @divFloor(153 * mp + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

const testing = std.testing;

fn civil(year: i64, month: u8, day: u8) CivilDate {
    return .{ .year = year, .month = month, .day = day };
}

test "daysFromCivil pins unix day of 1970-01-01 and 2024-01-01" {
    try testing.expectEqual(@as(i64, 0), civil(1970, 1, 1).dayOrdinal());
    try testing.expectEqual(@as(i64, 19723), civil(2024, 1, 1).dayOrdinal());
}

test "dateBucketFromCivil 0-equivalent missing stays on the wrapper; civil today/yesterday/older" {
    const monday = civil(2024, 1, 1);
    try testing.expectEqual(DateBucket.today, dateBucketFromCivil(monday, monday));
    try testing.expectEqual(DateBucket.today, dateBucketFromCivil(civil(2024, 1, 2), monday));
    try testing.expectEqual(DateBucket.yesterday, dateBucketFromCivil(civil(2023, 12, 31), monday));
    try testing.expectEqual(DateBucket.older, dateBucketFromCivil(civil(2023, 12, 30), monday));
    try testing.expectEqual(DateBucket.older, dateBucketFromCivil(civil(2023, 11, 22), monday));
}

test "dateBucketFromCivil This week and This month use Monday week and month" {
    const friday = civil(2024, 1, 19);
    try testing.expectEqual(DateBucket.today, dateBucketFromCivil(friday, friday));
    try testing.expectEqual(DateBucket.yesterday, dateBucketFromCivil(civil(2024, 1, 18), friday));
    try testing.expectEqual(DateBucket.this_week, dateBucketFromCivil(civil(2024, 1, 17), friday));
    try testing.expectEqual(DateBucket.this_week, dateBucketFromCivil(civil(2024, 1, 15), friday));
    try testing.expectEqual(DateBucket.this_month, dateBucketFromCivil(civil(2024, 1, 14), friday));
    try testing.expectEqual(DateBucket.this_month, dateBucketFromCivil(civil(2024, 1, 1), friday));
    try testing.expectEqual(DateBucket.older, dateBucketFromCivil(civil(2023, 12, 31), friday));
    try testing.expectEqual(DateBucket.older, dateBucketFromCivil(civil(2023, 12, 10), friday));
    // Thursday 2024-02-01: week started Monday 2024-01-29, so late January is This week, not This month.
    const feb_first = civil(2024, 2, 1);
    try testing.expectEqual(DateBucket.yesterday, dateBucketFromCivil(civil(2024, 1, 31), feb_first));
    try testing.expectEqual(DateBucket.this_week, dateBucketFromCivil(civil(2024, 1, 29), feb_first));
    try testing.expectEqual(DateBucket.this_year, dateBucketFromCivil(civil(2024, 1, 28), feb_first));
}

test "dateBucketFromCivil This year is same calendar year, older than this month" {
    const friday = civil(2024, 3, 15);
    try testing.expectEqual(DateBucket.today, dateBucketFromCivil(friday, friday));
    try testing.expectEqual(DateBucket.yesterday, dateBucketFromCivil(civil(2024, 3, 14), friday));
    try testing.expectEqual(DateBucket.this_week, dateBucketFromCivil(civil(2024, 3, 13), friday));
    try testing.expectEqual(DateBucket.this_week, dateBucketFromCivil(civil(2024, 3, 11), friday));
    try testing.expectEqual(DateBucket.this_month, dateBucketFromCivil(civil(2024, 3, 10), friday));
    try testing.expectEqual(DateBucket.this_month, dateBucketFromCivil(civil(2024, 3, 1), friday));
    try testing.expectEqual(DateBucket.this_year, dateBucketFromCivil(civil(2024, 2, 29), friday));
    try testing.expectEqual(DateBucket.this_year, dateBucketFromCivil(civil(2024, 1, 1), friday));
    try testing.expectEqual(DateBucket.older, dateBucketFromCivil(civil(2023, 12, 31), friday));
    try testing.expectEqual(DateBucket.older, dateBucketFromCivil(civil(2023, 2, 9), friday));
}

test "civilDayDelta pins today yesterday week and date-fallback span" {
    const now = civil(2024, 1, 1);
    try testing.expectEqual(@as(i64, 0), civilDayDelta(now, now));
    try testing.expectEqual(@as(i64, 1), civilDayDelta(civil(2023, 12, 31), now));
    try testing.expectEqual(@as(i64, 3), civilDayDelta(civil(2023, 12, 29), now));
    try testing.expectEqual(@as(i64, 40), civilDayDelta(civil(2023, 11, 22), now));
}

test "formatCivilYmd is ISO YYYY-MM-DD from the local civil date" {
    var buf: [16]u8 = undefined;
    try testing.expectEqualStrings("2023-11-22", formatCivilYmd(civil(2023, 11, 22), &buf).?);
}

test "sessionDateBucket 0 and missing now are Today without localtime" {
    try testing.expectEqual(DateBucket.today, sessionDateBucket(0, 1));
    try testing.expectEqual(DateBucket.today, sessionDateBucket(1, 0));
    try testing.expectEqual(DateBucket.today, sessionDateBucket(0, 0));
}

test "localCivilDate roundtrips localMsFromCivil noon; wrapper matches civil buckets" {
    const now = civil(2024, 3, 15);
    const yesterday = civil(2024, 3, 14);
    const week = civil(2024, 3, 12);
    const month = civil(2024, 3, 5);
    const year = civil(2024, 2, 24);
    const older = civil(2023, 12, 26);
    const now_ms = localMsFromCivil(now).?;
    try testing.expectEqual(now.year, localCivilDate(now_ms).?.year);
    try testing.expectEqual(now.month, localCivilDate(now_ms).?.month);
    try testing.expectEqual(now.day, localCivilDate(now_ms).?.day);
    try testing.expectEqual(DateBucket.today, sessionDateBucket(now_ms, now_ms));
    try testing.expectEqual(DateBucket.today, sessionDateBucket(now_ms + 1, now_ms));
    try testing.expectEqual(dateBucketFromCivil(yesterday, now), sessionDateBucket(localMsFromCivil(yesterday).?, now_ms));
    try testing.expectEqual(DateBucket.yesterday, sessionDateBucket(localMsFromCivil(yesterday).?, now_ms));
    try testing.expectEqual(DateBucket.this_week, sessionDateBucket(localMsFromCivil(week).?, now_ms));
    try testing.expectEqual(DateBucket.this_month, sessionDateBucket(localMsFromCivil(month).?, now_ms));
    try testing.expectEqual(DateBucket.this_year, sessionDateBucket(localMsFromCivil(year).?, now_ms));
    try testing.expectEqual(DateBucket.older, sessionDateBucket(localMsFromCivil(older).?, now_ms));
}

test "sessionRelativeTime day labels follow local civil dates" {
    const now = civil(2024, 1, 1);
    const now_ms = localMsFromCivil(now).?;
    var buf: [16]u8 = undefined;
    try testing.expectEqualStrings("Yesterday", sessionRelativeTime(localMsFromCivil(civil(2023, 12, 31)).?, now_ms, &buf).?);
    try testing.expectEqualStrings("3d", sessionRelativeTime(localMsFromCivil(civil(2023, 12, 29)).?, now_ms, &buf).?);
    try testing.expectEqualStrings("2023-11-22", sessionRelativeTime(localMsFromCivil(civil(2023, 11, 22)).?, now_ms, &buf).?);
}
