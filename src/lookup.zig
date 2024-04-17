const options = @import("options.zig");
const math = @import("std").math;

inline fn inBounds(square: i32) bool {
    return square >= 0 and square < 64;
}

inline fn createRankTable() [64]i32 {
    var rank_table: [64]i32 = undefined;
    for (0..8) |rank| {
        for (0..8) |file| {
            rank_table[rank * 8 + file] = @intCast(rank);
        }
    }

    return rank_table;
}

inline fn createFileTable() [64]i32 {
    var rank_table: [64]i32 = undefined;
    for (0..8) |rank| {
        for (0..8) |file| {
            rank_table[rank * 8 + file] = @intCast(file);
        }
    }

    return rank_table;
}

const rook_directions = [_]i32{ -8, -1, 1, 8 };
const bishop_directions = [_]i32{ -9, -7, 7, 9 };
inline fn rookWrapRule(start_rank: i32, current_rank: i32, abs_direction: u32) bool {
    return start_rank == current_rank or abs_direction != 1;
}
inline fn bishopWrapRule(rank_diff: i32, file_diff: i32) bool {
    return rank_diff == file_diff;
}

// this function has 2956 branches (if rook)
fn createMovementMasks() [64]u64 {
    // we cannot access other comptime vars to create this comptime var
    var rank_table: [64]i32 = createRankTable();
    var file_table: [64]i32 = createFileTable();

    const directions: [4]i32 = if (options.mode == options.Mode.rook) rook_directions else bishop_directions;
    var movement_masks: [64]u64 = undefined;
    for (0..64) |square| {
        var mask: u64 = 0;
        var start_rank: i32 = @intCast(rank_table[square]);
        var start_file: i32 = @intCast(file_table[square]);

        for (0..4) |i| {
            const direction: i32 = directions[i];

            var local_square: i32 = @as(i32, @intCast(square)) + direction;
            if (!inBounds(local_square)) {
                continue;
            }
            var rank_diff: i32 = math.absInt(start_rank - rank_table[@intCast(local_square)]) catch 0;
            var file_diff: i32 = math.absInt(start_file - file_table[@intCast(local_square)]) catch 0;

            const abs_direction: u32 = math.absCast(direction);
            while (if (options.mode == options.Mode.rook)
                rookWrapRule(start_rank, rank_table[@intCast(local_square)], abs_direction)
            else
                bishopWrapRule(rank_diff, file_diff))
            {
                mask |= @as(u64, 1) << @as(u6, @intCast(local_square));
                local_square += direction;
                if (!inBounds(local_square)) {
                    break;
                }
                rank_diff = math.absInt(start_rank - rank_table[@intCast(local_square)]) catch 0;
                file_diff = math.absInt(start_file - file_table[@intCast(local_square)]) catch 0;
            }
        }
        movement_masks[square] = mask;
    }
    return movement_masks;
}

pub var blocker_masks = init: {
    // this shit take too long to figure out what value its actually supposed to be so here...
    @setEvalBranchQuota(20_000_000);
    var initial_value: [64][16384]u64 = undefined;
    var movement_masks = createMovementMasks();

    var moves: [14]u6 = undefined;
    for (0..64) |square| {
        @memset(&initial_value[square], 0);
        var move_index: u32 = 0;
        for (0..64) |i| {
            if (movement_masks[square] >> @as(u6, @intCast(i)) & 1 != 0) {
                moves[move_index] = @as(u6, @intCast(i));
                move_index += 1;
            }
        }

        for (0..16384) |i| {
            for (0..14) |j| {
                initial_value[square][i] |= (i >> @as(u6, @intCast(j)) & 1) << @as(u6, @intCast(moves[j]));
            }
        }
    }
    break :init initial_value;
};

fn legalMoveFromMoveAndBlockerMask(square: usize, blocker_mask: u64, rank_table: [64]i32, file_table: [64]i32) u64 {
    var mask: u64 = 0;

    var start_rank: i32 = rank_table[square];
    var start_file: i32 = file_table[square];

    const directions: [4]i32 = if (options.mode == options.Mode.rook) rook_directions else bishop_directions;
    for (0..4) |i| {
        const direction: i32 = directions[i];
        var local_square: i32 = @as(i32, @intCast(square)) + direction;
        if (!inBounds(local_square)) {
            continue;
        }

        var rank_diff: i32 = math.absInt(start_rank - rank_table[@intCast(local_square)]) catch 0;
        var file_diff: i32 = math.absInt(start_file - file_table[@intCast(local_square)]) catch 0;
        const abs_direction: u32 = math.absCast(direction);

        while (if (options.mode == options.Mode.rook)
            rookWrapRule(start_rank, rank_table[@intCast(local_square)], abs_direction)
        else
            bishopWrapRule(rank_diff, file_diff))
        {
            mask |= @as(u64, 1) << @as(u6, @intCast(local_square));
            if ((blocker_mask & (@as(u64, 1) << @as(u6, @intCast(local_square)))) != 0) {
                break;
            }
            local_square += direction;
            if (!inBounds(local_square)) {
                break;
            }
            rank_diff = math.absInt(start_rank - rank_table[@intCast(local_square)]) catch 0;
            file_diff = math.absInt(start_file - file_table[@intCast(local_square)]) catch 0;
        }
    }

    return mask;
}

pub var all_moves: [64][16384]u64 = undefined;

pub fn populateAllMoves() void {
    var rank_table = createRankTable();
    var file_table = createFileTable();

    for (0..64) |square| {
        for (0..16384) |i| {
            all_moves[square][i] = legalMoveFromMoveAndBlockerMask(square, blocker_masks[square][i], rank_table, file_table);
        }
    }
}
