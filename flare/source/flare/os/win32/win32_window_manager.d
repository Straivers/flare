module flare.os.win32.win32_window_manager;

version (Windows):

import flare.memory : Allocator, Ternary;
import flare.os.input;
import flare.os.window;
import flare.util.checked_pointer;
import flare.util.handle_pool;

import core.sys.windows.windows;

enum wndclass_name = "flare_window_class_2\0"w;

pragma(lib, "gdi32");

struct Win32Window {
    WindowId id;
    Win32WindowManager manager;

    HWND hwnd;
    WindowState state;
    Callbacks callbacks;
    CheckedVoidPtr user_data;

    CursorIcon cursor_icon;
}

struct WindowCreateInfo {
    Win32Window* window;
    CheckedVoidPtr aux;
}

final class Win32WindowManager : OsWindowManager {
    this(Allocator allocator, InputEventBuffer inputs) nothrow {
        _windows = WindowPool(allocator);
        _inputs = inputs;

        WNDCLASSEXW wc = {
            cbSize: WNDCLASSEXW.sizeof,
            style: CS_OWNDC | CS_VREDRAW | CS_HREDRAW,
            lpfnWndProc: &_window_procedure,
            hInstance: GetModuleHandle(null),
            hCursor: translate(CursorIcon.Pointer),
            hbrBackground: GetStockObject(BLACK_BRUSH),
            lpszClassName: &wndclass_name[0],
        };

        const err = RegisterClassExW(&wc);
        assert(err != 0, "Failed to register window class!");
    }

    ~this() nothrow {
        destroy(_windows);
        UnregisterClass(&wndclass_name[0], GetModuleHandle(null));
    }

    void poll_events() nothrow {
        MSG msg;
        while (PeekMessage(&msg, null, 0, 0, PM_REMOVE) != 0) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
    }

    void wait_events() nothrow {
        WaitMessage();
    }

    size_t num_windows() nothrow {
        return _windows.num_allocated;
    }

    size_t max_windows() nothrow {
        return _windows.num_slots;
    }

    bool is_open(WindowId id) nothrow {
        return _windows.owns(id) == Ternary.yes;
    }

    void* get_os_handle(WindowId id) nothrow {
        return _windows.get(id).hwnd;
    }

    CheckedVoidPtr get_user_data(WindowId id) nothrow {
        return _windows.get(id).user_data;
    }

    void set_user_data(WindowId id, CheckedVoidPtr p) nothrow {
        _windows.get(id).user_data = p;
    }

    WindowId create_window(ref WindowProperties properties) nothrow {
        auto id = _windows.make();
        auto window = _windows.get(id);
        window.id = id;
        window.manager = this;
        window.user_data = properties.user_data;
        window.callbacks = properties.callbacks;

        // TODO: Move to swapchain instead
        window.state.vsync = properties.vsync;

        {
            auto style = WS_OVERLAPPEDWINDOW;
            if (!properties.is_resizable)
                style ^= WS_SIZEBOX;

            RECT rect = {0, 0, properties.width, properties.height};
            AdjustWindowRectEx(&rect, style, FALSE, 0);

            auto ci = WindowCreateInfo(window, properties.aux_data);
            CreateWindowEx(
                    0,
                    wndclass_name.ptr,
                    WCharBuffer(properties.title).ptr,
                    style,
                    CW_USEDEFAULT, CW_USEDEFAULT,
                    rect.right - rect.left, rect.bottom - rect.top,
                    NULL,
                    NULL,
                    GetModuleHandle(null),
                    &ci
            );
            ShowWindow(window.hwnd, SW_SHOWDEFAULT);
        }

        return id;
    }

    void destroy_window(WindowId id) nothrow {
        DestroyWindow(_windows.get(id).hwnd);
    }

    void request_close(WindowId id) nothrow {
        PostMessage(_windows.get(id).hwnd, WM_CLOSE, 0, 0);
    }

    ref const(WindowState) get_state(WindowId id) nothrow {
        return _windows.get(id).state;
    }

    void set_title(WindowId id, const char[] title) nothrow {
        SetWindowText(_windows.get(id).hwnd, WCharBuffer(title).ptr);
    }

    void set_size(WindowId id, ushort width, ushort height) nothrow {
        auto hwnd = _windows.get(id).hwnd;
        RECT rect;
        GetWindowRect(hwnd, &rect);
        MoveWindow(hwnd, rect.left, rect.top, width, height, true);
    }

    void set_mode(WindowId id, WindowMode mode) nothrow {
        ShowWindow(_windows.get(id), translate(mode));
    }

private:
    void _destroy(WindowId id) nothrow {
        _windows.dispose(id);
    }

