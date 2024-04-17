pub const Mode = enum {
    bishop,
    rook,
};

pub const thread_count: usize = 5;
pub const mode: Mode = Mode.rook;
pub const bit_goal: u6 = 14;
