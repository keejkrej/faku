//! First-cut Files preview regex: a self-contained Zig backtracker.
//! Matches Waku `compile_search` wrapping (`\b(?:pattern)\b` when
//! whole-word is on, ASCII case fold when Aa is off) as closely as a
//! Native zero-config path allows — not the Rust `regex` crate.
//!
//! Supported subset (byte-oriented, ASCII classes):
//! literals, `.` (not newline), `^`/`$` (multiline), `|`,
//! greedy `*` `+` `?` `{n,m}` with n,m ≤ 256, `(…)` captures,
//! `(?:…)`, `[…]` / `[^…]`, `\d\D\w\W\s\S`, `\b\B`, `\n\t\r`,
//! and `\$` / other non-letter escapes as literals.
//!
//! Unsupported (compile as invalid, same as a bad pattern):
//! Unicode properties, lookaheads, backrefs, lazy `*?`, named groups,
//! inline flags, possessive `++`. `$n` / `${n}` / `$$` expand on
//! replace; named `$foo` is not a group reference.

const std = @import("std");

pub const max_ops: usize = 768;
pub const max_nodes: usize = 256;
pub const max_classes: usize = 32;
pub const max_captures: usize = 16;
pub const max_quant: u16 = 256;
const max_frames: usize = 192;
const step_limit: u32 = 2_000_000;
const unset: u32 = std.math.maxInt(u32);

const cap_slots: usize = (max_captures + 1) * 2;

pub const Prog = struct {
    ops: [max_ops]Op = undefined,
    op_count: u16 = 0,
    classes: [max_classes]Class = [_]Class{.{}} ** max_classes,
    class_count: u8 = 0,
    case_sensitive: bool = true,
};

pub const Hit = struct {
    start: usize = 0,
    end: usize = 0,
    caps: [cap_slots]u32 = [_]u32{unset} ** cap_slots,
};

const OpKind = enum(u8) {
    char,
    any,
    class,
    split,
    jump,
    save,
    bol,
    eol,
    word_bound,
    not_word_bound,
    accept,
};

const Op = struct {
    kind: OpKind,
    a: u16 = 0,
    b: u16 = 0,
};

const Class = struct {
    bits: [4]u64 = [_]u64{0} ** 4,
    negated: bool = false,

    fn set(self: *Class, c: u8) void {
        self.bits[c >> 6] |= @as(u64, 1) << @as(u6, @truncate(c));
    }

    fn has(self: Class, c: u8) bool {
        const on = ((self.bits[c >> 6] >> @as(u6, @truncate(c))) & 1) == 1;
        return if (self.negated) !on else on;
    }
};

const NodeKind = enum(u8) {
    epsilon,
    lit,
    any,
    class,
    concat,
    alt,
    repeat,
    capture,
    bol,
    eol,
    word_bound,
    not_word_bound,
};

const Node = struct {
    kind: NodeKind,
    left: u16 = 0,
    right: u16 = 0,
    lo: u16 = 0,
    hi: u16 = 0,
};

const Compiler = struct {
    src: []const u8,
    i: usize = 0,
    case_sensitive: bool,
    nodes: [max_nodes]Node = undefined,
    node_len: u16 = 0,
    classes: [max_classes]Class = [_]Class{.{}} ** max_classes,
    class_len: u8 = 0,
    capture_len: u8 = 0,
    ops: [max_ops]Op = undefined,
    op_len: u16 = 0,

    fn peek(self: *const Compiler) ?u8 {
        if (self.i >= self.src.len) return null;
        return self.src[self.i];
    }

    fn peekAt(self: *const Compiler, off: usize) ?u8 {
        const j = self.i + off;
        if (j >= self.src.len) return null;
        return self.src[j];
    }

    fn take(self: *Compiler) ?u8 {
        const c = self.peek() orelse return null;
        self.i += 1;
        return c;
    }

    fn addNode(self: *Compiler, n: Node) ?u16 {
        if (self.node_len >= max_nodes) return null;
        const id = self.node_len;
        self.nodes[id] = n;
        self.node_len += 1;
        return id;
    }

    fn addClass(self: *Compiler, class: Class) ?u16 {
        if (self.class_len >= max_classes) return null;
        const id = self.class_len;
        self.classes[id] = class;
        self.class_len += 1;
        return id;
    }

    fn emitOp(self: *Compiler, op: Op) ?u16 {
        if (self.op_len >= max_ops) return null;
        const id = self.op_len;
        self.ops[id] = op;
        self.op_len += 1;
        return id;
    }
};

