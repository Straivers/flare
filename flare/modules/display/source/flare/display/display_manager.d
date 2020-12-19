module flare.display.display_manager;

version (Windows)
    import flare.display.win32_display;
else
    static assert(0, "Display manager does not support the targeted OS/Window manager");

public import flare.display.display;
import flare.display.input;
import flare.renderer.renderer;

enum DisplayResult {
    NoError,
    ErrTooManyDisplays,
    TitleTruncated
}

final class DisplayManager {
    import std.algorithm: min;

    /// The maximum number of displays that may be open simultaneously.
    enum max_displays = 64;
    enum max_title_length = 255;

public:
    ~this() {
        import core.bitop: bsf;

        if (_bitmap == ulong.max)
            return;
        
        for (int i = bsf(~_bitmap); _bitmap != ulong.max; i = bsf(~_bitmap))
            platform_destroy_window(_displays[i].platform_data);

        platform_poll_events();
    }

    size_t num_active_displays() {
        import core.bitop: _popcnt;

        return cast(size_t) _popcnt(~_bitmap);
    }

    void process_events(bool should_wait) {
        if (should_wait)
            platform_wait_events();
        else
            platform_poll_events();
    }

    DisplayResult make_display(ref DisplayProperties options, ref DisplayCallbacks callbacks, out DisplayId id) {
        if (auto display = alloc()) {
            {
                display.properties = options;

                const title_length = min(options.title.length, max_title_length);
                display.title_storage[0 .. title_length] = options.title;
                display.title_storage[title_length] = '\0';
                display.properties.title = display.title_storage[0 .. title_length + 1];
            }

            display.manager = this;
            display.callbacks = callbacks;

            display.platform_data = platform_create_window(display.properties, display);
            display.swapchain = display.renderer.create_swapchain(platform_get_os_handle(display.platform_data));
            
            id = display.id;

            if (options.title.length <= max_title_length)
                return DisplayResult.NoError;
            else
                return DisplayResult.TitleTruncated;
        }

        return DisplayResult.ErrTooManyDisplays;
    }

    void destroy_display(DisplayId id) nothrow {
        if (auto display = get_display_from(id)) {
            platform_destroy_window(display.platform_data);
        }
    }

    bool is_live(DisplayId id) {
        auto id_ = DisplayIdImpl(id);
        auto slot = &_displays[id_.index];

        return id == slot.id;
    }

    auto os_handle(DisplayId id) {
        if (auto display = get_display_from(id))
            return platform_get_os_handle(display.platform_data);
        return invalid_platform_window_data;
    }

    SwapchainId get_swapchain(DisplayId id) {
        if (auto display = get_display_from(id))
            return display.swapchain;
        assert(false);
    }

    void swap_buffers(DisplayId id) {
        if (auto display = get_display_from(id))
            display.properties.renderer.swap_buffers(display.swapchain);
    }

    void resize(DisplayId id, ushort width, ushort height) {
        // send -> event loop (os_resize) -> swapchain resize -> callback
        if (auto display = get_display_from(id)) {
            platform_resize(display.platform_data, width, height);
            display.properties.renderer.resize(display.swapchain, width, height);
        }
    }

    void retitle(DisplayId id, in char[] new_title) {
        if (auto display = get_display_from(id)) {
            const title_length = min(new_title.length, max_title_length);
            display.title_storage[0 .. title_length] = new_title;
            display.title_storage[title_length] = '\0';
            display.title = display.title_storage[0 .. title_length + 1];

            platform_retitle(display.platform_data, display.title);
        }
    }

    void set_cursor(DisplayId id, CursorIcon icon) {
        if (auto display = get_display_from(id)) {
            display.properties.cursor_icon = icon;
            platform_set_cursor(display.platform_data, icon);
        }
    }

    void set_mode(DisplayId id, DisplayMode mode) {
        if (auto display = get_display_from(id)) {
            display.properties.mode = mode;
            platform_set_mode(display.platform_data, mode);
        }
    }

    void send_close_request(DisplayId id) {
        // send -> event loop (is_close_requested = true) -> callback
        if (auto display = get_display_from(id)) {
            platform_send_close_request(display.platform_data);
        }
    }

private:
    DisplayImpl* alloc() {
        import core.bitop : bsf;

        if (_bitmap) {
            const index = bsf(_bitmap);
            _bitmap ^= 1 << index;

            assert(_displays[index].platform_data == invalid_platform_window_data);
            return &_displays[index];
        }
        return null;
    }

    DisplayImpl* get_display_from(DisplayId id) nothrow {
        auto id_ = DisplayIdImpl(id);
        auto slot = &_displays[id_.index];

        if (id == slot.id)
            return slot;

        debug assert(false, "Attempted to manipulate nonexistent display");
        else return null;
    }

    package void free(DisplayImpl* display) nothrow {
        auto id_ = DisplayIdImpl(display.id);
        id_.generation++;
        *display = DisplayImpl();
        display.id = id_.value;
        _bitmap |= 1 << id_.index;

        assert(display.platform_data == invalid_platform_window_data);
    }

    ulong _bitmap = ulong.max;
    DisplayImpl[64] _displays;
}

package:

struct DisplayImpl {
    DisplayProperties properties;
    alias properties this;

    DisplayCallbacks callbacks;

    DisplayId id;

    bool has_focus;
    bool has_cursor;
    bool is_close_requested;

    char[DisplayManager.max_title_length + 1] title_storage;

    DisplayManager manager;
    PlatformWindowData platform_data;

    SwapchainId swapchain;
}

union DisplayIdImpl {
    DisplayId value;

    struct {
        uint index;
        uint generation;
    }
}
