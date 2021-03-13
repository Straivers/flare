module flare.os.window;

import flare.os.input;
import flare.os.window_manager;
import flare.util.checked_pointer : CheckedVoidPtr;
import flare.util.handle : Handle32;

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

enum display_handle_name = "flare_handle32_display_id";
alias WindowId = Handle32!display_handle_name;

struct WindowProperties {
    enum max_title_length = 255;

    const(char)[] title;

    ushort width;
    ushort height;
    bool is_resizable;
    bool vsync;
    WindowMode mode;
    CursorIcon cursor_icon;

    Callbacks callbacks;

    CheckedVoidPtr user_data;
    CheckedVoidPtr aux_data;
}

alias OnCreate = void function(WindowManager*, WindowId, CheckedVoidPtr user_data, CheckedVoidPtr aux_data) nothrow;
alias OnClose = void function(WindowManager*, WindowId, CheckedVoidPtr user_data) nothrow;
alias OnDestroy = void function(WindowManager*, WindowId, CheckedVoidPtr user_data) nothrow;

alias OnResize = void function(WindowManager*, WindowId, CheckedVoidPtr user_data, ushort width, ushort height) nothrow;
alias OnKey = void function(WindowManager*, WindowId, CheckedVoidPtr user_data, KeyCode, ButtonState) nothrow;

struct Callbacks {
    /*
    NOTE:
        To add a new callback:
            1) Create a new alias type for the callback function.
            2) Add a pointer of that type to the `Callbacks` struct called `$callback_name$`.
            3) Add a handler called `_$callback_name$(WindowId, Args...)`.
            4) Add a delegate of the same type to `ImplCallbacks` for each OS implementation.
            5) Add a case in the OS layer to call the delegate callback.
            6) Add `WindowManager._$callback_name$(WindowId, Args...)` to the impl callbacks.
            5) Update any sublcasses that need to make use of the callback.
    */

    /**
    Callback called during window creation. This callback will be called after
    the window has been created, and before the window is visible.
    */
    OnCreate on_create;

    /**
    Callback called when a user presses the `x` to close a window, or when
    `WindowManager.close()` is called.
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

struct WindowState {
    WindowMode mode;
    bool vsync;
    bool has_cursor;
    bool is_close_requested;
    ushort width;
    ushort height;
}