module flare.os.win32.win32_window_manager;

import flare.util.checked_pointer;
import flare.os.window;
import flare.os.input;

struct Win32Window {
    WindowId id;

    HWND hwnd;
    WindowState state;
    Callbacks callbacks;
    CheckedVoidPtr user_data;

    CursorIcon cursor_icon;
}

final class Win32WindowManager : OsWindowManager {
    void poll_events() {
        assert(0, "Not Implemented");
    }

    void wait_events() {
        assert(0, "Not Implemented");
    }

    size_t num_windows() {
        assert(0, "Not Implemented");
    }

    size_t max_windows() {
        assert(0, "Not Implemented");
    }

    bool is_open(WindowId) {
        assert(0, "Not Implemented");
    }

    void* get_os_handle(WindowId) {
        assert(0, "Not Implemented");
    }

    CheckedVoidPtr get_user_data(WindowId) {
        assert(0, "Not Implemented");
    }

    void set_user_data(WindowId, CheckedVoidPtr) {
        assert(0, "Not Implemented");
    }

    WindowId create_window(ref WindowProperties) {
        assert(0, "Not Implemented");
    }

    void destroy_window(WindowId) {
        assert(0, "Not Implemented");
    }

    void request_close(WindowId) {
        assert(0, "Not Implemented");
    }

    ref const(WindowState) get_state(WindowId) {
        assert(0, "Not Implemented");
    }

    void set_title(WindowId, const char[]) {
        assert(0, "Not Implemented");
    }

    void set_size(WindowId, ushort, ushort) {
        assert(0, "Not Implemented");
    }

    void set_mode(WindowId, WindowMode) {
        assert(0, "Not Implemented");
    }
}
