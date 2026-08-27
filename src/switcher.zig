//! Ctrl-Tab session switcher helpers.
//!
//! Snapshot, highlight, cycle, commit, and close live here.
//! Msg routing, Model fields, and `switcher_rows` stay in `main.zig`.
//! Behavior is unchanged from the former `main` switcher helpers.

const main = @import("main.zig");

const Model = main.Model;
const Effects = main.Effects;

/// Runtime-only Ctrl-Tab switcher snapshot. Same cap as Waku's overlay.
pub const switcher_cap: u32 = 10;

fn switcherContains(ids: []const u32, count: u32, id: u32) bool {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (ids[i] == id) return true;
    }
    return false;
}

fn pushSwitcherId(ids: *[switcher_cap]u32, count: *u32, id: u32) void {
    if (id == 0 or count.* >= switcher_cap) return;
    if (switcherContains(ids, count.*, id)) return;
    ids[count.*] = id;
    count.* += 1;
}

fn switcherSessionAllowed(model: *const Model, id: u32, allow_current: bool) bool {
    const session = model.sessionByIdConst(id) orelse return false;
    if (allow_current and id == model.selected) return true;
    return session.hasStarted();
}

fn snapshotSwitcher(model: *Model) void {
    var ids = [_]u32{0} ** switcher_cap;
    var count: u32 = 0;

    if (switcherSessionAllowed(model, model.selected, true)) {
        pushSwitcherId(&ids, &count, model.selected);
    }

    if (model.history_count > 0) {
        var i: i32 = @intCast(model.history_count - 1);
        while (i >= 0) : (i -= 1) {
            const id = model.history_store[@intCast(i)];
            if (switcherSessionAllowed(model, id, false)) {
                pushSwitcherId(&ids, &count, id);
            }
        }
    }

    for (model.session_store[0..model.session_count]) |session| {
        if (session.hasStarted()) {
            pushSwitcherId(&ids, &count, session.id);
        }
    }

    model.switcher_ids = ids;
    model.switcher_count = count;
}

fn initialSwitcherHighlight(count: u32, first_is_current: bool, reverse: bool) u32 {
    if (count == 0) return 0;
    if (first_is_current) {
        if (count == 1) return 0;
        return if (reverse) count - 1 else 1;
    }
    return if (reverse) count - 1 else 0;
}

pub fn closeSwitcher(model: *Model) void {
    model.switcher_open = false;
    model.switcher_count = 0;
    model.switcher_highlight = 0;
    model.switcher_ids = [_]u32{0} ** switcher_cap;
}

pub fn cycleSwitcher(model: *Model, reverse: bool) void {
    if (model.palette_open) model.closePalette();
    if (model.model_picker_open or model.access_picker_open or model.effort_picker_open or model.goal_status_picker_open) {
        model.closeModelPicker();
    }
    if (model.switcher_open) {
        if (model.switcher_count == 0) {
            closeSwitcher(model);
            return;
        }
        if (reverse) {
            model.switcher_highlight = if (model.switcher_highlight == 0)
                model.switcher_count - 1
            else
                model.switcher_highlight - 1;
        } else {
            model.switcher_highlight = (model.switcher_highlight + 1) % model.switcher_count;
        }
        return;
    }

    snapshotSwitcher(model);
    if (model.switcher_count == 0) return;
    const first_is_current = model.switcher_ids[0] == model.selected;
    model.switcher_highlight = initialSwitcherHighlight(model.switcher_count, first_is_current, reverse);
    model.switcher_open = true;
}

fn commitSwitcher(model: *Model, fx: *Effects, id: u32) void {
    if (!model.switcher_open) return;
    closeSwitcher(model);
    if (model.sessionById(id) == null) return;
    model.pushSelectionHistory(id);
    main.applySessionSelection(model, fx, id);
}

pub fn confirmSwitcher(model: *Model, fx: *Effects) void {
    if (!model.switcher_open or model.switcher_count == 0) return;
    if (model.switcher_highlight >= model.switcher_count) return;
    commitSwitcher(model, fx, model.switcher_ids[model.switcher_highlight]);
}

pub fn pickSwitcher(model: *Model, fx: *Effects, id: u32) void {
    if (!model.switcher_open) return;
    if (!switcherContains(&model.switcher_ids, model.switcher_count, id)) return;
    commitSwitcher(model, fx, id);
}
