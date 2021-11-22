const std = @import("std");
const Entry = @import("./main.zig").Entry;
const XHandler = @import("./x.zig").XHandler;
usingnamespace @cImport({
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
    mainloop: *pa_threaded_mainloop,
    context: *pa_context,
    pointers: Pointers,

    fn sink_new_cb(
        context: ?*pa_context,
        info: [*c]const pa_sink_input_info,
        eol: c_int,
        userdata: ?*c_void,
    ) callconv(.C) void {
        if (eol == 1) return;
        var name = std.ArrayList(u8).init(std.heap.c_allocator);
        name.appendSlice(std.mem.span(info.*.name)) catch unreachable;
        const pointers = @ptrCast(*Pointers, @alignCast(@alignOf(*Pointers), userdata));
        pointers.entries.append(.{
            .id = info.*.index,
            .name = name,
            .volume = pa_sw_volume_to_linear(pa_cvolume_avg(&info.*.volume)),
            .channels = info.*.volume.channels,
        }) catch unreachable;
        pointers.x_handler.draw();
    }

    fn sink_change_cb(
        context: ?*pa_context,
        info: [*c]const pa_sink_input_info,
        eol: c_int,
        userdata: ?*c_void,
    ) callconv(.C) void {
        if (eol == 1) return;
        const pointers = @ptrCast(*Pointers, @alignCast(@alignOf(*Pointers), userdata));
        for (pointers.entries.items) |*entry, i| {
            if (entry.id == info.*.index) {
                entry.name.clearRetainingCapacity();
                entry.name.appendSlice(std.mem.span(info.*.name)) catch unreachable;
                entry.volume = pa_sw_volume_to_linear(pa_cvolume_avg(&info.*.volume));
                pointers.x_handler.draw();
                break;
            }
        }
    }

    fn context_subscribe_cb(
        context: ?*pa_context,
        event: pa_subscription_event_type,
        idx: c_uint,
        userdata: ?*c_void,
    ) callconv(.C) void {
        const event_type = @intToEnum(pa_subscription_event_type,
            @enumToInt(event) &
            @enumToInt(pa_subscription_event_type.PA_SUBSCRIPTION_EVENT_TYPE_MASK)
        );
        switch (event_type) {
            .PA_SUBSCRIPTION_EVENT_NEW => {
                pa_operation_unref(pa_context_get_sink_input_info(context, idx, sink_new_cb, userdata));
            },
            .PA_SUBSCRIPTION_EVENT_CHANGE => {
                pa_operation_unref(pa_context_get_sink_input_info(context, idx, sink_change_cb, userdata));
            },
            .PA_SUBSCRIPTION_EVENT_REMOVE => {
                const pointers = @ptrCast(*Pointers, @alignCast(@alignOf(*Pointers), userdata));
                for (pointers.entries.items) |entry, i| {
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

    fn context_state_cb(context: ?*pa_context, userdata: ?*c_void) callconv(.C) void {
        const state = pa_context_get_state(context);
        switch (state) {
            .PA_CONTEXT_UNCONNECTED => {},
            .PA_CONTEXT_CONNECTING => {},
            .PA_CONTEXT_AUTHORIZING => {},
            .PA_CONTEXT_SETTING_NAME => {},
            .PA_CONTEXT_READY => {
                pa_operation_unref(pa_context_get_sink_input_info_list(context, sink_new_cb, userdata));
                pa_context_set_subscribe_callback(context, context_subscribe_cb, userdata);
                pa_operation_unref(pa_context_subscribe(context, .PA_SUBSCRIPTION_MASK_SINK_INPUT, null, null));
            },
            .PA_CONTEXT_FAILED => {
                std.log.err("failed to connect to pulseaudio", .{});
                std.process.exit(1);
            },
            .PA_CONTEXT_TERMINATED => {},
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

        handler.mainloop = pa_threaded_mainloop_new() orelse return error.PulseMainloopNew;
        const api = pa_threaded_mainloop_get_api(handler.mainloop);
        handler.context = pa_context_new(api, context_name) orelse return error.PulseContextNew;

        return handler;
    }

    pub fn start(self: *@This()) !void {
        pa_context_set_state_callback(self.context, context_state_cb, &self.pointers);
        try check(pa_context_connect(self.context, null, .PA_CONTEXT_NOAUTOSPAWN, null), error.PulseContextConnect);
        try check(pa_threaded_mainloop_start(self.mainloop), error.PulseMainloopStart);
    }

    pub fn uninit(self: @This()) void {
        pa_context_disconnect(self.context);
        pa_threaded_mainloop_stop(self.mainloop);
        pa_threaded_mainloop_free(self.mainloop);
    }

    pub fn set_volume(self: @This(), idx: c_uint, volume: f64) void {
        for (self.pointers.entries.items) |*entry| {
            if (entry.id == idx) {
                const actual_volume = pa_sw_volume_from_linear(volume);
                var values = [_]pa_volume_t{0} ** PA_CHANNELS_MAX;
                var i: usize = 0;
                while (i < entry.channels): (i += 1) {
                    values[i] = actual_volume;
                }
                const cvolume = pa_cvolume{
                    .channels = entry.channels,
                    .values = values,
                };
                pa_operation_unref(pa_context_set_sink_input_volume(self.context, idx, &cvolume, null, null));
                return;
            }
        }
    }
};
