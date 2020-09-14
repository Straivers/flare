module sandbox.app;

import flare.core.logger;
import flare.presentation.window;
import flare.presentation.window_manager;

void main() {
    auto logger = Logger(LogLevel.All);
    logger.add_sink(new ConsoleLogger(true));

    auto wm = WindowManager(&logger);

    WindowId[1] ws;
    logger.trace("Creating %s windows", ws.length);
    foreach (ref w; ws)
        w = wm.make_window(WindowSettings("Title", 1280, 720, true));

    while (wm.num_open_windows > 0) {
        wm.wait_events();
        wm.destroy_closed_windows();
    }
}
