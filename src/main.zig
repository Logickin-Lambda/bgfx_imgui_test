//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");
const zm = @import("zm");
const builtin = @import("builtin");
const logo = @import("logo.zig");
const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {}); // We are providing our own entry point
    @cInclude("SDL3/SDL_main.h");
    @cInclude("bgfx/c99/bgfx.h");
});

const WindowConfig = struct {
    width: comptime_int,
    height: comptime_int,
};

pub fn main() !void {
    // initialize SDL:
    const window_config = WindowConfig{ .width = 1280, .height = 720 };

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        @panic("SDL Initialization Failed");
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("Imgui + BGFX Demo", window_config.width, window_config.height, 0) orelse {
        @panic("Window Creation Failed");
    };
    defer c.SDL_DestroyWindow(window);

    // initialize bgfx:
    var bgfx_init = std.mem.zeroes(c.bgfx_init_t);

    bgfx_init.type = c.BGFX_RENDERER_TYPE_COUNT;
    bgfx_init.vendorId = c.BGFX_PCI_ID_NONE;
    bgfx_init.capabilities = std.math.maxInt(u64);

    bgfx_init.resolution.format = c.BGFX_TEXTURE_FORMAT_RGBA8;
    bgfx_init.resolution.width = window_config.width;
    bgfx_init.resolution.height = window_config.height;
    bgfx_init.resolution.reset = c.BGFX_RESET_VSYNC;
    bgfx_init.resolution.numBackBuffers = 2;

    bgfx_init.limits.maxEncoders = 8;
    bgfx_init.limits.minResourceCbSize = 64 << 10;
    bgfx_init.limits.transientVbSize = 6 << 20;
    bgfx_init.limits.transientIbSize = 2 << 20;

    bgfx_init.platformData = getPlatformData(window);
    c.bgfx_set_platform_data(&bgfx_init.platformData);

    _ = c.bgfx_render_frame(-1);

    if (!c.bgfx_init(&bgfx_init)) {
        @panic("BGFX Initialization Failed");
    }
    defer c.bgfx_shutdown();

    const renderer_type = c.bgfx_get_renderer_type();
    const backend_name = c.bgfx_get_renderer_name(renderer_type);
    std.debug.print("Using Backend: {s}\n", .{backend_name});

    // enable debug text
    c.bgfx_set_debug(c.BGFX_DEBUG_TEXT);

    c.bgfx_set_view_clear(
        0,
        c.BGFX_CLEAR_COLOR | c.BGFX_CLEAR_DEPTH,
        0x303030ff,
        1,
        0,
    );

    // Main Event Loop:
    var running = true;

    while (running) {
        pollEvents(&running);

        c.bgfx_set_view_rect(0, 0, 0, window_config.width, window_config.height);

        // clear debug font
        c.bgfx_dbg_text_clear(0, false);

        // Similar to the original example, it turns out we need to use a hacky way to draw any non-shader objects;
        // otherwise, we will only have a blank black screen.
        c.bgfx_touch(0);

        const stats: *c.bgfx_stats_t = @constCast(c.bgfx_get_stats());

        // since the original has stated that bx::max<uint16_t>(uint16_t(stats->textWidth/2), 20)-20
        // meaning that if half of text width is larger, return textWisdth - 20; otherwise 0 because
        // both 20 has cancelled out. Besides, doing integer division in zig is a bit noisy due to the use
        // of @divFloor(), while this just a simple divide by 2, thus a right shift.
        const img_x = std.math.clamp(stats.textWidth >> 1, 20, std.math.maxInt(u16)) - 20;
        const img_y = std.math.clamp(stats.textHeight >> 1, 6, std.math.maxInt(u16)) - 6;

        std.log.info("img_x: {d}, img_y: {d}", .{ img_x, img_y });

        c.bgfx_dbg_text_image(
            img_x,
            img_y,
            40,
            12,
            &logo.s_logo,
            160,
        );

        // For some reasons, Directx 3D 11 doesn't show the debug text if we don't call bgfx_touch(0), but
        // Using Directx 3D 12,and Vulkan works perfectly fine.
        c.bgfx_dbg_text_printf(0, 1, 0x0f, "Color can be changed with ANSI \x1b[9;me\x1b[10;ms\x1b[11;mc\x1b[12;ma\x1b[13;mp\x1b[14;me\x1b[0m code too.");
        c.bgfx_dbg_text_printf(80, 1, 0x0f, "\x1b[;0m    \x1b[;1m    \x1b[; 2m    \x1b[; 3m    \x1b[; 4m    \x1b[; 5m    \x1b[; 6m    \x1b[; 7m    \x1b[0m");
        c.bgfx_dbg_text_printf(80, 2, 0x0f, "\x1b[;8m    \x1b[;9m    \x1b[;10m    \x1b[;11m    \x1b[;12m    \x1b[;13m    \x1b[;14m    \x1b[;15m    \x1b[0m");

        c.bgfx_dbg_text_printf(
            0,
            2,
            0x0f,
            "Backbuffer %dW x %dH in pixels, debug text %dW x %dH in characters.",
            stats.width,
            stats.height,
            stats.textWidth,
            stats.textHeight,
        );

        _ = c.bgfx_frame(false);
    }
}

