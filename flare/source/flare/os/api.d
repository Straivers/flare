module flare.os.api;

import flare.memory : Allocator, make, dispose;
import flare.os.window;


OsWindowManager initialize_window_api(Allocator allocator) {
    version (Windows) {
        import flare.os.win32.win32_window_manager : Win32WindowManager;

        return allocator.make!Win32WindowManager(allocator);
    }
}

void terminate_window_api(Allocator allocator, OsWindowManager windows) {
    allocator.dispose(windows);
}
