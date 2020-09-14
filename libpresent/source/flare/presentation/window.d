module flare.presentation.window;

import flare.presentation.input: WindowCallbacks;

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

///
enum WindowMode : ubyte {
    Windowed,
    Maximized,
    Minimized,
    Hidden
}

/// Configuration settings for a window. Set these, then call
/// `WindowManager.create_window(settings)` to create a new window with these
/// settings.
struct WindowSettings {
    /// The maximum length of the name of the window, in UTF-8 chars.
    enum max_title_length = 256;

    /// The title of the new window.
    const char[] title;

    /// The size of the usable area of the window. Some platforms have a 'grab
    /// border' around their windows that take up extra space, so the actual
    /// window may be slightly larger than specified. However, those extra
    /// pixels are not interactible from a programmer's perspective.
    ushort inner_width;
    
    /// ditto
    ushort inner_height;
    
    /// If the window can be resized by the user.
    bool is_resizable;

    /// User-defined data. The WindowManager will not modify the contents of
    /// this pointer.
    void* user_data;

    /// The initial window mode for this window. This can be changed at any time
    /// during the window's lifetime.
    WindowMode mode;

    /// The initial cursor icon for this window. This can be changed at any time
    /// during the window's lifetime.
    CursorIcon cursor_icon;

    /// Callbacks for any events generated by the window. This includes input
    /// events while the window is in focus, as well as events that may be
    /// generated as a consequence of calling functions from the window manager.
    WindowCallbacks callbacks;
}

/// A unique identifier for a window. This is the primary way for interacting
/// with specific windows through the window manager.
struct WindowId {
    package short value;
}

/// The `WindowStatus` describes the state of a window at a moment in time.
struct WindowStatus {
    /// A pointer to user-specified per-window data.
    void* user_data;
    /// The unique identifier of this window.
    WindowId id;
    /// The width of the window's usable area.
    ushort inner_width;
    /// The height of the window's usable area.
    ushort inner_height;
    /// If the cursor is currently within the window's bounds.
    bool has_cursor;
    /// If the user has requested that the window be closed (ie. by clicking the
    /// 'X') or if `window_manager.send_close_request(id)` has been called on
    /// this window.
    bool is_close_requested;
    /// The current cursor icon.
    CursorIcon cursor_icon;
    /// The callbacks that are currently active for this window.
    WindowCallbacks callbacks;
}
