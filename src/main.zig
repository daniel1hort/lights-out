const std = @import("std");
const rl = @import("raylib");
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

        {
            rl.beginDrawing();
            defer rl.endDrawing();

            rl.clearBackground(rl.Color.dark_gray);

            {
                state.camera.begin();
                defer state.camera.end();

                drawMap();
            }

            const length = rl.measureText("Title", 30);
            rl.drawRectangle(0, 0, length + 20, 50, rl.Color.beige);
            rl.drawText(
                "Title",
                10,
                10,
                30,
                rl.Color.black,
            );
        }
    }
}

fn drawMap() void {
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

            rl.drawRectangleLinesEx(
                rl.Rectangle.init(
                    screen_x,
                    screen_y,
                    State.cell_size.x,
                    State.cell_size.y,
                ),
                2,
                rl.Color.light_gray,
            );
        }
    }
}
