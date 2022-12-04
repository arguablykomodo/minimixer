const std = @import("std");
const XHandler = @import("x.zig").XHandler;
const PulseHandler = @import("pulse.zig").PulseHandler;

pub const Entry = struct {
    id: c_uint,
    name: std.ArrayList(u8),
    volume: u32,
    channels: u8,
};

var entries = std.ArrayList(Entry).init(std.heap.c_allocator);

pub fn main() anyerror!void {
    var x: XHandler = undefined;
    var pulse: PulseHandler = undefined;

    x = try XHandler.init(&entries, &pulse);
    defer x.uninit();

    pulse = try PulseHandler.init(&entries, &x);
    defer pulse.uninit();

    try pulse.start();
    try x.mainLoop();
}
