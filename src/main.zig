const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const State = @import("state.zig");

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

        {
            rl.beginDrawing();
            defer rl.endDrawing();

            rl.clearBackground(rl.Color.init(0, 34, 43, 255));

            {
                state.camera.begin();
                defer state.camera.end();

                drawMap(state);
            }

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
                state.highlights = try solve(&state, allocator);
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

//TODO(dani): cleanup
fn solve(state: *State, allocator: std.mem.Allocator) ![]State.Cell {
    var cells = std.ArrayList(State.Cell).init(allocator);
    defer cells.deinit();
    for (0..State.map_size.y) |y| {
        for (0..State.map_size.x) |x| {
            const cell_state = state.get(x, y);
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
    defer allocator.free(matrix_buffer);
    @memset(matrix_buffer, 0);

    const expected = try allocator.alloc(u1, n);
    defer allocator.free(expected);
    const sol = try allocator.alloc(u1, n);
    defer allocator.free(sol);
    @memset(sol, 0);

    var var_count: usize = n;
    const best_sol = try allocator.alloc(u1, n);
    @memset(best_sol, 1);

    const matrix = try allocator.alloc([]u1, n);
    defer allocator.free(matrix);
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
            if (cell.x - 1 == c.x and cell.y == c.y)
                matrix[i][index] = 1;
        }
        for (cells.items, 0..) |c, i| {
            if (cell.x == c.x and cell.y - 1 == c.y)
                matrix[i][index] = 1;
        }
        for (cells.items, 0..) |c, i| {
            if (cell.x + 1 == c.x and cell.y == c.y)
                matrix[i][index] = 1;
        }
        for (cells.items, 0..) |c, i| {
            if (cell.x == c.x and cell.y + 1 == c.y)
                matrix[i][index] = 1;
        }
    }

    //gaussian elimination
    var h: usize = 0;
    var k: usize = 0;
    while (h < n and k < n) {
        const first_row = blk: {
            for (h..n) |row| {
                if (matrix[row][k] == 1)
                    break :blk row;
            }
            break :blk h;
        };
        if (matrix[first_row][k] == 0) {
            k = k + 1;
        } else {
            const aux1 = matrix[h];
            matrix[h] = matrix[first_row];
            matrix[first_row] = aux1;
            const aux2 = expected[h];
            expected[h] = expected[first_row];
            expected[first_row] = aux2;

            for (h + 1..n) |row| {
                if (matrix[row][k] == 1) {
                    matrix[row][k] = 0;
                    for (k + 1..n) |col| {
                        matrix[row][col] = matrix[row][col] +% matrix[h][col];
                    }
                    expected[row] = expected[row] +% expected[h];
                }
            }

            h = h + 1;
            k = k + 1;
        }
    }

    for (0..n) |row| {
        for (0..n) |col| {
            std.debug.print("{d} ", .{matrix[row][col]});
        }
        std.debug.print("| {d}\n", .{expected[row]});
    }

    const free_vars: usize = blk: {
        var row: usize = n;
        while (row > 0) {
            row -= 1;
            for (row..n) |col| {
                if (matrix[row][col] == 1)
                    break :blk n - row - 1;
            }
        }
        break :blk n;
    };

    //find solutions
    const ways = std.math.pow(usize, 2, free_vars);
    for (0..ways) |way| {
        @memset(sol, 0);
        var shift: usize = 1;
        for (0..free_vars) |index| {
            sol[n - index - 1] = if (way & shift != 0) 1 else 0;
            shift = shift << 1;
        }

        var row: usize = n - free_vars;
        while (row > 0) {
            row -= 1;
            var col = n;
            while (col > row + 1) {
                col -= 1;
                if (matrix[row][col] == 1) {
                    sol[row] +%= sol[col];
                }
            }
            sol[row] +%= expected[row];
        }

        std.debug.print("solution #{d}: ", .{way + 1});
        for (sol, 0..) |value, index| {
            if (value == 1) {
                std.debug.print("{d} ", .{index + 1});
            }
        }
        std.debug.print("\n", .{});

        var count: usize = 0;
        for (sol) |value| {
            count += value;
        }
        if (count < var_count) {
            var_count = count;
            @memcpy(best_sol, sol);
        }
    }

    var cells_to_press = std.ArrayList(State.Cell).init(allocator);
    for (0..n) |index| {
        if (best_sol[index] == 1)
            try cells_to_press.append(cells.items[index]);
    }
    return cells_to_press.toOwnedSlice();
}
