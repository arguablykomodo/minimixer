const std = @import("std");
const Entry = @import("./main.zig").Entry;
usingnamespace @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xft/Xft.h");
});

const width = 100;
const height = 100;
const background = 0x222222;
const foreground = 0xAAAAAA;
const font_name = "Fira Code:style=Regular";

const text_render_color = XRenderColor{
    .red = (foreground >> 16 & 0xFF) * 0x101,
    .green = (foreground >> 8 & 0xFF) * 0x101,
    .blue = (foreground & 0xFF) * 0x101,
    .alpha = 0xFFFF,
};

var window_attrs: XSetWindowAttributes = .{
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
    .cursor = undefined,
};

var gc_values: XGCValues = .{
    .function = undefined,
    .plane_mask = undefined,
    .foreground = foreground,
    .background = background,
    .line_width = undefined,
    .line_style = undefined,
    .cap_style = undefined,
    .join_style = undefined,
    .fill_style = undefined,
    .fill_rule = undefined,
    .arc_mode = undefined,
    .tile = undefined,
    .stipple = undefined,
    .ts_x_origin = undefined,
    .ts_y_origin = undefined,
    .font = undefined,
    .subwindow_mode = undefined,
    .graphics_exposures = undefined,
    .clip_x_origin = undefined,
    .clip_y_origin = undefined,
    .clip_mask = undefined,
    .dash_offset = undefined,
    .dashes = undefined,
};

fn check(status: c_int, comptime err: anyerror) !void {
    if (status == 0) {
        return err;
    }
}

pub const XHandler = struct {
    display: *Display,
    visual: *Visual,
    colormap: Colormap,
    font: *XftFont,
    text_color: XftColor,
    xft: *XftDraw,
    entries: *std.ArrayList(Entry),

    pub fn init(entries: *std.ArrayList(Entry)) !@This() {
        const display = XOpenDisplay(null) orelse return error.XOpenDisplay;
        const screen = XDefaultScreen(display);
        const visual = XDefaultVisual(display, screen);
        const colormap = XDefaultColormap(display, screen);

        const window = XCreateWindow(
            display, XDefaultRootWindow(display),
            0, 0, width, height, 0,
            CopyFromParent, InputOutput, visual,
            CWBackPixel | CWEventMask, &window_attrs,
        );
        try check(XMapWindow(display, window), error.XMapWindow);
        const gc = XCreateGC(
            display, window,
            GCForeground | GCBackground,
            &gc_values,
        );

        const font = XftFontOpenName(display, screen, font_name) orelse return error.XftFontOpenName;
        var text_color: XftColor = undefined;
        try check(
            XftColorAllocValue(display, visual, colormap, &text_render_color, &text_color),
            error.XftColorAllocValue,
        );
        const xft = XftDrawCreate(display, window, visual, colormap) orelse return error.XftDrawCreate;

        return @This(){
            .display = display,
            .visual = visual,
            .colormap = colormap,
            .font = font,
            .text_color = text_color,
            .xft = xft,
            .entries = entries,
        };
    }

    pub fn uninit(self: *@This()) void {
        XftFontClose(self.display, self.font);
        XftColorFree(self.display, self.visual, self.colormap, &self.text_color);
        _ = XCloseDisplay(self.display);
    }

    pub fn draw(self: @This()) void {
        var extents: XGlyphInfo = undefined;
        var y: c_int = 0;
        for (self.entries.items) |entry| {
            const len = @intCast(c_int, entry.name.len);
            _ = XftTextExtentsUtf8(self.display, self.font, entry.name.ptr, len, &extents);
            y += extents.height;
            _ = XftDrawStringUtf8(self.xft, &self.text_color, self.font, 0, y, entry.name.ptr, len);
        }
    }

    pub fn main_loop(self: @This()) !void {
        var event: XEvent = undefined;
        while (true) {
            _ = XNextEvent(self.display, &event);
            switch (event.type) {
                KeyPress => {
                    const key_press_event = @ptrCast(*XKeyPressedEvent, &event);
                    if (key_press_event.keycode == 9) return; // ESC
                },
                Expose => self.draw(),
                else => unreachable,
            }
        }
    }
};