pub fn compile(query: []const u8, case_sensitive: bool, whole_word: bool) ?Prog {
    var c = Compiler{ .src = query, .case_sensitive = case_sensitive };
    const body = parseAlt(&c) orelse return null;
    if (c.i != c.src.len) return null;
    var root = body;
    if (whole_word) {
        const bound_l = c.addNode(.{ .kind = .word_bound }) orelse return null;
        const bound_r = c.addNode(.{ .kind = .word_bound }) orelse return null;
        const mid = c.addNode(.{ .kind = .concat, .left = bound_l, .right = body }) orelse return null;
        root = c.addNode(.{ .kind = .concat, .left = mid, .right = bound_r }) orelse return null;
    }
    const captured = c.addNode(.{ .kind = .capture, .left = root, .lo = 0 }) orelse return null;
    if (!emit(&c, captured)) return null;
    _ = c.emitOp(.{ .kind = .accept }) orelse return null;

    var prog = Prog{
        .op_count = c.op_len,
        .class_count = c.class_len,
        .case_sensitive = case_sensitive,
    };
    @memcpy(prog.ops[0..c.op_len], c.ops[0..c.op_len]);
    prog.classes = c.classes;
    return prog;
}

fn parseAlt(c: *Compiler) ?u16 {
    var left = parseConcat(c) orelse return null;
    while (c.peek() == '|') {
        _ = c.take();
        const right = parseConcat(c) orelse return null;
        left = c.addNode(.{ .kind = .alt, .left = left, .right = right }) orelse return null;
    }
    return left;
}

fn parseConcat(c: *Compiler) ?u16 {
    if (!startsAtom(c.peek())) {
        const ch = c.peek();
        if (ch == null or ch == '|' or ch == ')') {
            return c.addNode(.{ .kind = .epsilon });
        }
        return null;
    }
    const first = parseRepeat(c) orelse return null;
    var left = first;
    while (startsAtom(c.peek())) {
        const next = parseRepeat(c) orelse return null;
        left = c.addNode(.{ .kind = .concat, .left = left, .right = next }) orelse return null;
    }
    return left;
}

fn startsAtom(c: ?u8) bool {
    const ch = c orelse return false;
    return switch (ch) {
        '|', ')' => false,
        '*', '+', '?', '{' => false,
        else => true,
    };
}

fn parseRepeat(c: *Compiler) ?u16 {
    if (isQuantifier(c.peek())) return null;
    const atom = parseAtom(c) orelse return null;
    const q = parseQuantifier(c) orelse return atom;
    if (isQuantifier(c.peek())) return null;
    return c.addNode(.{
        .kind = .repeat,
        .left = atom,
        .lo = q.min,
        .hi = q.max,
    });
}

fn isQuantifier(c: ?u8) bool {
    const ch = c orelse return false;
    return ch == '*' or ch == '+' or ch == '?' or ch == '{';
}

const Quant = struct { min: u16, max: u16 };

fn parseQuantifier(c: *Compiler) ?Quant {
    const ch = c.peek() orelse return null;
    switch (ch) {
        '*' => {
            _ = c.take();
            return .{ .min = 0, .max = std.math.maxInt(u16) };
        },
        '+' => {
            _ = c.take();
            return .{ .min = 1, .max = std.math.maxInt(u16) };
        },
        '?' => {
            _ = c.take();
            return .{ .min = 0, .max = 1 };
        },
        '{' => return parseBraceQuant(c),
        else => return null,
    }
}

fn parseBraceQuant(c: *Compiler) ?Quant {
    const saved = c.i;
    _ = c.take();
    const min = parseDecimal(c) orelse {
        c.i = saved;
        return null;
    };
    if (min > max_quant) return null;
    var max = min;
    if (c.peek() == ',') {
        _ = c.take();
        if (c.peek() == '}') {
            max = std.math.maxInt(u16);
        } else {
            max = parseDecimal(c) orelse return null;
            if (max > max_quant or max < min) return null;
        }
    }
    if (c.take() != '}') return null;
    return .{ .min = min, .max = max };
}

fn parseDecimal(c: *Compiler) ?u16 {
    const start = c.i;
    var n: u32 = 0;
    var any = false;
    while (c.peek()) |ch| {
        if (!std.ascii.isDigit(ch)) break;
        _ = c.take();
        any = true;
        n = n * 10 + (ch - '0');
        if (n > max_quant) return null;
    }
    if (!any or start == c.i) return null;
    return @intCast(n);
}

