const std = @import("std");
const rl = @import("raylib");

pub const CellState = enum { none, off, on };
const Self = @This();

pub const screen_size = rl.Vector2.init(1280, 720);
pub const map_size = rl.Vector2.init(20, 20);
pub const cell_size = rl.Vector2.init(40, 40);

map: [map_size.x * map_size.y]CellState = undefined,

camera: rl.Camera2D = .{
    .offset = .{ .x = 0, .y = 0 },
    .target = .{ .x = 0, .y = 0 },
    .zoom = 1.0,
    .rotation = 0.0,
},
