module flare.os.window;

import flare.os.input;
import flare.util.checked_pointer : CheckedVoidPtr;
import flare.util.handle_pool : Handle32;

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

enum WindowMode : ubyte {
    Hidden      = 1 << 0,
    Windowed    = 1 << 1,
    Maximized   = 1 << 2,
    Minimized   = 1 << 3,
    // Fullscreen,
}

bool is_visible(WindowMode mode) {
    return (mode & (WindowMode.Windowed | WindowMode.Maximized)) != 0;
}

enum window_handle_name = "flare_handle32_window_id";
alias WindowId = Handle32!window_handle_name;

struct WindowProperties {
    enum max_title_length = 255;

    const(char)[] title;

    ushort width;
    ushort height;
    bool is_resizable;

    WindowMode mode;
    CursorIcon cursor_icon;

    CheckedVoidPtr user_data;
    CheckedVoidPtr aux_data;
}

struct WindowState {
    WindowMode mode;
    bool vsync;
    bool has_cursor;
    bool is_close_requested;
    ushort width;
    ushort height;
}

interface OsWindowManager {
    /// Processes all events pending since last call.
    void poll_events() nothrow;

    /// Causes the thread to block and wait until the OS event queue has events,
    /// then processes them.
    void wait_events() nothrow;

    /// The number of open windows.
    size_t num_windows() nothrow;

    /// The maximum number of windows that may be open at any time.
    size_t max_windows() nothrow;

    /// Checks if the window exists.
    bool is_open(WindowId) nothrow;

    /// Gets the operating system handle for a window. It is invalid to call
    /// this function with an invalid `WindowId`.
    void* get_os_handle(WindowId) nothrow;

    /// Gets the user-specified pointer associated with the window. It is
    /// invalid to call this function with an invalid `WindowId`.
    CheckedVoidPtr get_user_data(WindowId) nothrow;

    /// Sets the user-specified pointer associated with the window. It is
    /// invalid to call this function with an invalid `WindowId`.
    void set_user_data(WindowId, CheckedVoidPtr) nothrow;

    /// Creates a new window. Failure will crash the program.
    WindowId create_window(ref WindowProperties) nothrow;

    /// Destroys the window. It is invalid to call this function with an invalid
    /// `WindowId`.
    void destroy_window(WindowId) nothrow;

    /// Requests that the window be closed. This simply sets a flag, which may
    /// be retrieved by `get_state(id).is_close_requested`. This is the same
    /// mechanism used when the user clicks the 'X' icon to close a window.
    void request_close(WindowId) nothrow;

    /// Returns a const reference to the window's current state. It is invalid
    /// to call this function with an invalid `WindowId`.
    ref const(WindowState) get_state(WindowId) nothrow;

    /// Sets the window's title. It is invalid to call this function with an
    /// invalid `WindowId`.
    void set_title(WindowId, const char[]) nothrow;

    /// Sets the size of the window's content area. The actual window size may
    /// be larger to support OS decorations. It is invalid to call this function
    /// with an invalid `WindowId`.
    void set_size(WindowId, ushort, ushort) nothrow;

    /// Sets the window mode. It is invalid to call this function with an
    /// invalid `WindowId`.
    void set_mode(WindowId, WindowMode) nothrow;
}
