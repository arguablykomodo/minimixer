const std = @import("std");
const Entry = @import("./main.zig").Entry;
usingnamespace @cImport({
    @cInclude("pulse/pulseaudio.h");
});

const name = "minimixer";

fn check(status: c_int, comptime err: anyerror) !void {
    if (status < 0) {
        return err;
    }
}

pub const PulseHandler = struct {
    mainloop: *pa_threaded_mainloop,
    context: *pa_context,

    fn sink_new_cb(
        context: ?*pa_context,
        info: [*c]const pa_sink_input_info,
        eol: c_int,
        userdata: ?*c_void,
    ) callconv(.C) void {
        if (eol == 1) return;
        const entries = @ptrCast(*std.ArrayList(Entry), @alignCast(8, userdata));
        entries.append(.{
            .id = info.*.index,
            .name = std.mem.span(info.*.name),
        }) catch unreachable;
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
            },
            .PA_CONTEXT_FAILED => {
                std.log.err("failed to connect to pulseaudio", .{});
                std.process.exit(1);
            },
            .PA_CONTEXT_TERMINATED => {},
            else => unreachable,
        }
    }

    pub fn init(entries: *std.ArrayList(Entry)) !@This() {
        const mainloop = pa_threaded_mainloop_new() orelse return error.PulseMainloopNew;
        try check(pa_threaded_mainloop_start(mainloop), error.PulseMainloopStart);

        const api = pa_threaded_mainloop_get_api(mainloop);
        const context = pa_context_new(api, name) orelse return error.PulseContextNew;
        pa_context_set_state_callback(context, context_state_cb, entries);
        try check(pa_context_connect(context, null, pa_context_flags.PA_CONTEXT_NOFLAGS, null), error.PulseContextConnect);

        return PulseHandler{
            .mainloop = mainloop,
            .context = context,
        };
    }

    pub fn uninit(self: @This()) void {
        pa_context_disconnect(self.context);
        pa_threaded_mainloop_stop(self.mainloop);
        pa_threaded_mainloop_free(self.mainloop);
    }
};