fn parseAtom(c: *Compiler) ?u16 {
    const ch = c.peek() orelse return null;
    switch (ch) {
        '.' => {
            _ = c.take();
            return c.addNode(.{ .kind = .any });
        },
        '^' => {
            _ = c.take();
            return c.addNode(.{ .kind = .bol });
        },
        '$' => {
            _ = c.take();
            return c.addNode(.{ .kind = .eol });
        },
        '(' => return parseGroup(c),
        '[' => {
            const class_id = parseClass(c) orelse return null;
            return c.addNode(.{ .kind = .class, .lo = class_id });
        },
        '\\' => return parseEscapeAtom(c),
        '|', ')' => return null,
        '*', '+', '?', '{' => return null,
        else => {
            _ = c.take();
            return c.addNode(.{ .kind = .lit, .lo = ch });
        },
    }
}

fn parseGroup(c: *Compiler) ?u16 {
    _ = c.take();
    var capturing = true;
    if (c.peek() == '?' ) {
        if (c.peekAt(1) == ':') {
            _ = c.take();
            _ = c.take();
            capturing = false;
        } else {
            return null;
        }
    }
    var cap_id: u16 = 0;
    if (capturing) {
        if (c.capture_len >= max_captures) return null;
        c.capture_len += 1;
        cap_id = c.capture_len;
    }
    const inner = parseAlt(c) orelse return null;
    if (c.take() != ')') return null;
    if (!capturing) return inner;
    return c.addNode(.{ .kind = .capture, .left = inner, .lo = cap_id });
}

fn parseEscapeAtom(c: *Compiler) ?u16 {
    _ = c.take();
    const ch = c.take() orelse return null;
    switch (ch) {
        'd', 'D', 'w', 'W', 's', 'S' => {
            var class = Class{};
            fillShorthand(&class, ch);
            const id = c.addClass(class) orelse return null;
            return c.addNode(.{ .kind = .class, .lo = id });
        },
        'b' => return c.addNode(.{ .kind = .word_bound }),
        'B' => return c.addNode(.{ .kind = .not_word_bound }),
        'n' => return c.addNode(.{ .kind = .lit, .lo = '\n' }),
        't' => return c.addNode(.{ .kind = .lit, .lo = '\t' }),
        'r' => return c.addNode(.{ .kind = .lit, .lo = '\r' }),
        else => {
            if (std.ascii.isAlphabetic(ch) or std.ascii.isDigit(ch)) return null;
            return c.addNode(.{ .kind = .lit, .lo = ch });
        },
    }
}

fn parseClass(c: *Compiler) ?u16 {
    _ = c.take();
    var class = Class{};
    if (c.peek() == '^') {
        _ = c.take();
        class.negated = true;
    }
    var got = false;
    if (c.peek() == ']') {
        _ = c.take();
        addClassByte(&class, ']', c.case_sensitive);
        got = true;
    }
    while (c.peek()) |ch| {
        if (ch == ']') break;
        const start_byte = parseClassItem(c, &class) orelse return null;
        got = true;
        if (c.peek() == '-') {
            if (c.peekAt(1) != ']' and c.peekAt(1) != null) {
                _ = c.take();
                const end_byte = parseClassItem(c, &class) orelse return null;
                if (end_byte < start_byte) return null;
                var b = start_byte;
                while (b <= end_byte) : (b += 1) {
                    addClassByte(&class, b, c.case_sensitive);
                    if (b == 255) break;
                }
            }
        }
    }
    if (c.take() != ']' or !got) return null;
    const id = c.addClass(class) orelse return null;
    return id;
}

fn parseClassItem(c: *Compiler, class: *Class) ?u8 {
    const ch = c.take() orelse return null;
    if (ch != '\\') {
        addClassByte(class, ch, c.case_sensitive);
        return ch;
    }
    const esc = c.take() orelse return null;
    switch (esc) {
        'd', 'D', 'w', 'W', 's', 'S' => {
            fillShorthand(class, esc);
            return 0;
        },
        'n' => {
            addClassByte(class, '\n', true);
            return '\n';
        },
        't' => {
            addClassByte(class, '\t', true);
            return '\t';
        },
        'r' => {
            addClassByte(class, '\r', true);
            return '\r';
        },
        else => {
            if (std.ascii.isAlphabetic(esc)) return null;
            addClassByte(class, esc, c.case_sensitive);
            return esc;
        },
    }
}

