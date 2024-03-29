const std = @import("std");
const Entry = @import("main.zig").Entry;
const XHandler = @import("x.zig").XHandler;
const c = @cImport({
    @cInclude("pulse/pulseaudio.h");
});

const context_name = "minimixer";

fn check(status: c_int, comptime err: anyerror) !void {
    if (status < 0) {
        return err;
    }
}

pub const Pointers = struct {
    entries: *std.ArrayList(Entry),
    x_handler: *XHandler,
};

pub const PulseHandler = struct {
    mainloop: *c.pa_threaded_mainloop,
    context: *c.pa_context,
    pointers: Pointers,

    fn newInputCallback(
        _: ?*c.pa_context,
        info: [*c]const c.pa_sink_input_info,
        eol: c_int,
        userdata: ?*anyopaque,
    ) callconv(.C) void {
        if (eol == 1) return;
        var name = std.ArrayList(u8).init(std.heap.c_allocator);
        name.appendSlice(std.mem.span(info.*.name)) catch unreachable;
        const pointers: *Pointers = @alignCast(@ptrCast(userdata));
        pointers.entries.append(.{
            .id = info.*.index,
            .name = name,
            .volume = c.pa_cvolume_avg(&info.*.volume),
            .channels = info.*.volume.channels,
        }) catch unreachable;
        pointers.x_handler.draw();
    }

    fn changedInputCallback(
        _: ?*c.pa_context,
        info: [*c]const c.pa_sink_input_info,
        eol: c_int,
        userdata: ?*anyopaque,
    ) callconv(.C) void {
        if (eol == 1) return;
        const pointers: *Pointers = @alignCast(@ptrCast(userdata));
        for (pointers.entries.items) |*entry| {
            if (entry.id == info.*.index) {
                entry.name.clearRetainingCapacity();
                entry.name.appendSlice(std.mem.span(info.*.name)) catch unreachable;
                entry.volume = c.pa_cvolume_avg(&info.*.volume);
                pointers.x_handler.draw();
                break;
            }
        }
    }

    fn contextSubscribeCallback(
        context: ?*c.pa_context,
        event: c.pa_subscription_event_type,
        idx: c_uint,
        userdata: ?*anyopaque,
    ) callconv(.C) void {
        const event_type = event & c.PA_SUBSCRIPTION_EVENT_TYPE_MASK;
        switch (event_type) {
            c.PA_SUBSCRIPTION_EVENT_NEW => {
                c.pa_operation_unref(c.pa_context_get_sink_input_info(context, idx, newInputCallback, userdata));
            },
            c.PA_SUBSCRIPTION_EVENT_CHANGE => {
                c.pa_operation_unref(c.pa_context_get_sink_input_info(context, idx, changedInputCallback, userdata));
            },
            c.PA_SUBSCRIPTION_EVENT_REMOVE => {
                const pointers: *Pointers = @alignCast(@ptrCast(userdata));
                for (pointers.entries.items, 0..) |entry, i| {
                    if (entry.id == idx) {
                        entry.name.deinit();
                        _ = pointers.entries.orderedRemove(i);
                        pointers.x_handler.draw();
                        break;
                    }
                }
            },
            else => unreachable,
        }
    }

    fn contextStateCallback(context: ?*c.pa_context, userdata: ?*anyopaque) callconv(.C) void {
        const state = c.pa_context_get_state(context);
        switch (state) {
            c.PA_CONTEXT_UNCONNECTED => {},
            c.PA_CONTEXT_CONNECTING => {},
            c.PA_CONTEXT_AUTHORIZING => {},
            c.PA_CONTEXT_SETTING_NAME => {},
            c.PA_CONTEXT_READY => {
                c.pa_operation_unref(c.pa_context_get_sink_input_info_list(context, newInputCallback, userdata));
                c.pa_context_set_subscribe_callback(context, contextSubscribeCallback, userdata);
                c.pa_operation_unref(c.pa_context_subscribe(context, c.PA_SUBSCRIPTION_MASK_SINK_INPUT, null, null));
            },
            c.PA_CONTEXT_FAILED => {
                std.log.err("failed to connect to pulseaudio", .{});
                std.process.exit(1);
            },
            c.PA_CONTEXT_TERMINATED => {},
            else => unreachable,
        }
    }

    pub fn init(entries: *std.ArrayList(Entry), x_handler: *XHandler) !@This() {
        var handler = PulseHandler{
            .mainloop = undefined,
            .context = undefined,
            .pointers = Pointers{
                .entries = entries,
                .x_handler = x_handler,
            },
        };

        handler.mainloop = c.pa_threaded_mainloop_new() orelse return error.PulseMainloopNew;
        const api = c.pa_threaded_mainloop_get_api(handler.mainloop);
        handler.context = c.pa_context_new(api, context_name) orelse return error.PulseContextNew;

        return handler;
    }

    pub fn start(self: *@This()) !void {
        c.pa_context_set_state_callback(self.context, contextStateCallback, &self.pointers);
        try check(c.pa_context_connect(self.context, null, c.PA_CONTEXT_NOAUTOSPAWN, null), error.PulseContextConnect);
        try check(c.pa_threaded_mainloop_start(self.mainloop), error.PulseMainloopStart);
    }

    pub fn uninit(self: @This()) void {
        c.pa_context_disconnect(self.context);
        c.pa_threaded_mainloop_stop(self.mainloop);
        c.pa_threaded_mainloop_free(self.mainloop);
    }

    pub fn setVolume(self: @This(), idx: c_uint, volume: f64) void {
        for (self.pointers.entries.items) |*entry| {
            if (entry.id == idx) {
                var cvolume = c.pa_cvolume{
                    .channels = entry.channels,
                    .values = [_]c.pa_volume_t{0} ** c.PA_CHANNELS_MAX,
                };
                _ = c.pa_cvolume_set(&cvolume, entry.channels, @intFromFloat(volume * @as(f32, @floatFromInt(c.PA_VOLUME_NORM))));
                c.pa_operation_unref(c.pa_context_set_sink_input_volume(self.context, idx, &cvolume, null, null));
                return;
            }
        }
    }
};
