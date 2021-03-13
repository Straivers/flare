module flare.application;

import flare.core.logger;
import flare.core.time;
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
    double tick_frequency = 50;
    Allocator main_allocator;
}

abstract class FlareApp {
    this(ref FlareAppSettings settings) {
        log = Logger(LogLevel.All);
        log.add_sink(new ConsoleLogger(true));
        log.all("Flare Engine v%s.%s.%s", flare_version_major, flare_version_minor, flare_version_patch);

        app_settings = settings;
        displays = DisplayManager(&log, memory);
        tick_time = 1.secs / app_settings.tick_frequency;
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

    abstract void on_update(Duration dt);

    abstract void on_draw(Duration dt);

    void run() {
        auto last_time = get_time();
        Duration lag;

        while (displays.num_active_displays > 0) {
            const current_time = get_time();
            const elapsed_time = current_time - last_time;
            last_time = current_time;
            lag += elapsed_time;

            displays.process_events();

            while (lag >= tick_time) {
                on_update(tick_time);
                lag -= tick_time;
            }

            on_draw(elapsed_time);
        }
    }

    pragma(inline, true)
    Allocator memory() {
        return app_settings.main_allocator;
    }

    Logger log;
    FlareAppSettings app_settings;
    DisplayManager displays;
    Duration tick_time;
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
