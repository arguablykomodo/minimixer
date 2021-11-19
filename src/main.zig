const std = @import("std");
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

fn sinkInputCallback(pulse_context: ?*pa_context, input: [*c]const pa_sink_input_info, eol: c_int, userdata: ?*c_void) callconv(.C) void {
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
        else => unreachable
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

    const display = XOpenDisplay(null) orelse return error.XOpenDisplay;
    defer _ = XCloseDisplay(display);
    const screen = XDefaultScreen(display);
    const visual = XDefaultVisual(display, screen);
    const colormap = XDefaultColormap(display, screen);

    var attributes: XSetWindowAttributes = .{
        .background_pixmap = undefined,
        .background_pixel = background,
        .border_pixmap = undefined,
        .border_pixel = undefined,
        .bit_gravity = undefined,
        .win_gravity = undefined,
        .backing_store = undefined,
        .backing_planes = undefined,
        .backing_pixel = undefined,
        .save_under = undefined,
        .event_mask = KeyPressMask | ExposureMask,
        .do_not_propagate_mask = undefined,
        .override_redirect = undefined,
        .colormap = undefined,
        .cursor = undefined
    };
    const window = XCreateWindow(
        display, XDefaultRootWindow(display),
        0, 0, 100, 100, 0,
        CopyFromParent, InputOutput, CopyFromParent,
        CWBackPixel | CWEventMask, &attributes
    );
    _ = XMapWindow(display, window);

    const gc = XCreateGC(display, window, 0, null);
    _ = XSetBackground(display, gc, background);
    _ = XSetForeground(display, gc, foreground);

    const font = XftFontOpenName(display, screen, font_name);
    const text_render_color = XRenderColor{
        .red = (foreground >> 16 & 0xFF) * 0x101,
        .green = (foreground >> 8 & 0xFF) * 0x101,
        .blue = (foreground & 0xFF) * 0x101,
        .alpha = 0xFFFF
    };
    var text_color: XftColor = undefined;
    _ = XftColorAllocValue(display, visual, colormap, &text_render_color, &text_color);
    const xft = XftDrawCreate(display, window, visual, colormap);

    var event: XEvent = undefined;
    while (true) {
        _ = XNextEvent(display, &event);
        switch (event.type) {
            KeyPress => {
                const key_press_event = @ptrCast(*XKeyPressedEvent, &event);
                if (key_press_event.keycode == 9) break; // ESC
            },
            Expose => {
                var y: c_int = 20;
                for (text.items) |line| {
                    _ = XftDrawString8(xft, &text_color, font, 0, y, line.ptr, @intCast(c_int, line.len));
                    y += 20;
                }
            },
            else => unreachable
        }
    }
}
