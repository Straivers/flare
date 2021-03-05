module flare.display.manager;

import flare.core.logger: Logger;
import flare.core.memory: Allocator, Ternary;
import flare.core.handle: HandlePool;
import flare.display.input: KeyCode, ButtonState;
import flare.display.display;

version (Windows)
    import flare.display.win32;

alias OnCreate = void function(DisplayManager, DisplayId, void* user_data) nothrow;
alias OnClose = void function(DisplayManager, DisplayId, void* user_data) nothrow;
alias OnDestroy = void function(DisplayManager, DisplayId, void* user_data) nothrow;

alias OnResize = void function(DisplayManager, DisplayId, void* user_data, ushort width, ushort height) nothrow;
alias OnKey = void function(DisplayManager, DisplayId, void* user_data, KeyCode, ButtonState) nothrow;

struct Callbacks {
    /*
    NOTE:
        To add a new callback:
            1) Create a new alias type for the callback function.
            2) Add a pointer of that type to the `Callbacks` struct called `$callback_name$`.
            3) Add a handler called `_$callback_name$(DisplayId, Args...)`.
            4) Add a delegate of the same type to `ImplCallbacks` for each OS implementation.
            5) Add a case in the OS layer to call the delegate callback.
            6) Add `DisplayManager._$callback_name$(DisplayId, Args...)` to the impl callbacks.
            5) Update any sublcasses that need to make use of the callback.
    */

    /**
    Callback called during window creation. This callback will be called after
    the window has been created, and before the window is visible.
    */
    OnCreate on_create;

    /**
    Callback called when a user presses the `x` to close a window, or when
    `DisplayManager.close()` is called.
    */
    OnClose on_close;

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

class DisplayManager {
    import flare.core.os.types: OsWindow;

    enum max_open_displays = 64;
    enum max_title_length = DisplayProperties.max_title_length;

public nothrow:
    this(Logger* sys_logger, Allocator allocator) {
        _sys_logger = sys_logger;
        _displays = DisplayPool(allocator);
        _os.initialize();

        // Handles subclass overrides too.
        impl_callbacks.get_state = &_get_mutable_state;
        impl_callbacks.on_create = &_on_create;
        impl_callbacks.on_close = &_on_close;
        impl_callbacks.on_destroy = &_on_destroy;
        impl_callbacks.on_resize = &_on_resize;
        impl_callbacks.on_key = &_on_key;
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
        _os.create_window(impl_callbacks, id, properties, display.os_impl);
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

    ref const(DisplayState) get_state(DisplayId id) const nothrow {
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
    pragma(inline, true);
    void dispatch_event(string event, Args...)(DisplayId id, Args args) {
        mixin("_" ~ event ~ "(id, args);");
    }

    DisplayState* _get_mutable_state(DisplayId id) {
        return &_displays.get(id).state;
    }

protected:
    Logger* _sys_logger;

    void _on_create(DisplayId id) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_create"(this, id, get_user_data(id));
    }

    void _on_close(DisplayId id) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_close"(this, id, get_user_data(id));
    }

    void _on_destroy(DisplayId id) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_destroy"(this, id, get_user_data(id));
    }

    void _on_resize(DisplayId id, ushort width, ushort height) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_resize"(this, id, get_user_data(id), width, height);
    }

    void _on_key(DisplayId id, KeyCode key, ButtonState state) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_key"(this, id, get_user_data(id), key, state);
    }

private:
    alias DisplayPool = HandlePool!(_Display, display_handle_name, max_open_displays);

    struct _Display {
        DisplayState state;
        DisplayImpl os_impl;
        Callbacks callbacks;
        void* user_data;
    }

    ImplCallbacks impl_callbacks;

    OsWindowManager _os;
    size_t _num_allocated;
    DisplayPool _displays;
}
