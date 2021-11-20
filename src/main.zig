const std = @import("std");
const XHandler = @import("./x.zig").XHandler;
usingnamespace @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xft/Xft.h");
    @cInclude("pulse/pulseaudio.h");
});

const background = 0x222222;
const foreground = 0xAAAAAA;
const font_name = "Fira Code:style=Regular";
const app_name = "minimixer";

var text = std.ArrayList([]const u8).init(std.heap.c_allocator);

fn sinkInputCallback(
    pulse_context: ?*pa_context,
    input: [*c]const pa_sink_input_info,
    eol: c_int,
    userdata: ?*c_void,
) callconv(.C) void {
    if (eol == 1) return;
    _ = text.append(std.mem.span(input.*.name)) catch unreachable;
}

fn stateCallback(pulse_context: ?*pa_context, userdata: ?*c_void) callconv(.C) void {
    _ = switch (pa_context_get_state(pulse_context)) {
        pa_context_state.PA_CONTEXT_UNCONNECTED => null,
        pa_context_state.PA_CONTEXT_CONNECTING => null,
        pa_context_state.PA_CONTEXT_AUTHORIZING => null,
        pa_context_state.PA_CONTEXT_SETTING_NAME => null,
        pa_context_state.PA_CONTEXT_READY => {
            _ = pa_context_get_sink_input_info_list(pulse_context, sinkInputCallback, null);
        },
        pa_context_state.PA_CONTEXT_FAILED => {
            std.log.err("failed to connect to pulseaudio", .{});
            std.process.exit(1);
        },
        pa_context_state.PA_CONTEXT_TERMINATED => null,
        else => unreachable,
    };
}

pub fn main() anyerror!void {
    const pulse_mainloop = pa_threaded_mainloop_new();
    _ = pa_threaded_mainloop_start(pulse_mainloop);
    defer _ = {
        pa_threaded_mainloop_stop(pulse_mainloop);
        pa_threaded_mainloop_free(pulse_mainloop);
    };

    const pulse_context = pa_context_new(pa_threaded_mainloop_get_api(pulse_mainloop), app_name);
    _ = pa_context_connect(pulse_context, null, pa_context_flags.PA_CONTEXT_NOFLAGS, null);
    defer _ = pa_context_disconnect(pulse_context);
    pa_context_set_state_callback(pulse_context, stateCallback, null);

    var handler = try XHandler.init(&text);
    defer handler.uninit();
    try handler.main_loop();
}
