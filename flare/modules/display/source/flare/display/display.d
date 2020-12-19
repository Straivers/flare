module flare.display.display;

import flare.display.display;
import flare.display.input;
import flare.renderer.renderer;

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

struct DisplayId {
    ulong value;
}

enum DisplayMode {
    Hidden,
    Windowed,
    Maximized,
    Minimized,
    // Fullscreen,
}

struct DisplayProperties {
    enum max_title_length = 255;

    const(char)[] title;

    ushort width;
    ushort height;
    bool is_resizable;
    DisplayMode mode;
    Renderer renderer;

    void* user_data;
    CursorIcon cursor_icon;
}

struct DisplayCallbacks {
    import flare.display.display_manager: DisplayManager;

@safe @nogc nothrow:
    /// Callback for key events.
    void function(DisplayManager, DisplayId, KeyCode, ButtonState) on_key;
    /// Callback for mouse button events.
    void function(DisplayManager, DisplayId, MouseButton, ButtonState) on_mouse_button;

    /// Callback for mouse wheel scroll events.
    void function(DisplayManager, DisplayId, int) on_scroll;
    /// Callback for cursor movement events.
    void function(DisplayManager, DisplayId, short, short) on_cursor_move;
    /// Callback for when the cursor leaves the window.
    void function(DisplayManager, DisplayId) on_cursor_exit;
    /// Callback for when the cursor enters the window.
    void function(DisplayManager, DisplayId, short, short) on_cursor_enter;

    /// Callback for when the display is created.
    void function(DisplayManager, DisplayId) on_create;
    /// Callback for when the user has clicked the 'X' to close the window.
    void function(DisplayManager, DisplayId) on_close_request;
    /// Callback for resizing the window.
    void function(DisplayManager, DisplayId, short, short) on_resize;
    /// Callback for just before the window is destroyed. Window destruction is
    /// inevitable at this point, and cannot be aborted.
    void function(DisplayManager, DisplayId) on_destroy;
}
