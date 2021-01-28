module flare.display.manager;

import flare.core.memory;
import flare.display.win32;
import flare.renderer.renderer;

// public import flare.display.display;

version (Windows)
    import flare.display.win32;

/// The icon over the cursor. User defiend icons are currently not supported,
/// and using those flags will cause an error.
enum CursorIcon : ubyte {
    /// ⭦
    Pointer,
    /// ⌛
    Wait,
    /// Ꮖ
    IBeam,
    /// ⭤
    ResizeHorizontal,
    /// ⭥
    ResizeVertical,
    /// ⤡
    ResizeNorthwestSoutheast,
    /// ⤢
    ResizeCornerNortheastSouthwest,
    ///
    UserDefined1 = 128,
    ///
    UserDefined2,
    ///
    UserDefined3,
    ///
    UserDefined4
}

enum DisplayMode : ubyte {
    Windowed = 1,
    Hidden = 1 << 1,
    Maximized = 1 << 2,
    Minimized = 1 << 3,
    // Fullscreen,
}

struct DisplayId {
    ulong value;
}

struct DisplayProperties {
    import flare.renderer.renderer: Renderer;

    enum max_title_length = 255;

    const(char)[] title;

    ushort width;
    ushort height;
    bool is_resizable;
    DisplayMode mode;
    Renderer renderer;
    DisplayInput input_callbacks;

    void* user_data;
    CursorIcon cursor_icon;
}

struct DisplayInput {
    import flare.display.input: KeyCode, ButtonState;

    void function(DisplayManager manager, DisplayId display, KeyCode key, ButtonState state, void* data) nothrow on_key;
}

final class DisplayManager {

    enum max_title_length = DisplayProperties.max_title_length;

public:
    this(Allocator allocator) {
        _displays = WeakObjectPool!DisplayImpl(allocator, 64);
    }

    void process_events(bool should_wait = false) {
        _os.process_events(should_wait);
    }

    size_t num_active_displays() {
        return _num_allocated;
    }

    DisplayId create(ref DisplayProperties properties) nothrow {
        auto id = _displays.allocate();
        _os.create_window(this, id.to!DisplayId, properties, *_displays.get(id));
        _num_allocated++;
        return id.to!DisplayId;
    }

    void close(DisplayId id) nothrow {
        _os.close_window(_displays.get(Handle.from(id)));
    }

    void destroy(DisplayId id) nothrow {
        _os.destroy_window(_displays.get(Handle.from(id)));
        _displays.deallocate(Handle.from(id));
        _num_allocated--;
    }

    bool is_live(DisplayId id) nothrow {
        return _displays.owns(Handle.from(id)) == Ternary.yes;
    }

    bool is_visible(DisplayId id) nothrow {
        auto display = _displays.get(Handle.from(id));
        return (display.mode & (DisplayMode.Hidden | DisplayMode.Minimized)) == 0;
    }

    bool is_close_requested(DisplayId id) nothrow {
        return _displays.get(Handle.from(id)).is_close_requested;
    }

    void resize(DisplayId id, ushort width, ushort height) nothrow {
        _displays.get(Handle.from(id)).resize(width, height);
    }

    void retitle(DisplayId id, in char[] title) nothrow {
        _displays.get(Handle.from(id)).retitle(title);
    }

    void change_window_mode(DisplayId id, DisplayMode mode) nothrow {
        _displays.get(Handle.from(id)).set_mode(mode);
    }

    SwapchainId get_swapchain(DisplayId id) nothrow {
        return _displays.get(Handle.from(id)).swapchain;
    }

private:
    OsWindowManager _os;
    size_t _num_allocated;
    WeakObjectPool!DisplayImpl _displays;

    alias Handle = _displays.Handle;
}
