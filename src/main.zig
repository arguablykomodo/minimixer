const std = @import("std");
const XHandler = @import("./x.zig").XHandler;
const PulseHandler = @import("./pulse.zig").PulseHandler;

pub const Entry = struct {
    id: c_uint,
    name: std.ArrayList(u8),
};
var entries = std.ArrayList(Entry).init(std.heap.c_allocator);

pub fn main() anyerror!void {
    var x = try XHandler.init(&entries);
    defer x.uninit();

    var pulse = try PulseHandler.init(&entries, &x);
    defer pulse.uninit();

    try pulse.start();
    try x.main_loop();
}
