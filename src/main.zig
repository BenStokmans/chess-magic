const std = @import("std");
const lookup = @import("lookup.zig");
const options = @import("options.zig");

const NodeInfo = struct {
    idx: usize,
    semaphore_ptr: *std.Thread.Semaphore,
};

const shift: u6 = 63 - options.bit_goal + 1;
const entries: u64 = 1 << options.bit_goal;
var done: usize = 0;
var next_square: u32 = 0;

var tests: [64][entries]u64 = undefined;
fn testMagic(square: u32, magic: u64) bool {
    @memset(&tests[square], 0);

    @setEvalBranchQuota(32_768);
    inline for (0..16384) |i| {
        const blockers: u64 = lookup.blocker_masks[square][i];
        const moves: u64 = lookup.all_moves[square][i];

        const magic_key: u32 = @intCast(@mulWithOverflow(blockers, magic)[0] >> shift);
        if (tests[square][magic_key] == 0 or tests[square][magic_key] == moves) {
            tests[square][magic_key] = moves;
        } else {
            return false;
        }
    }
    return true;
}

var g_lehmer64_state: u128 = 1337;

fn lehmer64() u64 {
    g_lehmer64_state = @mulWithOverflow(g_lehmer64_state, 0xDA942042E4DD58B5)[0];
    return @intCast(g_lehmer64_state >> 64);
}

fn generateMagic(square: u32) u64 {
    while (true) {
        const r_magic: u64 = lehmer64();
        if (testMagic(square, r_magic)) {
            return r_magic;
        }
    }
    unreachable;
}

fn nodeWork(info: *NodeInfo) !void {
    while (true) {
        if (@atomicLoad(u32, &next_square, .SeqCst) < 64) {
            const square = @atomicRmw(u32, &next_square, .Add, 1, .SeqCst);
            std.debug.print("Thread {d}: working on square {d}\n", .{ info.idx, square });

            var magic = generateMagic(square);
            std.debug.print("final magic for square: {d} = 0x{x}, bits = {d}\n", .{ square, magic, options.bit_goal });
            _ = @atomicRmw(usize, &done, .Add, 1, .SeqCst);
        } else {
            info.semaphore_ptr.wait();
        }
    }
}

pub fn main() !void {
    g_lehmer64_state = @intCast(std.time.milliTimestamp());
    lookup.populateAllMoves();

    var semaphore = std.Thread.Semaphore{};
    var infos: [options.thread_count]NodeInfo = undefined;
    for (&infos, 0..) |*info, thread_index| {
        info.idx = thread_index;
        info.semaphore_ptr = &semaphore;
        const handle = try std.Thread.spawn(.{}, nodeWork, .{info});
        handle.detach();
    }
    while (next_square != @atomicLoad(usize, &done, .SeqCst)) {}
}
