module flare.os.window_manager;

import flare.logger : Logger;
import flare.memory : Allocator, Ternary;
import flare.os.input : ButtonState, KeyCode;
import flare.os.window;
import flare.util.checked_pointer : CheckedVoidPtr;
import flare.util.handle : HandlePool;

version (Windows)
    import flare.os.win32.win32_window;

struct WindowManager {
    import flare.os.types: OsWindow;

    enum max_open_displays = 64;
    enum max_title_length = WindowProperties.max_title_length;

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

    @disable this(this);

    void process_events(bool should_wait = false) {
        _os.process_events(should_wait);
    }

    size_t num_active_displays() {
        return _displays.num_allocated;
    }

    OsWindow get_os_handle(WindowId id) {
        return _os.get_os_handle(_displays.get(id).os_impl);
    }

    CheckedVoidPtr get_user_data(WindowId id) {
        return _displays.get(id).user_data;
    }

    void set_user_data(WindowId id, CheckedVoidPtr new_user_data) {
        _displays.get(id).user_data = new_user_data;
    }

    WindowId create(ref WindowProperties properties) nothrow {
        auto id = _displays.make();
        auto display = _displays.get(id);
        display.callbacks = properties.callbacks;
        display.user_data = properties.user_data;
        display.state.vsync = properties.vsync;

        _sys_logger.info("Initalizing new OS window into slot %8#0x: %s (w: %s, h: %s)", id.int_value, properties.title, properties.width, properties.height);
        _os.create_window(impl_callbacks, id, properties, display.os_impl);
        _sys_logger.info("Initialization for window %8#0x completed.", id.int_value);
        return id;
    }

    void close(WindowId id) nothrow {
        _os.close_window(_displays.get(id).os_impl);
    }

    void destroy(WindowId id) nothrow {
        _sys_logger.info("Destroying window %8#0x.", id.int_value);

        _os.destroy_window(_displays.get(id).os_impl);
        _displays.dispose(id);
    }

    ref const(WindowState) get_state(WindowId id) const nothrow {
        return _displays.get(id).state;
    }

    bool is_live(WindowId id) nothrow {
        return _displays.owns(id) == Ternary.yes;
    }

    bool is_visible(WindowId id) nothrow {
        const mode = get_state(id).mode;
        return mode == WindowMode.Windowed || mode == WindowMode.Maximized;
    }

    bool is_close_requested(WindowId id) nothrow {
        return get_state(id).is_close_requested;
    }

    void resize(WindowId id, ushort width, ushort height) nothrow {
        _displays.get(id).os_impl.resize(width, height);
    }

    void retitle(WindowId id, in char[] title) nothrow {
        _displays.get(id).os_impl.retitle(title);
    }

    void change_window_mode(WindowId id, WindowMode mode) nothrow {
        _displays.get(id).os_impl.set_mode(mode);
    }

package:
    pragma(inline, true);
    void dispatch_event(string event, Args...)(WindowId id, Args args) {
        mixin("_" ~ event ~ "(id, args);");
    }

    WindowState* _get_mutable_state(WindowId id) {
        return &_displays.get(id).state;
    }

protected:
    Logger* _sys_logger;

    void _on_create(WindowId id, CheckedVoidPtr aux_data) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_create"(&this, id, display.user_data, aux_data);
    }

    void _on_close(WindowId id) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_close"(&this, id, display.user_data);
    }

    void _on_destroy(WindowId id) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_destroy"(&this, id, display.user_data);
    }

    void _on_resize(WindowId id, ushort width, ushort height) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_resize"(&this, id, display.user_data, width, height);
    }

    void _on_key(WindowId id, KeyCode key, ButtonState state) {
        auto display = _displays.get(id);
        display.callbacks.try_call!"on_key"(&this, id, display.user_data, key, state);
    }

private:
    alias DisplayPool = HandlePool!(_Display, display_handle_name, max_open_displays);

    struct _Display {
        WindowState state;
        DisplayImpl os_impl;
        Callbacks callbacks;
        CheckedVoidPtr user_data;
    }

    ImplCallbacks impl_callbacks;

    OsWindowManager _os;
    DisplayPool _displays;
}
