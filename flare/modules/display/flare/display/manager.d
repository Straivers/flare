module flare.display.manager;

import flare.core.logger: Logger;
import flare.core.memory: Allocator, Ternary;
import flare.core.handle: HandlePool, Handle32;
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
    Hidden      = 1 << 0,
    Windowed    = 1 << 1,
    Maximized   = 1 << 2,
    Minimized   = 1 << 3,
    // Fullscreen,
}

enum display_handle_name = "flare_handle32_display_id";
alias DisplayId = Handle32!display_handle_name;

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
    CursorIcon cursor_icon;
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

    void try_call(string name, Args...)(Args args) {
        mixin("if(" ~ name ~ ") " ~ name ~ "(args);");
    }
}

struct DisplayState {
    DisplayMode mode;
    bool is_close_requested;
    bool has_cursor;
    ushort width;
    ushort height;
}

class DisplayManager {
    import flare.core.os.types: OsWindow;

    enum max_open_displays = 64;
    enum max_title_length = DisplayProperties.max_title_length;

public nothrow:
    this(Logger* sys_logger, Allocator allocator) {
        _sys_logger = sys_logger;
        _displays = DisplayPool(allocator);
    }

    void process_events(bool should_wait = false) {
        _os.process_events(should_wait);
    }

    size_t num_active_displays() {
        return _displays.num_allocated;
    }

    OsWindow get_os_handle(DisplayId id) {
        return _os.get_os_handle(_displays.get(id).os_impl);
    }

    void* get_user_data(DisplayId id) {
        return _displays.get(id).user_data;
    }

    DisplayId create(ref DisplayProperties properties, Callbacks callbacks, void* user_data) nothrow {
        auto id = _displays.make();
        auto display = _displays.get(id);
        display.callbacks = callbacks;
        display.user_data = user_data;

        _sys_logger.info("Initalizing new OS window into slot %8#0x: %s (w: %s, h: %s)", id.int_value, properties.title, properties.width, properties.height);
        _os.create_window(this, id, properties, display.os_impl);
        _sys_logger.info("Initialization for window %8#0x completed.", id.int_value);

        return id;
    }

    void close(DisplayId id) nothrow {
        _os.close_window(_displays.get(id).os_impl);
    }

    void destroy(DisplayId id) nothrow {
        _sys_logger.info("Destroying window %8#0x.", id.int_value);

        _os.destroy_window(_displays.get(id).os_impl);
        _displays.dispose(id);
        _num_allocated--;
    }

    ref inout(DisplayState) get_state(DisplayId id) inout nothrow {
        return _displays.get(id).state;
    }

    bool is_live(DisplayId id) nothrow {
        return _displays.owns(id) == Ternary.yes;
    }

    bool is_visible(DisplayId id) nothrow {
        return (get_state(id).mode & (DisplayMode.Hidden | DisplayMode.Minimized)) == 0;
    }

    bool is_close_requested(DisplayId id) nothrow {
        return get_state(id).is_close_requested;
    }

    void resize(DisplayId id, ushort width, ushort height) nothrow {
        _displays.get(id).os_impl.resize(width, height);
    }

    void retitle(DisplayId id, in char[] title) nothrow {
        _displays.get(id).os_impl.retitle(title);
    }

    void change_window_mode(DisplayId id, DisplayMode mode) nothrow {
        _displays.get(id).os_impl.set_mode(mode);
    }

package:
    Logger* _sys_logger;

    pragma(inline, true);
    void dispatch_event(string event, Args...)(DisplayId id, Args args) {
        mixin("_" ~ event ~ "(id, args);");
    }

protected:
    void _on_create(DisplayId id) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_create"(EventSource(this, id, display.user_data));
    }

    void _on_destroy(DisplayId id) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_destroy"(EventSource(this, id, display.user_data));
    }

    void _on_resize(DisplayId id, ushort width, ushort height) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_resize"(EventSource(this, id, display.user_data), width, height);
    }

    void _on_key(DisplayId id, KeyCode key, ButtonState state) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_key"(EventSource(this, id, display.user_data), key, state);
    }

private:
    alias DisplayPool = HandlePool!(_Display, display_handle_name, max_open_displays);

    struct _Display {
        DisplayState state;
        DisplayImpl os_impl;
        Callbacks callbacks;
        void* user_data;
    }

    OsWindowManager _os;
    size_t _num_allocated;
    DisplayPool _displays;
}
