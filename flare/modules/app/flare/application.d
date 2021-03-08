module flare.application;

import flare.core.logger;
import flare.display.manager;

public import flare.core.memory.measures : kib, mib, gib;
public import flare.core.memory.allocators;

enum uint flare_version_major = 0;
enum uint flare_version_minor = 1;
enum uint flare_version_patch = 0;

struct FlareAppSettings {
    const(char)[] name = "Flare Application";
    ushort main_window_width = 1280;
    ushort main_window_height = 720;
    Allocator main_allocator;
}

abstract class FlareApp {
    this(ref FlareAppSettings settings) {
        log = Logger(LogLevel.All);
        log.add_sink(new ConsoleLogger(true));
        log.all("Flare Engine v%s.%s.%s", flare_version_major, flare_version_minor, flare_version_patch);

        app_settings = settings;
        displays = DisplayManager(&log, memory);
    }

    ~this() {
        destroy(displays);
        destroy(log);
        destroy(memory);
    }

    /**
    Program initialization that may fail. Read files, initialize libraries, and
    the like.
    */
    abstract void on_init();

    abstract void on_shutdown();

    abstract void run();

    pragma(inline, true)
    Allocator memory() {
        return app_settings.main_allocator;
    }

    Logger log;
    FlareAppSettings app_settings;
    DisplayManager displays;
}

void run_app(App: FlareApp)(ref FlareAppSettings settings) {
    auto app = new App(settings);
    app.on_init();
    app.log.info("Entering program loop");
    app.run();
    app.log.info("Shutting down engine");
    app.on_shutdown();
    destroy(app);
}
