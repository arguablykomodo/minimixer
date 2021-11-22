const std = @import("std");
const XHandler = @import("./x.zig").XHandler;
const PulseHandler = @import("./pulse.zig").PulseHandler;

pub const Entry = struct {
    id: c_uint,
    name: []const u8,
};
var entries = std.ArrayList(Entry).init(std.heap.c_allocator);

pub fn main() anyerror!void {
    const pulse = try PulseHandler.init(&entries);
    defer pulse.uninit();

    var handler = try XHandler.init(&entries);
    defer handler.uninit();
    try handler.main_loop();
}