    WindowPool _windows;
    InputEventBuffer _inputs;
}

private:
alias WindowPool = HandlePool!(Win32Window, display_handle_name, 100);

extern (Windows) LRESULT _window_procedure(HWND hwnd, uint msg, WPARAM wp, LPARAM lp) nothrow {
    if (msg == WM_NCCREATE) {
        auto ci = cast(WindowCreateInfo*)((cast(CREATESTRUCT*) lp).lpCreateParams);
        SetWindowLongPtr(hwnd, GWLP_USERDATA, cast(LONG_PTR) ci.window);

        ci.window.hwnd = hwnd;
        with (ci.window)
            if (callbacks.on_create)
                callbacks.on_create(manager, id, user_data, ci.aux);
        return TRUE;
    }

    auto window = cast(Win32Window*) GetWindowLongPtr(hwnd, GWLP_USERDATA);

    if (!window)
        return DefWindowProc(hwnd, msg, wp, lp);

    with (window) switch (msg) {
    case WM_SIZE: {
            switch (wp) {
            case SIZE_MINIMIZED:
                state.mode = WindowMode.Minimized;
                break;
            case SIZE_MAXIMIZED:
                state.mode = WindowMode.Maximized;
                break;
            default:
                state.mode = WindowMode.Windowed;
                break;
            }

            state.width = LOWORD(lp);
            state.height = HIWORD(lp);
            if (callbacks.on_resize)
                callbacks.on_resize(manager, id, user_data, state.width, state.height);
        }
        return 0;

    case WM_CLOSE:
        state.is_close_requested = true;
        return 0;

    case WM_DESTROY:
        manager._destroy(id);
        if (callbacks.on_destroy)
            callbacks.on_destroy(manager, id, user_data);
        return 0;

    case WM_MOUSEMOVE:
        if (!state.has_cursor) {
            state.has_cursor = true;

            TRACKMOUSEEVENT tme = {
                cbSize: TRACKMOUSEEVENT.sizeof,
                dwFlags: TME_LEAVE | TME_HOVER,
                hwndTrack: window.hwnd,
                dwHoverTime: HOVER_DEFAULT,
            };
            TrackMouseEvent(&tme);
        }
        auto event = InputEvent(id, MousePosition(cast(short) LOWORD(lp), cast(short) HIWORD(lp)));
        manager._inputs.push_event(event);
        return 0;

    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
        auto event = InputEvent(id, KeyState(keycode_table[wp], ButtonState.Pressed));
        manager._inputs.push_event(event);
        return 0;

    case WM_KEYUP:
    case WM_SYSKEYUP:
        auto event = InputEvent(id, KeyState(keycode_table[wp], ButtonState.Released));
        manager._inputs.push_event(event);
        return 0;

    default:
        return DefWindowProc(window.hwnd, msg, wp, lp);
    }
}

HCURSOR translate(CursorIcon icon) nothrow {
    static HCURSOR[16] cursor_icons;
    if (auto i = cursor_icons[icon])
        return i;

    auto ico = () {
        switch (icon) with (CursorIcon) {
            // dfmt off
            case Pointer:                           return IDC_ARROW;
            case Wait:                              return IDC_WAIT;
            case IBeam:                             return IDC_IBEAM;
            case ResizeHorizontal:                  return IDC_SIZEWE;
            case ResizeVertical:                    return IDC_SIZENS;
            case ResizeNorthwestSoutheast:          return IDC_SIZENWSE;
            case ResizeCornerNortheastSouthwest:    return IDC_SIZENESW;
            default:                                assert(false, "Custom Cursor Icons not Implemented.");
            // dfmt on
        }
    } ();
    () @trusted { cursor_icons[icon] = LoadCursor(null, ico); } ();

    return cursor_icons[icon];
}

int translate(WindowMode mode) nothrow {
    final switch (mode) with (WindowMode) {
        // dfmt off
        case Hidden:    return SW_HIDE;
        case Windowed:  return SW_SHOWNORMAL;
        case Minimized: return SW_SHOWMINIMIZED;
        case Maximized: return SW_SHOWMAXIMIZED;
        // dfmt on
    }
}

struct WCharBuffer {
    import flare.util.buffer_writer : TypedWriter;
    import std.utf : byWchar;

nothrow:
    this(in char[] original) {
        auto writer = TypedWriter!wchar(buffer);
        writer.put(original.byWchar());
        writer.put('\0');
    }

    alias buffer this;
    wchar[WindowProperties.max_title_length] buffer;
}

