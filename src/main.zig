const std = @import("std");
usingnamespace @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xft/Xft.h");
});

const background = 0x222222;
const foreground = 0xAAAAAA;
const font_name = "Fira Code:style=Regular";
const text = "Hello!";

pub fn main() anyerror!void {
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
                _ = XftDrawString8(xft, &text_color, font, 22, 56, text, text.len);
            },
            else => unreachable
        }
    }
}
