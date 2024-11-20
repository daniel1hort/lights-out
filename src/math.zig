const std = @import("std");

pub fn gaussianElimination(
    matrix: [][]u1,
    expected: []u1,
) void {
    const n = expected.len;
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
            swap(&matrix[h], &matrix[first_row]);
            swap(&expected[h], &expected[first_row]);

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
}

pub fn solveUpperTriangular(
    matrix: [][]u1,
    expected: []u1,
    allocator: std.mem.Allocator,
    comptime options: struct { print_solutions: bool },
) ![]u1 {
    const n = expected.len;
    const free_vars = countFreeVars(matrix, n);

    var var_count: usize = n;
    const best_sol = try allocator.alloc(u1, n);
    @memset(best_sol, 1);

    const sol = try allocator.alloc(u1, n);
    defer allocator.free(sol);
    @memset(sol, 0);

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

        if (options.print_solutions) {
            std.debug.print("solution #{d}: ", .{way + 1});
            for (sol, 0..) |value, index| {
                if (value == 1) {
                    std.debug.print("{d} ", .{index + 1});
                }
            }
            std.debug.print("\n", .{});
        }

        var count: usize = 0;
        for (sol) |value| {
            count += value;
        }
        if (count < var_count) {
            var_count = count;
            @memcpy(best_sol, sol);
        }
    }

    return best_sol;
}

fn countFreeVars(matrix: []const []const u1, n: usize) usize {
    var row: usize = n;
    while (row > 0) {
        row -= 1;
        for (row..n) |col| {
            if (matrix[row][col] == 1)
                return n - row - 1;
        }
    }
    return n;
}

fn swap(a: anytype, b: @TypeOf(a)) void {
    const aux = a.*;
    a.* = b.*;
    b.* = aux;
}