immutable keycode_table = () {
    KeyCode[256] table;

    with (KeyCode) {
        table[0x30] = Num_0;
        table[0x31] = Num_1;
        table[0x32] = Num_2;
        table[0x33] = Num_3;
        table[0x34] = Num_4;
        table[0x35] = Num_5;
        table[0x36] = Num_6;
        table[0x37] = Num_7;
        table[0x38] = Num_8;
        table[0x39] = Num_9;

        table[0x41] = A;
        table[0x42] = B;
        table[0x43] = C;
        table[0x44] = D;
        table[0x45] = E;
        table[0x46] = F;
        table[0x47] = G;
        table[0x48] = H;
        table[0x49] = I;
        table[0x4A] = J;
        table[0x4B] = K;
        table[0x4C] = L;
        table[0x4D] = M;
        table[0x4E] = N;
        table[0x4F] = O;
        table[0x50] = P;
        table[0x51] = Q;
        table[0x52] = R;
        table[0x53] = S;
        table[0x54] = T;
        table[0x55] = U;
        table[0x56] = V;
        table[0x57] = W;
        table[0x58] = X;
        table[0x59] = Y;
        table[0x5A] = Z;

        //Math
        table[VK_OEM_MINUS] = Minus;
        table[VK_OEM_PLUS] = Equal;

        //Brackets
        table[VK_OEM_4] = LeftBracket;
        table[VK_OEM_6] = RightBracket;

        //Grammatical Characters
        table[VK_OEM_5] = BackSlash;
        table[VK_OEM_1] = Semicolon;
        table[VK_OEM_7] = Apostrophe;
        table[VK_OEM_COMMA] = Comma;
        table[VK_OEM_PERIOD] = Period;
        table[VK_OEM_2] = Slash;
        table[VK_OEM_3] = GraveAccent;
        table[VK_SPACE] = Space;
        table[VK_SHIFT] = Shift;

        //Text Control Keys
        table[VK_BACK] = Backspace;
        table[VK_DELETE] = Delete;
        table[VK_INSERT] = Insert;
        table[VK_TAB] = Tab;
        table[VK_RETURN] = Enter;

        //Arrows
        table[VK_LEFT] = Left;
        table[VK_RIGHT] = Right;
        table[VK_UP] = Up;
        table[VK_DOWN] = Down;

        //Locks
        table[VK_CAPITAL] = CapsLock;
        table[VK_SCROLL] = ScrollLock;
        table[VK_NUMLOCK] = NumLock;

        //Auxiliary
        table[VK_SNAPSHOT] = PrintScreen;
        table[VK_MENU] = Alt;

        table[VK_PRIOR] = PageUp;
        table[VK_NEXT] = PageDown;
        table[VK_END] = End;
        table[VK_HOME] = Home;

        table[VK_ESCAPE] = Escape;
        table[VK_CONTROL] = Control;

        //Function Keys
        table[VK_F1] = F1;
        table[VK_F2] = F2;
        table[VK_F3] = F3;
        table[VK_F4] = F4;
        table[VK_F5] = F5;
        table[VK_F6] = F6;
        table[VK_F7] = F7;
        table[VK_F8] = F8;
        table[VK_F9] = F9;
        table[VK_F10] = F10;
        table[VK_F11] = F11;
        table[VK_F12] = F12;
        table[VK_F13] = F13;
        table[VK_F14] = F14;
        table[VK_F15] = F15;
        table[VK_F16] = F16;
        table[VK_F17] = F17;
        table[VK_F18] = F18;
        table[VK_F19] = F19;
        table[VK_F20] = F20;
        table[VK_F21] = F21;
        table[VK_F22] = F22;
        table[VK_F23] = F23;
        table[VK_F24] = F24;

        //Keypad
        table[VK_NUMPAD0] = Keypad_0;
        table[VK_NUMPAD1] = Keypad_1;
        table[VK_NUMPAD2] = Keypad_2;
        table[VK_NUMPAD3] = Keypad_3;
        table[VK_NUMPAD4] = Keypad_4;
        table[VK_NUMPAD5] = Keypad_5;
        table[VK_NUMPAD6] = Keypad_6;
        table[VK_NUMPAD7] = Keypad_7;
        table[VK_NUMPAD8] = Keypad_8;
        table[VK_NUMPAD9] = Keypad_9;

        table[VK_ADD] = Keypad_Add;
        table[VK_SUBTRACT] = Keypad_Subtract;
        table[VK_MULTIPLY] = Keypad_Multiply;
        table[VK_DIVIDE] = Keypad_Divide;
        table[VK_OEM_PLUS] = Keypad_Enter;
    }

    return table;
} ();
