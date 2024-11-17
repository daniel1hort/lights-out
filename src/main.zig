const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const State = @import("state.zig");

pub fn main() !void {
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
        //panning
        if (rl.isMouseButtonDown(.mouse_button_right)) {
            const delta = rl.getMouseDelta().scale(1.0 / state.camera.zoom).negate();
            state.camera.target = state.camera.target.add(delta);
        }

        //zooming
        const wheel_move = rl.getMouseWheelMove();
        if (wheel_move != 0) {
            const mouse_pos = rl.getMousePosition();
            state.camera.target = rl.getScreenToWorld2D(mouse_pos, state.camera);
            state.camera.offset = mouse_pos;
            state.camera.zoom *= if (wheel_move < 0) 0.75 else (1.0 / 0.75);
        }

        if (rl.isMouseButtonReleased(.mouse_button_left)) {
            const pos = rl.getScreenToWorld2D(
                rl.getMousePosition(),
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
            if (state.withinBounds(index.x, index.y)) {
                const x: usize = @intFromFloat(index.x);
                const y: usize = @intFromFloat(index.y);
                state.set(
                    x,
                    y,
                    switch (state.get(x, y)) {
                        .none => .off,
                        .off => .on,
                        .on => .none,
                    },
                );
            }
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

            _ = rg.guiButton(
                rl.Rectangle.init(0, 0, 150, 60),
                "Solve",
            );

            _ = rg.guiButton(
                rl.Rectangle.init(0, 70, 150, 60),
                "Play",
            );
        }
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

            if (state.get(x, y) == .on) {
                rl.drawRectangleRec(
                    rl.Rectangle.init(
                        screen_x,
                        screen_y,
                        State.cell_size.x,
                        State.cell_size.y,
                    ),
                    rl.Color.orange,
                );
            }

            if (state.get(x, y) == .off) {
                rl.drawRectangleRec(
                    rl.Rectangle.init(
                        screen_x,
                        screen_y,
                        State.cell_size.x,
                        State.cell_size.y,
                    ),
                    rl.Color.white,
                );
            }

            rl.drawRectangleLinesEx(
                rl.Rectangle.init(
                    screen_x,
                    screen_y,
                    State.cell_size.x,
                    State.cell_size.y,
                ),
                2,
                rl.Color.init(126, 188, 204, 255),
            );
        }
    }
}