pub fn pollEvents(running: *bool) void {
    var event: c.SDL_Event = undefined;

    while (c.SDL_PollEvent(&event)) {
        switch (event.type) {
            c.SDL_EVENT_QUIT => running.* = false,
            c.SDL_EVENT_KEY_DOWN => switch (event.key.key) {
                c.SDLK_ESCAPE, c.SDLK_X => running.* = false,
                else => {},
            },
            else => {},
        }
    }
}

pub fn getPlatformData(window: *c.SDL_Window) c.bgfx_platform_data_t {
    // the following functions gets the windowing system information
    // which are display type and handles if there is one.
    var data = std.mem.zeroes(c.bgfx_platform_data_t);

    switch (builtin.os.tag) {
        // This might save my original confusing superbible code because it turns out
        // that std.mem.span is used for converting *c multi pointer into slices.
        .linux => {
            const video_driver = std.mem.span(c.SDL_GetCurrentVideoDriver() orelse {
                @panic("Failed to get SDL video driver");
            });

            // So the video_driver are just strings turned into slice because we can
            // just do a string comparison:
            if (std.mem.eql(u8, video_driver, "x11")) {
                data.type = c.BGFX_NATIVE_WINDOW_HANDLE_TYPE_DEFAULT;
                data.ndt = getWindowPtrProperties(window, c.SDL_PROP_WINDOW_X11_DISPLAY_POINTER);
                data.nwh = getWindowIntProperties(window, c.SDL_PROP_WINDOW_X11_WINDOW_NUMBER);
            } else if (std.mem.eql(u8, video_driver, "x11")) {
                data.type = c.BGFX_NATIVE_WINDOW_HANDLE_TYPE_WAYLAND;
                data.ndt = getWindowIntProperties(window, c.SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER);
                data.nwh = getWindowPtrProperties(window, c.SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER);
            } else {
                // Seems like Zero and Ziggy can do things like just Ferris
                std.debug.panic("Unspported window driver from linux", .{});
            }
        },
        .windows => {
            data.nwh = getWindowPtrProperties(window, c.SDL_PROP_WINDOW_WIN32_HWND_POINTER);
        },
        .macos => {
            data.nwh = getWindowPtrProperties(window, c.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER);
        },
        else => {
            std.debug.panic("Unsupported os: {s}\n", .{@tagName(builtin.os.tag)});
        },
    }

    return data;
}

pub fn getWindowIntProperties(window: *c.SDL_Window, property_name: [:0]const u8) *anyopaque {
    const properties = c.SDL_GetWindowProperties(window);

    if (properties == 0) {
        @panic("Failed to get the SDL window property ID with the property name.");
    }

    // zero is possible for counting the properties, so we have to let zero to be valid even thought it might not.
    return @ptrFromInt(@as(usize, @intCast(c.SDL_GetNumberProperty(properties, property_name, 0))));
}

pub fn getWindowPtrProperties(window: *c.SDL_Window, property_name: [:0]const u8) *anyopaque {

    // It returns the property id or 0 if the given property is not found
    const properties = c.SDL_GetWindowProperties(window);

    if (properties == 0) {
        @panic("Failed to get the SDL window property ID with the property name.");
    }

    return c.SDL_GetPointerProperty(properties, property_name, null) orelse {
        std.debug.panic("Failed to get SDL window property '{s}'", .{property_name});
    };
}
