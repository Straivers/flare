module flare.display.display;

import flare.core.handle: Handle32;

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

struct DisplayProperties {
    enum max_title_length = 255;

    const(char)[] title;

    ushort width;
    ushort height;
    bool is_resizable;
    DisplayMode mode;
    CursorIcon cursor_icon;

    void* aux_data;
}

struct DisplayState {
    DisplayMode mode;
    bool is_close_requested;
    bool has_cursor;
    ushort width;
    ushort height;
}
