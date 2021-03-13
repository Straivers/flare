module flare.application;

import flare.logger;
import flare.os;
public import flare.memory.measures : kib, mib, gib;
public import flare.memory.allocators;

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
        windows = initialize_window_api(app_settings.main_allocator);
        tick_time = 1.secs / app_settings.tick_frequency;
    }

    ~this() {
        terminate_window_api(app_settings.main_allocator, windows);
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

        windows.poll_events();

        while (windows.num_windows > 0) {
            const current_time = get_time();
            const elapsed_time = current_time - last_time;
            last_time = current_time;
            lag += elapsed_time;

            windows.poll_events();

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
    OsWindowManager windows;
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
