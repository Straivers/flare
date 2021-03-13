module flare.os.api;

import flare.memory : Allocator, make, dispose;
import flare.os.window;
import flare.os.time;

struct OsApi {
    OsWindowManager windows;
    OsClock clock;
}

void initialize_os_api(Allocator allocator, out OsApi api) {
    version (Windows) {
        import flare.os.win32.win32_time : Win32Clock;
        import flare.os.win32.win32_window_manager : Win32WindowManager;

        api.clock = allocator.make!Win32Clock();
        api.windows = allocator.make!Win32WindowManager(allocator);
    }
    else static assert(0, "Unsupported OS");
}

void terminate_os_api(Allocator allocator, ref OsApi api) {
    allocator.dispose(api.windows);
    allocator.dispose(api.clock);
}
