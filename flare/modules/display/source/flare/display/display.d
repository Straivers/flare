module flare.display.display;

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
    Windowed,
    Hidden,
    Maximized,
    Minimized,
    // Fullscreen,
}

struct DisplayId {
    ulong value;
}

struct DisplayProperties {
    import flare.renderer.renderer: Renderer;

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