fn fillShorthand(class: *Class, kind: u8) void {
    switch (kind) {
        'd' => {
            var d: u8 = '0';
            while (d <= '9') : (d += 1) class.set(d);
        },
        'D' => {
            var i: u16 = 0;
            while (i < 256) : (i += 1) {
                const b: u8 = @intCast(i);
                if (!std.ascii.isDigit(b)) class.set(b);
            }
        },
        'w' => {
            var i: u16 = 0;
            while (i < 256) : (i += 1) {
                const b: u8 = @intCast(i);
                if (isWord(b)) class.set(b);
            }
        },
        'W' => {
            var i: u16 = 0;
            while (i < 256) : (i += 1) {
                const b: u8 = @intCast(i);
                if (!isWord(b)) class.set(b);
            }
        },
        's' => {
            class.set(' ');
            class.set('\t');
            class.set('\n');
            class.set('\r');
            class.set(0x0b);
            class.set(0x0c);
        },
        'S' => {
            var i: u16 = 0;
            while (i < 256) : (i += 1) {
                const b: u8 = @intCast(i);
                if (!isSpace(b)) class.set(b);
            }
        },
        else => {},
    }
}

fn addClassByte(class: *Class, c: u8, case_sensitive: bool) void {
    class.set(c);
    if (case_sensitive) return;
    if (std.ascii.isUpper(c)) class.set(std.ascii.toLower(c));
    if (std.ascii.isLower(c)) class.set(std.ascii.toUpper(c));
}

fn isWord(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0b or c == 0x0c;
}

fn emit(c: *Compiler, node_i: u16) bool {
    const n = c.nodes[node_i];
    switch (n.kind) {
        .epsilon => return true,
        .lit => return c.emitOp(.{ .kind = .char, .a = n.lo }) != null,
        .any => return c.emitOp(.{ .kind = .any }) != null,
        .class => return c.emitOp(.{ .kind = .class, .a = n.lo }) != null,
        .bol => return c.emitOp(.{ .kind = .bol }) != null,
        .eol => return c.emitOp(.{ .kind = .eol }) != null,
        .word_bound => return c.emitOp(.{ .kind = .word_bound }) != null,
        .not_word_bound => return c.emitOp(.{ .kind = .not_word_bound }) != null,
        .concat => return emit(c, n.left) and emit(c, n.right),
        .capture => {
            if (c.emitOp(.{ .kind = .save, .a = n.lo * 2 }) == null) return false;
            if (!emit(c, n.left)) return false;
            return c.emitOp(.{ .kind = .save, .a = n.lo * 2 + 1 }) != null;
        },
        .alt => {
            const split_at = c.emitOp(.{ .kind = .split }) orelse return false;
            const left_pc = c.op_len;
            if (!emit(c, n.left)) return false;
            const jmp_at = c.emitOp(.{ .kind = .jump }) orelse return false;
            const right_pc = c.op_len;
            if (!emit(c, n.right)) return false;
            const after = c.op_len;
            c.ops[split_at].a = left_pc;
            c.ops[split_at].b = right_pc;
            c.ops[jmp_at].a = after;
            return true;
        },
        .repeat => return emitRepeat(c, n),
    }
}

fn emitRepeat(c: *Compiler, n: Node) bool {
    const min = n.lo;
    var k: u16 = 0;
    while (k < min) : (k += 1) {
        if (!emit(c, n.left)) return false;
    }
    if (n.hi == std.math.maxInt(u16)) {
        const split_at = c.emitOp(.{ .kind = .split }) orelse return false;
        const body = c.op_len;
        if (!emit(c, n.left)) return false;
        if (c.emitOp(.{ .kind = .jump, .a = split_at }) == null) return false;
        const after = c.op_len;
        c.ops[split_at].a = body;
        c.ops[split_at].b = after;
        return true;
    }
    const extra = n.hi - min;
    var e: u16 = 0;
    while (e < extra) : (e += 1) {
        const split_at = c.emitOp(.{ .kind = .split }) orelse return false;
        const body = c.op_len;
        if (!emit(c, n.left)) return false;
        const after = c.op_len;
        c.ops[split_at].a = body;
        c.ops[split_at].b = after;
    }
    return true;
}

const Frame = struct {
    pc: u16,
    pos: u32,
    caps: [cap_slots]u32,
};

