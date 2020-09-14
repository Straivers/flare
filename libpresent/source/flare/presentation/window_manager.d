module flare.presentation.window_manager;

import flare.presentation.window;
import flare.core.logger: Logger, LogLevel;

version (Windows)
    import flare.platform.win32.window;
else
    static assert(0, "Unsuported Operating System!");

/**
 The `WindowManager` controls the creation and destruction of operating system
 windows.
 */
struct WindowManager {
    import flare.core.memory.static_allocator : StaticAllocator;

    /// The maximum number of windows that can be open at any time.
    enum max_open_windows = 64;

nothrow public:
    /// Initializes the window manager. Pass `null` if no logging from the window
    /// manager is desired.
    @safe @nogc this(Logger* logger) {
        _logger = logger;
    }

    /// Constructs a window using the settings provided.
    @safe WindowId make_window(WindowSettings settings) {
        auto window = alloc();
        assert(window, "Too many windows!");

        window.platform_data = platform_create_window(settings, &window.status);

        return WindowId(window.id.value);
    }

    /// Destroys the window. Once destroyed, its identifier will never be reused
    /// again while the program is running.
    @safe void destroy_window(WindowId id)
    in (is_live(id)) {
        auto window = get(id);

        platform_destroy_window(window.platform_data);

        free(id);
    }

    /// Destroys all windows that have the `status.is_close_requested` flag set.
    @safe void destroy_closed_windows() {
        foreach (ref window; _windows) {
            if (window.is_active && window.is_close_requested)
                destroy_window(window.id);
        }
    }

    /// Returns: The number of windows that are currently active.
    @safe @nogc size_t num_open_windows() const pure {
        import core.bitop: _popcnt;

        /// Note: We assume that the computer was produced after 2007. Given
        /// that it's 2020, that should be a safe bet, right?
        return cast(size_t) _popcnt(~_bitmap);
    }

    /// Checks if a window id refers to one that is currently open.
    @safe @nogc bool is_live(WindowId id) const pure {
        return get(id) !is null;
    }

    /// Retrieves the status of a currently open window.
    @safe @nogc ref const(WindowStatus) get_status(WindowId id) const
    in (is_live(id)) {
        return get(id).status;
    }

    /// Resizes the window.
    @safe @nogc void resize(WindowId id, ushort new_width, ushort new_height)
    in (is_live(id)) {
        platform_resize(get(id).platform_data, new_width, new_height);
    }

    /// Changes the title of the window. Once called, the character array passed
    /// to this function may be disposed of.
    @safe @nogc void retitle(WindowId id, in char[] new_title)
    in (is_live(id)) {
        platform_retitle(get(id).platform_data, new_title);
    }

    /// Sets the icon for the cursor.
    @safe @nogc void set_cursor(WindowId id, CursorIcon icon)
    in (is_live(id)) {
        platform_set_cursor(get(id).platform_data, icon);
    }

    /// Changes the mode of the window.
    @safe @nogc void set_mode(WindowId id, WindowMode mode)
    in (is_live(id)) {
        platform_set_mode(get(id).platform_data, mode);
    }

    /// Sets the `is_close_requested` flag to `true` for the identified window,
    /// and calls the window's `on_close_request` event handler. This is
    /// equivalent to the user clicking the 'X' icon to close a window.
    @safe @nogc void send_close_request(WindowId id)
    in (is_live(id)) {
        platform_close_window(get(id).platform_data);
    }

    /// Checks for, and processes any new window events since the last
    /// `poll_events()` or `wait_events()` call. Either `poll_events()` or
    /// `wait_events()` should be called regularly to ensure the responsiveness
    /// of windows to user input.
    @safe @nogc void poll_events() {
        platform_poll_events();
    }

    /// Waits for, and processes any new window events since the last
    /// `poll_events()` or `wait_events()` call. Either `poll_events()` or
    /// `wait_events()` should be called regularly to ensure the responsiveness
    /// of windows to user input.
    @safe @nogc void wait_events() {
        platform_wait_events();
    }

    version (Windows) {
        import core.sys.windows.windows : HWND;

        /// Windows specific. Retrieves the OS window handle for an open window.
        @safe @nogc HWND get_hwnd(WindowId id)
        in (is_live(id)) {
            return platform_get_hwnd(get(id).platform_data);
        }
    }

private:
    @safe Window* alloc() {
        import core.bitop : bsf;

        // Find first available flag.
        /// bsf finds the first set bit.
        const index = bsf(_bitmap);

        // Clear flag to indicate slot is active.
        _bitmap ^= 1 << index;

        _logger.trace("Creating window. %s of max %s windows active.", num_open_windows, max_open_windows);

        assert(!_windows[index].is_active);
        return _windows[index].activate(cast(ubyte) index);
    }

    @safe @nogc inout(Window*) get(WindowId id) inout pure return  {
        auto id_ = WindowId_(id.value);
        auto window = &_windows[id_.index];
        const generation = WindowId_(window.id.value).generation;

        if (generation == id_.generation)
            return &_windows[id_.index];
        return null;
    }

    @safe void free(WindowId id) {
        auto id_ = WindowId_(id.value);
        _windows[id_.index].deactivate();

        // Set flag to indicate the slot is free.
        _bitmap |= 1 << id_.index;
    }

    Logger* _logger;

    ulong _bitmap = ulong.max;
    Window[max_open_windows] _windows;
}

private:

struct Window {
@safe @nogc pure nothrow private:
    Window* activate(ubyte index) return  {
        auto id_ = cast(WindowId_*)&id;
        id_.index = index;

        is_active = true;
        return &this;
    }

    void deactivate() {
        auto id_ = cast(WindowId_*)&id;
        id_.generation++;

        is_active = false;
    }

    WindowStatus status;
    alias status this;

    PlatformWindowData platform_data;

    bool is_active;
}

union WindowId_ {
    short value;
    struct {
        ubyte index;
        ubyte generation;
    }
}
