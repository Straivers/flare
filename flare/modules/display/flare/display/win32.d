module flare.display.win32;

version (Windows):

import core.sys.windows.windows;
import flare.core.logger : Logger;
import flare.core.os.types : OsWindow;
import flare.display.input;
import flare.display.manager;

pragma(lib, "user32");

immutable wndclass_name = "flare_window_class\0"w;

struct DisplayImpl {
    DisplayManager manager;
    CursorIcon cursor_icon;

    HWND hwnd;
    DisplayId id;

    bool is_close_requested;
    bool has_cursor;

    void set_mode(DisplayMode mode) nothrow {
        ShowWindow(hwnd, translate(mode));
    }

    void resize(ushort width, ushort height) nothrow {
        RECT rect;
        GetWindowRect(hwnd, &rect);
        MoveWindow(hwnd, rect.left, rect.top, width, height, true);
    }

    void retitle(const(char)[] title) nothrow {
        SetWindowText(hwnd, WCharBuffer(title).ptr);
    }
}

struct OsWindowManager {
    OsWindow get_os_handle(ref DisplayImpl impl) nothrow {
        return impl.hwnd;
    }

    void create_window(DisplayManager manager, DisplayId id, ref DisplayProperties properties, out DisplayImpl display) nothrow {
        if (!_registered_wndclass) {
            WNDCLASSEXW wc = {
                cbSize: WNDCLASSEXW.sizeof,
                style: CS_OWNDC | CS_VREDRAW | CS_HREDRAW,
                lpfnWndProc: &window_procedure,
                hInstance: GetModuleHandle(null),
                hCursor: translate(CursorIcon.Pointer),
                lpszClassName: &wndclass_name[0],
            };

            const err = RegisterClassExW(&wc);
            assert(err != 0, "Failed to register window class");

            _registered_wndclass = true;
        }

        auto style = WS_OVERLAPPEDWINDOW;
        if (!properties.is_resizable)
            style ^= WS_SIZEBOX;

        RECT rect = {0, 0, properties.width, properties.height};
        AdjustWindowRectEx(&rect, style, FALSE, 0);

        display.id = id;
        display.manager = manager;
        display.cursor_icon = properties.cursor_icon;

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
            &display
        );
        display.set_mode(properties.mode);
    }

    void close_window(ref DisplayImpl impl) nothrow {
        PostMessage(impl.hwnd, WM_CLOSE, 0, 0);
    }

    void destroy_window(ref DisplayImpl impl) nothrow {
        DestroyWindow(impl.hwnd);
    }

    void process_events(bool should_wait) nothrow {
        static send(ref MSG msg) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }

        MSG msg;
        if (should_wait) {
            const quit = GetMessage(&msg, null, 0, 0);
            send(msg);

            if (quit == 0)
                return;
        }

        while (PeekMessage(&msg, null, 0, 0, PM_REMOVE) != 0)
            send(msg);
    }

    private bool _registered_wndclass;
}

void dispatch(string name, Args...)(DisplayImpl* impl, auto ref Args args) {
    impl.manager.dispatch_event!name(impl.id, args);
}

extern (Windows) LRESULT window_procedure(HWND hwnd, uint msg, WPARAM wp, LPARAM lp) nothrow {
    if (msg == WM_NCCREATE) {
        auto display = cast(DisplayImpl*) ((cast(CREATESTRUCT*) lp).lpCreateParams);
        SetWindowLongPtr(hwnd, GWLP_USERDATA, cast(LONG_PTR) display);

        display.hwnd = hwnd;
        dispatch!"on_create"(display);

        return TRUE;
    }

    auto display = cast(DisplayImpl*) GetWindowLongPtr(hwnd, GWLP_USERDATA);

    if (!display)
        return DefWindowProc(hwnd, msg, wp, lp);

    auto state = &display.manager.get_state(display.id);

    switch (msg) {
    case WM_SIZE: {
            switch (wp) {
            case SIZE_MINIMIZED:
                state.mode = DisplayMode.Minimized;
                break;
            case SIZE_MAXIMIZED:
                state.mode = DisplayMode.Maximized;
                break;
            default:
                state.mode = DisplayMode.Windowed;
                break;
            }

            const width = LOWORD(lp);
            const height = HIWORD(lp);

            dispatch!"on_resize"(display, width, height);
        }
        return 0;

    case WM_CLOSE:
        state.is_close_requested = true;
        return 0;

    case WM_DESTROY:
        dispatch!"on_destroy"(display);
        return 0;

    case WM_MOUSEMOVE:
        if (!display.has_cursor) {
            state.has_cursor = true;

            TRACKMOUSEEVENT tme = {
                cbSize: TRACKMOUSEEVENT.sizeof,
                dwFlags: TME_LEAVE | TME_HOVER,
                hwndTrack: hwnd,
                dwHoverTime: HOVER_DEFAULT,
            };
            TrackMouseEvent(&tme);
        }
        return 0;

    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
        dispatch!"on_key"(display, keycode_table[wp], ButtonState.Pressed);
        return 0;

    case WM_KEYUP:
    case WM_SYSKEYUP:
        dispatch!"on_key"(display, keycode_table[wp], ButtonState.Released);
        return 0;

    default:
        return DefWindowProc(hwnd, msg, wp, lp);
    }
}

HCURSOR translate(CursorIcon icon) nothrow {
    static HCURSOR[16] cursor_icons;
    if (auto i = cursor_icons[icon])
        return i;

    auto ico = () {
        switch (icon) with (CursorIcon) {
            case Pointer:                           return IDC_ARROW;
            case Wait:                              return IDC_WAIT;
            case IBeam:                             return IDC_IBEAM;
            case ResizeHorizontal:                  return IDC_SIZEWE;
            case ResizeVertical:                    return IDC_SIZENS;
            case ResizeNorthwestSoutheast:          return IDC_SIZENWSE;
            case ResizeCornerNortheastSouthwest:    return IDC_SIZENESW;
            default:                                assert(false, "Custom Cursor Icons not Implemented.");
        }
    } ();
    () @trusted { cursor_icons[icon] = LoadCursor(null, ico); } ();

    return cursor_icons[icon];
}

int translate(DisplayMode mode) nothrow {
    final switch (mode) with (DisplayMode) {
        case Hidden: return SW_HIDE;
        case Windowed: return SW_SHOWNORMAL;
        case Minimized: return SW_SHOWMINIMIZED;
        case Maximized: return SW_SHOWMAXIMIZED;
    }
}

struct WCharBuffer {
    import flare.core.buffer_writer: TypedWriter;
    import std.utf : byWchar;

nothrow:
    this(in char[] original) {
        auto writer = TypedWriter!wchar(buffer);
        writer.put(original.byWchar());
        writer.put('\0');
    }

    wchar* ptr() return {
        return &buffer[0];
    }

    wchar[DisplayProperties.max_title_length] buffer;
}

immutable keycode_table = () {
    import flare.display.input: KeyCode;

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
