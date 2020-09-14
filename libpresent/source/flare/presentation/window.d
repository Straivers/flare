module flare.presentation.window;

import flare.presentation.input: WindowCallbacks;

// per-window data [user][internal]
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
    Windowed,
    Maximized,
    Minimized,
    Hidden
}

struct WindowSettings {
    enum max_title_length = 256;

    const char[] title;
    ushort inner_width;
    ushort inner_height;
    bool is_resizable;
    void* user_data;
    WindowMode mode;
    CursorIcon cursor_icon;
    WindowCallbacks callbacks;
}

struct WindowId {
    short value;
}

struct WindowStatus {
    void* user_data;
    WindowId id;
    ushort inner_width;
    ushort inner_height;
    bool has_cursor;
    bool is_close_requested;
    CursorIcon cursor_icon;
    WindowCallbacks callbacks;
}
