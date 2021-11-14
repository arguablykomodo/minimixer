const std = @import("std");
usingnamespace @cImport({
    @cInclude("X11/Xlib.h");
});

pub fn main() anyerror!void {
    const display = XOpenDisplay(null) orelse return error.XOpenDisplay;
    defer _ = XCloseDisplay(display);

    var attributes: XSetWindowAttributes = .{
        .background_pixmap = undefined,
        .background_pixel = 0x222222,
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
    _ = XSetBackground(display, gc, 0x222222);
    _ = XSetForeground(display, gc, 0xaaaaaa);

    var event: XEvent = undefined;
    while (true) {
        _ = XNextEvent(display, &event);
        switch (event.type) {
            KeyPress => {
                const key_press_event = @ptrCast(*XKeyPressedEvent, &event);
                if (key_press_event.keycode == 9) break; // ESC
            },
            Expose => {
                _ = XFillRectangle(display, window, gc, 10, 10, 80, 80);
            },
            else => unreachable
        }
    }
}
