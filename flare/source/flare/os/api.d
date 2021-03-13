module flare.os.api;

import flare.memory : Allocator, make, dispose;
import flare.os.window;
import flare.os.time;
import flare.os.input;

struct OsApi {
    OsClock clock;
    OsWindowManager windows;
    InputEventBuffer input_events;
}

void initialize_os_api(Allocator allocator, out OsApi api) {
    version (Windows) {
        import flare.os.win32.win32_time : Win32Clock;
        import flare.os.win32.win32_window_manager : Win32WindowManager;
        import flare.os.input : InputEventBuffer;

        auto inputs = allocator.make!InputEventBuffer();

        api.clock = allocator.make!Win32Clock();
        api.windows = allocator.make!Win32WindowManager(allocator, inputs);
        api.input_events = inputs;
    }
    else static assert(0, "Unsupported OS");
}

void terminate_os_api(Allocator allocator, ref OsApi api) {
    allocator.dispose(api.clock);
    allocator.dispose(api.windows);
    allocator.dispose(api.input_events);
}
