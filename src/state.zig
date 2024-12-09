const std = @import("std");
const rl = @import("raylib");

pub const CellState = enum { none, off, on };
pub const Step = enum { design, solve, play };
pub const Cell = struct {
    x: usize,
    y: usize,
    state: CellState,
};
const Self = @This();

pub const screen_size = rl.Vector2.init(1280, 720);
pub const map_size = rl.Vector2.init(20, 20);
pub const cell_size = rl.Vector2.init(40, 40);
pub const ui_panel_bounds = rl.Rectangle.init(
    0,
    0,
    190,
    260,
);

map: [map_size.x * map_size.y]CellState = undefined,
camera: rl.Camera2D = .{
    .offset = .{ .x = 0, .y = 0 },
    .target = .{ .x = 0, .y = 0 },
    .zoom = 1.0,
    .rotation = 0.0,
},
mouse_pos: rl.Vector2 = undefined,
step: Step = .design,
highlights: ?[]Cell = null,

pub fn withinBounds(self: Self, x: f32, y: f32) bool {
    _ = self;
    return x >= 0 and x < map_size.x and y >= 0 and y < map_size.y;
}

pub fn indexAt(self: Self, x: usize, y: usize) usize {
    _ = self;
    return y * @as(usize, @intFromFloat(map_size.x)) + x;
}

pub fn set(self: *Self, x: usize, y: usize, value: CellState) void {
    self.map[self.indexAt(x, y)] = value;
}

pub fn get(self: Self, x: usize, y: usize) CellState {
    return self.map[self.indexAt(x, y)];
}

pub fn toggle(self: *Self, x: usize, y: usize) void {
    switch (self.get(x, y)) {
        .off => self.set(x, y, .on),
        .on => self.set(x, y, .off),
        .none => {},
    }
}

pub fn isHighlighted(self: Self, x: usize, y: usize) bool {
    if (self.highlights) |highlights| {
        for (highlights) |cell| {
            if (cell.x == x and cell.y == y)
                return true;
        }
    } else {
        return false;
    }
    return false;
}

const ParsedMatrix = struct {
    buffer: []u1,
    matrix: [][]u1,
    expected: []u1,
    cells: []Cell,
    allocator: std.mem.Allocator,

    pub fn deinit(self: ParsedMatrix) void {
        self.allocator.free(self.expected);
        self.allocator.free(self.matrix);
        self.allocator.free(self.buffer);
        self.allocator.free(self.cells);
    }
};

pub fn toMatrix(self: Self, allocator: std.mem.Allocator) !ParsedMatrix {
    var cells = std.ArrayList(Cell).init(allocator);
    for (0..map_size.y) |y| {
        for (0..map_size.x) |x| {
            const cell_state = self.get(x, y);
            if (cell_state != .none) {
                try cells.append(.{
                    .state = cell_state,
                    .x = x,
                    .y = y,
                });
            }
        }
    }

    const n = cells.items.len;
    const matrix_buffer = try allocator.alloc(u1, n * (n));
    const expected = try allocator.alloc(u1, n);
    const matrix = try allocator.alloc([]u1, n);

    @memset(matrix_buffer, 0);
    for (0..n) |row| {
        const start = row * n;
        const end = start + n;
        matrix[row] = matrix_buffer[start..end];
    }

    for (cells.items, 0..) |cell, index| {
        expected[index] = switch (cell.state) {
            .off => 1,
            .on => 0,
            .none => 0,
        };
        matrix[index][index] = 1;
        for (cells.items, 0..) |c, i| {
            const fx: f32 = @floatFromInt(cell.x);
            const fy: f32 = @floatFromInt(cell.y);
            if (self.withinBounds(fx - 1, fy) and cell.x - 1 == c.x and cell.y == c.y)
                matrix[i][index] = 1;
            if (self.withinBounds(fx, fy - 1) and cell.x == c.x and cell.y - 1 == c.y)
                matrix[i][index] = 1;
            if (self.withinBounds(fx + 1, fy) and cell.x + 1 == c.x and cell.y == c.y)
                matrix[i][index] = 1;
            if (self.withinBounds(fx, fy + 1) and cell.x == c.x and cell.y + 1 == c.y)
                matrix[i][index] = 1;
        }
    }

    return .{
        .buffer = matrix_buffer,
        .matrix = matrix,
        .expected = expected,
        .cells = try cells.toOwnedSlice(),
        .allocator = allocator,
    };
}
