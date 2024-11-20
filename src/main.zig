const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const State = @import("state.zig");
const math = @import("math.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var state: State = .{};
    @memset(&state.map, .none);

    rl.initWindow(
        State.screen_size.x,
        State.screen_size.y,
        "Lights Out",
    );
    defer rl.closeWindow();

    rl.setTargetFPS(60);
    rg.guiLoadStyle("style_cyber.rgs");
    rg.guiSetStyle(
        rg.GuiControl.default,
        @intFromEnum(rg.GuiDefaultProperty.text_size),
        40,
    );

    while (!rl.windowShouldClose()) {
        state.mouse_pos = rl.getMousePosition();
        const wheel_move = rl.getMouseWheelMove();

        //panning
        if (rl.isMouseButtonDown(.mouse_button_right)) {
            const delta = rl.getMouseDelta().scale(1.0 / state.camera.zoom).negate();
            state.camera.target = state.camera.target.add(delta);
        }

        //zooming
        if (wheel_move != 0) {
            state.camera.target = rl.getScreenToWorld2D(state.mouse_pos, state.camera);
            state.camera.offset = state.mouse_pos;
            state.camera.zoom *= if (wheel_move < 0) 0.75 else (1.0 / 0.75);
        }

        if (rl.isMouseButtonReleased(.mouse_button_left)) {
            onGridClick(&state);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.init(0, 34, 43, 255));

        {
            state.camera.begin();
            defer state.camera.end();

            drawMap(state);
        }

        try drawButtonsPanel(&state, allocator);
    }

    if (state.highlights) |highlights| {
        allocator.free(highlights);
    }
}

fn drawMap(state: State) void {
    const total_size = rl.Vector2.init(
        State.map_size.x * State.cell_size.x,
        State.map_size.y * State.cell_size.y,
    );
    const origin = rl.Vector2.init(
        (State.screen_size.x - total_size.x) * 0.5,
        (State.screen_size.y - total_size.y) * 0.5,
    );

    for (0..State.map_size.x) |x| {
        for (0..State.map_size.y) |y| {
            const screen_x = origin.x + @as(f32, (@floatFromInt(x))) * State.cell_size.x;
            const screen_y = origin.y + @as(f32, (@floatFromInt(y))) * State.cell_size.y;

            const bounds = rl.Rectangle.init(
                screen_x,
                screen_y,
                State.cell_size.x,
                State.cell_size.y,
            );
            const color = switch (state.get(x, y)) {
                .none => rl.Color.blank,
                .off => rl.Color.white,
                .on => rl.Color.orange,
            };

            rl.drawRectangleRec(bounds, color);
            rl.drawRectangleLinesEx(
                bounds,
                2,
                rl.Color.init(126, 188, 204, 255),
            );

            if (state.isHighlighted(x, y)) {
                rl.drawCircle(
                    @intFromFloat(screen_x + State.cell_size.x * 0.5),
                    @intFromFloat(screen_y + State.cell_size.y * 0.5),
                    5,
                    rl.Color.red,
                );
            }
        }
    }
}

fn drawButtonsPanel(state: *State, allocator: std.mem.Allocator) !void {
    _ = rg.guiPanel(
        State.ui_panel_bounds,
        null,
    );

    if (rg.guiButton(
        rl.Rectangle.init(20, 20, 150, 60),
        "Solve",
    ) != 0) {
        state.step = .solve;
        if (state.highlights) |highlights|
            allocator.free(highlights);
        state.highlights = try solve(state, allocator);
        state.step = .play;
    }

    const play_button_text = switch (state.step) {
        .design => "Play",
        .play => "Stop",
        .solve => "Waiting",
    };
    if (rg.guiButton(
        rl.Rectangle.init(20, 100, 150, 60),
        play_button_text,
    ) != 0) {
        switch (state.step) {
            .design => state.step = .play,
            .play => state.step = .design,
            .solve => {},
        }
    }

    if (rg.guiButton(
        rl.Rectangle.init(20, 180, 150, 60),
        "Clear",
    ) != 0) {
        @memset(&state.map, .none);
        if (state.highlights) |highlights| {
            allocator.free(highlights);
            state.highlights = null;
        }
        state.step = .design;
    }
}

fn onGridClick(state: *State) void {
    const pos = rl.getScreenToWorld2D(
        state.mouse_pos,
        state.camera,
    );

    const total_size = rl.Vector2.init(
        State.map_size.x * State.cell_size.x,
        State.map_size.y * State.cell_size.y,
    );
    const origin = rl.Vector2.init(
        (State.screen_size.x - total_size.x) * 0.5,
        (State.screen_size.y - total_size.y) * 0.5,
    );

    const index = pos.subtract(origin).scale(1.0 / State.cell_size.x);
    const over_panel = rl.checkCollisionPointRec(state.mouse_pos, State.ui_panel_bounds);
    if (state.withinBounds(index.x, index.y) and !over_panel) {
        const x: usize = @intFromFloat(index.x);
        const y: usize = @intFromFloat(index.y);
        switch (state.step) {
            .design => {
                const next_state: State.CellState = switch (state.get(x, y)) {
                    .none => .off,
                    .off => .on,
                    .on => .none,
                };
                state.set(x, y, next_state);
            },
            .play => {
                if (state.get(x, y) != .none) {
                    state.toggle(x, y);
                    state.toggle(x - 1, y);
                    state.toggle(x, y - 1);
                    state.toggle(x + 1, y);
                    state.toggle(x, y + 1);
                }
            },
            .solve => {},
        }
    }
}

fn solve(state: *State, allocator: std.mem.Allocator) ![]State.Cell {
    const parsed = try state.toMatrix(allocator);
    defer parsed.deinit();

    const n = parsed.expected.len;
    const cells = parsed.cells;
    const matrix = parsed.matrix;
    const expected = parsed.expected;

    math.gaussianElimination(matrix, expected);

    for (0..n) |row| {
        for (0..n) |col| {
            std.debug.print("{d} ", .{matrix[row][col]});
        }
        std.debug.print("| {d}\n", .{expected[row]});
    }

    const best_sol = try math.solveUpperTriangular(
        matrix,
        expected,
        allocator,
        .{ .print_solutions = true },
    );
    defer allocator.free(best_sol);

    var cells_to_press = std.ArrayList(State.Cell).init(allocator);
    for (0..n) |index| {
        if (best_sol[index] == 1)
            try cells_to_press.append(cells[index]);
    }
    return cells_to_press.toOwnedSlice();
}
