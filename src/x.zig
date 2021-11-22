const std = @import("std");
const Entry = @import("./main.zig").Entry;
const PulseHandler = @import("./pulse.zig").PulseHandler;
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
const entry_height = text_height + inner_padding + volume_height + outer_padding * 2;
const height = 4 * entry_height;

const font_name = "Fira Code:style=Regular";

const background = 0x222222;
const volume_bg = 0x333333;
const volume_fg = 0x555555;
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
    .event_mask = KeyPressMask | ButtonPressMask | Button1MotionMask | ButtonReleaseMask | ExposureMask,
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
    volume_fg: XftColor,
    xft: *XftDraw,
    entries: *std.ArrayList(Entry),
    pulse_handler: *PulseHandler,
    selected_entry: ?c_uint,

    pub fn init(entries: *std.ArrayList(Entry), pulse_handler: *PulseHandler) !@This() {
        try check(XInitThreads(), error.XInitThreads);
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
            .volume_fg = try allocColor(display, visual, colormap, renderColor(volume_fg)),
            .xft = xft,
            .entries = entries,
            .pulse_handler = pulse_handler,
            .selected_entry = null,
        };
    }

    pub fn uninit(self: *@This()) void {
        XftFontClose(self.display, self.font);
        XftColorFree(self.display, self.visual, self.colormap, &self.foreground);
        XftColorFree(self.display, self.visual, self.colormap, &self.volume_bg);
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
            _ = XftDrawRect(self.xft, &self.volume_fg, outer_padding, y, @floatToInt(c_uint, entry.volume * volume_width), volume_height);
            y += volume_height + outer_padding;
        }
        _ = XFlush(self.display);
    }

    fn set_volume(self: @This(), x: c_int) void {
        if (self.selected_entry) |selected_entry| {
            const volume =
                @intToFloat(f64, std.math.min(volume_width, std.math.max(x - outer_padding, 0))) /
                @intToFloat(f64, volume_width);
            self.pulse_handler.set_volume(selected_entry, volume);
        }
    }

    pub fn main_loop(self: *@This()) !void {
        var e: XEvent = undefined;
        while (true) {
            _ = XNextEvent(self.display, &e);
            switch (e.type) {
                KeyPress => {
                    const event = @ptrCast(*XKeyPressedEvent, &e);
                    if (event.keycode == 9) return; // ESC
                },
                ButtonPress => {
                    const event = @ptrCast(*XButtonPressedEvent, &e);
                    if (event.button != 1) continue;
                    const i = @intCast(usize, event.y) / entry_height;
                    if (self.entries.items.len > i) {
                        self.selected_entry = self.entries.items[i].id;
                    } else {
                        self.selected_entry = null;
                    }
                    self.set_volume(event.x);
                },
                MotionNotify => {
                    const event = @ptrCast(*XPointerMovedEvent, &e);
                    self.set_volume(event.x);
                },
                ButtonRelease => {
                    const event = @ptrCast(*XButtonPressedEvent, &e);
                    if (event.button != 1) continue;
                    self.set_volume(event.x);
                    self.selected_entry = null;
                },
                Expose => self.draw(),
                else => unreachable,
            }
        }
    }
};
