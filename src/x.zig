const std = @import("std");
const Entry = @import("./main.zig").Entry;
const PulseHandler = @import("./pulse.zig").PulseHandler;
const c = @cImport({
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

fn renderColor(comptime hex: comptime_int) c.XRenderColor {
    return c.XRenderColor{
        .red = (hex >> 16 & 0xFF) * 0x101,
        .green = (hex >> 8 & 0xFF) * 0x101,
        .blue = (hex & 0xFF) * 0x101,
        .alpha = 0xFFFF,
    };
}

var window_attrs: c.XSetWindowAttributes = .{
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
    .event_mask = c.KeyPressMask | c.ButtonPressMask | c.Button1MotionMask | c.ButtonReleaseMask | c.ExposureMask,
    .do_not_propagate_mask = undefined,
    .override_redirect = undefined,
    .colormap = undefined,
    .cursor = undefined,
};

var gc_values: c.XGCValues = .{
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
    display: *c.Display,
    visual: *c.Visual,
    colormap: c.Colormap,
    render_color: c.XRenderColor,
) !c.XftColor {
    var color: c.XftColor = undefined;
    try check(
        c.XftColorAllocValue(display, visual, colormap, &render_color, &color),
        error.XftColorAllocValue,
    );
    return color;
}

pub const XHandler = struct {
    display: *c.Display,
    window: c.Window,
    visual: *c.Visual,
    colormap: c.Colormap,
    font: *c.XftFont,
    foreground: c.XftColor,
    volume_bg: c.XftColor,
    volume_fg: c.XftColor,
    xft: *c.XftDraw,
    entries: *std.ArrayList(Entry),
    pulse_handler: *PulseHandler,
    selected_entry: ?c_uint,

    pub fn init(entries: *std.ArrayList(Entry), pulse_handler: *PulseHandler) !@This() {
        try check(c.XInitThreads(), error.XInitThreads);
        const display = c.XOpenDisplay(null) orelse return error.XOpenDisplay;
        const screen = c.XDefaultScreen(display);
        const visual = c.XDefaultVisual(display, screen);
        const colormap = c.XDefaultColormap(display, screen);

        const window = c.XCreateWindow(
            display, c.XDefaultRootWindow(display),
            0, 0, width, height, 0,
            c.CopyFromParent, c.InputOutput, visual,
            c.CWBackPixel | c.CWEventMask, &window_attrs,
        );
        try check(c.XMapWindow(display, window), error.XMapWindow);
        // const gc = c.XCreateGC(display, window, .GCBackground, &gc_values);

        const font = c.XftFontOpenName(display, screen, font_name) orelse return error.XftFontOpenName;
        const xft = c.XftDrawCreate(display, window, visual, colormap) orelse return error.XftDrawCreate;

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
        c.XftFontClose(self.display, self.font);
        c.XftColorFree(self.display, self.visual, self.colormap, &self.foreground);
        c.XftColorFree(self.display, self.visual, self.colormap, &self.volume_bg);
        c.XftColorFree(self.display, self.visual, self.colormap, &self.volume_fg);
        _ = c.XCloseDisplay(self.display);
    }

    pub fn draw(self: @This()) void {
        _ = c.XClearWindow(self.display, self.window);
        var y: c_int = outer_padding;
        for (self.entries.items) |entry| {
            y += text_height;
            _ = c.XftDrawStringUtf8(self.xft, &self.foreground, self.font, outer_padding, y, entry.name.items.ptr, @intCast(c_int, entry.name.items.len));
            y += inner_padding;
            _ = c.XftDrawRect(self.xft, &self.volume_bg, outer_padding, y, 400, 10);
            _ = c.XftDrawRect(self.xft, &self.volume_fg, outer_padding, y, @floatToInt(c_uint, entry.volume * volume_width), volume_height);
            y += volume_height + outer_padding;
        }
        _ = c.XFlush(self.display);
    }

    fn set_volume(self: @This(), x: c_int) void {
        if (self.selected_entry) |selected_entry| {
            const volume =
                @intToFloat(f64, @minimum(volume_width, @maximum(x - outer_padding, 0))) /
                @intToFloat(f64, volume_width);
            self.pulse_handler.set_volume(selected_entry, volume);
        }
    }

    pub fn main_loop(self: *@This()) !void {
        var e: c.XEvent = undefined;
        while (true) {
            _ = c.XNextEvent(self.display, &e);
            switch (e.type) {
                c.KeyPress => {
                    const event = @ptrCast(*c.XKeyPressedEvent, &e);
                    if (event.keycode == 9) return; // ESC
                },
                c.ButtonPress => {
                    const event = @ptrCast(*c.XButtonPressedEvent, &e);
                    if (event.button != 1) continue;
                    const i = @intCast(usize, event.y) / entry_height;
                    if (self.entries.items.len > i) {
                        self.selected_entry = self.entries.items[i].id;
                    } else {
                        self.selected_entry = null;
                    }
                    self.set_volume(event.x);
                },
                c.MotionNotify => {
                    const event = @ptrCast(*c.XPointerMovedEvent, &e);
                    self.set_volume(event.x);
                },
                c.ButtonRelease => {
                    const event = @ptrCast(*c.XButtonPressedEvent, &e);
                    if (event.button != 1) continue;
                    self.set_volume(event.x);
                    self.selected_entry = null;
                },
                c.Expose => self.draw(),
                else => unreachable,
            }
        }
    }
};
