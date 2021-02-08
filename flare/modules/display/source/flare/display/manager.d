module flare.display.manager;

import flare.core.memory;
import flare.display.win32;
import flare.display.input: KeyCode, ButtonState;

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

/**
An EventSource is a convenience struct that is passed to display callbacks.
*/
struct EventSource {
    DisplayManager manager;
    DisplayId display_id;
    void* user_data;
}

alias OnCreate = void function(EventSource) nothrow;
alias OnDestroy = void function(EventSource) nothrow;
alias OnResize = void function(EventSource, ushort width, ushort height) nothrow;

alias OnKey = void function(EventSource, KeyCode, ButtonState) nothrow;

struct DisplayProperties {
    enum max_title_length = 255;

    const(char)[] title;

    ushort width;
    ushort height;
    bool is_resizable;
    DisplayMode mode;

    void* user_data;
    CursorIcon cursor_icon;

    Callbacks callbacks;
}

struct Callbacks {
    /**
    Callback called during window creation. This callback will be called after
    the window has been created, and before the window is visible.
    */
    OnCreate on_create;

    /**
    Callback called during window destruction. This callback will be called
    before the window is destroyed.
    */
    OnDestroy on_destroy;

    /**
    Callback called during window resizing.
    */
    OnResize on_resize;

    /**
    Callback called when a keyboard event occurs within the window.
    */
    OnKey on_key;
}

class DisplayManager {
    import flare.core.os.types: OsWindow;

    enum max_open_displays = 64;
    enum max_title_length = DisplayProperties.max_title_length;

public nothrow:
    this(Allocator allocator) {
        _displays = WeakObjectPool!DisplayImpl(allocator, max_open_displays);
    }

    void process_events(bool should_wait = false) {
        _os.process_events(should_wait);
    }

    size_t num_active_displays() {
        return _num_allocated;
    }

    OsWindow get_os_handle(DisplayId id) {
        return _os.get_os_handle(_displays.get(Handle.from(id)));
    }

    void* get_user_data(DisplayId id) {
        return _displays.get(Handle.from(id)).user_data;
    }

    DisplayId create(ref DisplayProperties properties) nothrow {
        auto id = _displays.allocate();
        _num_allocated++;

        _os.create_window(this, id.to!DisplayId, properties, *_displays.get(id));
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

private:
    OsWindowManager _os;
    size_t _num_allocated;
    WeakObjectPool!DisplayImpl _displays;

    alias Handle = _displays.Handle;
}
