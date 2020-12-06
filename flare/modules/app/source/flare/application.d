module flare.application;

import flare.display.window_manager;
import flare.core.logger;

enum uint flare_version_major = 0;
enum uint flare_version_minor = 1;
enum uint flare_version_patch = 0;

struct FlareAppSettings {
    string name = "Flare Application";
    ushort main_window_width = 1280;
    ushort main_window_height = 720;
}

abstract class FlareApp {
    this(ref FlareAppSettings settings) {
        log = Logger(LogLevel.All);
        log.add_sink(new ConsoleLogger(true));
        log.all("Flare Engine v%s.%s.%s", flare_version_major, flare_version_minor, flare_version_patch);

        app_settings = settings;

        window_manager = WindowManager(&log);
    }

    ~this() {
    }

    abstract void on_init();

    abstract void on_shutdown();

    abstract void run();

    Logger log;
    WindowManager window_manager;
    FlareAppSettings app_settings;
}

void run_app(App: FlareApp)(ref FlareAppSettings settings) {
    auto app = new App(settings);
    app.on_init();
    app.log.info("Entering program loop");
    app.run();
    app.log.info("Shutting down engine");
    app.on_shutdown();
    // destroy(app);
}