fn charsEq(a: u8, b: u8, case_sensitive: bool) bool {
    if (case_sensitive) return a == b;
    return std.ascii.toLower(a) == std.ascii.toLower(b);
}

fn atBol(hay: []const u8, pos: usize) bool {
    return pos == 0 or hay[pos - 1] == '\n';
}

fn atEol(hay: []const u8, pos: usize) bool {
    return pos == hay.len or hay[pos] == '\n';
}

fn atWordBound(hay: []const u8, pos: usize) bool {
    const prev = if (pos == 0) false else isWord(hay[pos - 1]);
    const next = if (pos >= hay.len) false else isWord(hay[pos]);
    return prev != next;
}

fn execAt(prog: *const Prog, hay: []const u8, from: usize, seen_gen: []u32, seen_pos: []u32, gen: u32) ?Hit {
    var stack: [max_frames]Frame = undefined;
    var sp: usize = 0;
    var pc: u16 = 0;
    var pos: u32 = @intCast(from);
    var caps: [cap_slots]u32 = [_]u32{unset} ** cap_slots;
    var steps: u32 = 0;
    const ops = prog.ops[0..prog.op_count];

    backtrack: while (true) {
        steps += 1;
        if (steps > step_limit) return null;
        if (pc >= ops.len) {
            if (sp == 0) return null;
            sp -= 1;
            pc = stack[sp].pc;
            pos = stack[sp].pos;
            caps = stack[sp].caps;
            continue;
        }
        if (seen_gen[pc] == gen and seen_pos[pc] == pos) {
            if (sp == 0) return null;
            sp -= 1;
            pc = stack[sp].pc;
            pos = stack[sp].pos;
            caps = stack[sp].caps;
            continue;
        }
        seen_gen[pc] = gen;
        seen_pos[pc] = pos;

        const op = ops[pc];
        switch (op.kind) {
            .char => {
                if (pos >= hay.len or !charsEq(hay[pos], @intCast(op.a), prog.case_sensitive)) {
                    if (sp == 0) return null;
                    sp -= 1;
                    pc = stack[sp].pc;
                    pos = stack[sp].pos;
                    caps = stack[sp].caps;
                    continue :backtrack;
                }
                pos += 1;
                pc += 1;
            },
            .any => {
                if (pos >= hay.len or hay[pos] == '\n') {
                    if (sp == 0) return null;
                    sp -= 1;
                    pc = stack[sp].pc;
                    pos = stack[sp].pos;
                    caps = stack[sp].caps;
                    continue :backtrack;
                }
                pos += 1;
                pc += 1;
            },
            .class => {
                if (pos >= hay.len or !prog.classes[op.a].has(hay[pos])) {
                    if (sp == 0) return null;
                    sp -= 1;
                    pc = stack[sp].pc;
                    pos = stack[sp].pos;
                    caps = stack[sp].caps;
                    continue :backtrack;
                }
                pos += 1;
                pc += 1;
            },
            .split => {
                if (sp >= max_frames) return null;
                stack[sp] = .{ .pc = op.b, .pos = pos, .caps = caps };
                sp += 1;
                pc = op.a;
            },
            .jump => pc = op.a,
            .save => {
                caps[op.a] = pos;
                pc += 1;
            },
            .bol => {
                if (!atBol(hay, pos)) {
                    if (sp == 0) return null;
                    sp -= 1;
                    pc = stack[sp].pc;
                    pos = stack[sp].pos;
                    caps = stack[sp].caps;
                    continue :backtrack;
                }
                pc += 1;
            },
            .eol => {
                if (!atEol(hay, pos)) {
                    if (sp == 0) return null;
                    sp -= 1;
                    pc = stack[sp].pc;
                    pos = stack[sp].pos;
                    caps = stack[sp].caps;
                    continue :backtrack;
                }
                pc += 1;
            },
            .word_bound => {
                if (!atWordBound(hay, pos)) {
                    if (sp == 0) return null;
                    sp -= 1;
                    pc = stack[sp].pc;
                    pos = stack[sp].pos;
                    caps = stack[sp].caps;
                    continue :backtrack;
                }
                pc += 1;
            },
            .not_word_bound => {
                if (atWordBound(hay, pos)) {
                    if (sp == 0) return null;
                    sp -= 1;
                    pc = stack[sp].pc;
                    pos = stack[sp].pos;
                    caps = stack[sp].caps;
                    continue :backtrack;
                }
                pc += 1;
            },
            .accept => {
                var hit = Hit{ .start = from, .end = pos, .caps = caps };
                if (caps[0] != unset) hit.start = caps[0];
                if (caps[1] != unset) hit.end = caps[1];
                return hit;
            },
        }
    }
}

