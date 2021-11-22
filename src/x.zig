const std = @import("std");
const Entry = @import("./main.zig").Entry;
usingnamespace @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xft/Xft.h");
});

const outer_padding = 20; // Padding between window and entries
const inner_padding = 20; // Padding between text and volume bar
const text_height = 12;
const volume_height = 10;
const volume_width = 400;

const width = volume_width + outer_padding * 2;
const height = 4 * (text_height + inner_padding + volume_height + outer_padding * 2);

const font_name = "Fira Code:style=Regular";

const background = 0x222222;
const volume_bg = 0x333333;
const foreground = 0xAAAAAA;

fn renderColor(comptime hex: comptime_int) XRenderColor {
    return XRenderColor{
        .red = (hex >> 16 & 0xFF) * 0x101,
        .green = (hex >> 8 & 0xFF) * 0x101,
        .blue = (hex & 0xFF) * 0x101,
        .alpha = 0xFFFF,
    };
}

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
    .foreground = undefined,
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

fn allocColor(
    display: *Display,
    visual: *Visual,
    colormap: Colormap,
    render_color: XRenderColor,
) !XftColor {
    var color: XftColor = undefined;
    try check(
        XftColorAllocValue(display, visual, colormap, &render_color, &color),
        error.XftColorAllocValue,
    );
    return color;
}

pub const XHandler = struct {
    display: *Display,
    window: Window,
    visual: *Visual,
    colormap: Colormap,
    font: *XftFont,
    foreground: XftColor,
    volume_bg: XftColor,
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
        const gc = XCreateGC(display, window, GCBackground, &gc_values);

        const font = XftFontOpenName(display, screen, font_name) orelse return error.XftFontOpenName;
        const xft = XftDrawCreate(display, window, visual, colormap) orelse return error.XftDrawCreate;

        return @This(){
            .display = display,
            .window = window,
            .visual = visual,
            .colormap = colormap,
            .font = font,
            .foreground = try allocColor(display, visual, colormap, renderColor(foreground)),
            .volume_bg = try allocColor(display, visual, colormap, renderColor(volume_bg)),
            .xft = xft,
            .entries = entries,
        };
    }

    pub fn uninit(self: *@This()) void {
        XftFontClose(self.display, self.font);
        XftColorFree(self.display, self.visual, self.colormap, &self.foreground);
        _ = XCloseDisplay(self.display);
    }

    pub fn draw(self: @This()) void {
        _ = XClearWindow(self.display, self.window);
        var y: c_int = outer_padding;
        for (self.entries.items) |entry| {
            y += text_height;
            _ = XftDrawStringUtf8(self.xft, &self.foreground, self.font, outer_padding, y, entry.name.items.ptr, @intCast(c_int, entry.name.items.len));
            y += inner_padding;
            _ = XftDrawRect(self.xft, &self.volume_bg, outer_padding, y, 400, 10);
            _ = XftDrawRect(self.xft, &self.foreground, outer_padding, y, @floatToInt(c_uint, entry.volume * volume_width), volume_height);
            y += volume_height + outer_padding;
        }
        _ = XFlush(self.display);
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