/// Leftmost non-empty match with start ≥ `from`. Zero-width hits are skipped.
pub fn find(prog: *const Prog, hay: []const u8, from: usize) ?Hit {
    var seen_gen: [max_ops]u32 = [_]u32{0} ** max_ops;
    var seen_pos: [max_ops]u32 = undefined;
    var gen: u32 = 0;
    var i = from;
    while (i <= hay.len) {
        gen += 1;
        if (gen == 0) {
            @memset(seen_gen[0..], 0);
            gen = 1;
        }
        if (execAt(prog, hay, i, seen_gen[0..], seen_pos[0..], gen)) |hit| {
            if (hit.end > hit.start) return hit;
        }
        if (i == hay.len) break;
        i += 1;
    }
    return null;
}

/// Match anchored at `from` (Waku `captures_at`). Null when it misses
/// or the whole match is empty.
pub fn exec(prog: *const Prog, hay: []const u8, from: usize) ?Hit {
    var seen_gen: [max_ops]u32 = [_]u32{0} ** max_ops;
    var seen_pos: [max_ops]u32 = undefined;
    return execAt(prog, hay, from, seen_gen[0..], seen_pos[0..], 1);
}

fn groupSlice(hay: []const u8, hit: Hit, group: usize) []const u8 {
    if (group == 0) {
        if (hit.end > hay.len or hit.start > hit.end) return &.{};
        return hay[hit.start..hit.end];
    }
    const start_slot = group * 2;
    const end_slot = start_slot + 1;
    if (end_slot >= cap_slots) return &.{};
    const a = hit.caps[start_slot];
    const b = hit.caps[end_slot];
    if (a == unset or b == unset or b > hay.len or a > b) return &.{};
    return hay[a..b];
}

/// `$n` / `${n}` / `$$` expand. Unknown groups become empty. A bare
/// `$` that is not a reference is copied through.
pub fn expand(template: []const u8, hay: []const u8, hit: Hit, dest: []u8) ?[]u8 {
    var out: usize = 0;
    var i: usize = 0;
    while (i < template.len) {
        if (template[i] != '$') {
            if (out >= dest.len) return null;
            dest[out] = template[i];
            out += 1;
            i += 1;
            continue;
        }
        i += 1;
        if (i >= template.len) {
            if (out >= dest.len) return null;
            dest[out] = '$';
            out += 1;
            break;
        }
        if (template[i] == '$') {
            if (out >= dest.len) return null;
            dest[out] = '$';
            out += 1;
            i += 1;
            continue;
        }
        var group: usize = 0;
        if (template[i] == '{') {
            i += 1;
            const num_start = i;
            while (i < template.len and std.ascii.isDigit(template[i])) i += 1;
            if (i == num_start or i >= template.len or template[i] != '}') {
                if (out >= dest.len) return null;
                dest[out] = '$';
                out += 1;
                i = num_start - 1;
                if (template[i] == '{') {}
                continue;
            }
            group = parseGroupNum(template[num_start..i]) orelse 0;
            i += 1;
        } else if (std.ascii.isDigit(template[i])) {
            const num_start = i;
            while (i < template.len and std.ascii.isDigit(template[i])) i += 1;
            group = parseGroupNum(template[num_start..i]) orelse 0;
        } else {
            if (out >= dest.len) return null;
            dest[out] = '$';
            out += 1;
            continue;
        }
        const slice = groupSlice(hay, hit, group);
        if (out + slice.len > dest.len) return null;
        @memcpy(dest[out .. out + slice.len], slice);
        out += slice.len;
    }
    return dest[0..out];
}

fn parseGroupNum(s: []const u8) ?usize {
    if (s.len == 0) return null;
    var n: usize = 0;
    for (s) |ch| {
        n = n * 10 + (ch - '0');
        if (n > max_captures) return n;
    }
    return n;
}

test "compile rejects unclosed groups and unknown flags" {
    try std.testing.expect(compile("(unclosed", false, false) == null);
    try std.testing.expect(compile("a(", false, false) == null);
    try std.testing.expect(compile("(?i)a", false, false) == null);
    try std.testing.expect(compile("a*?b", false, false) == null);
    try std.testing.expect(compile("\\1", false, false) == null);
    try std.testing.expect(compile("foo", false, false) != null);
}
