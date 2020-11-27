module flare.application;

import flare.display.window_manager;
import flare.core.logger;

struct FlareAppSettings {
    string name = "Flare Application";
}

abstract class FlareApp {
    this(ref FlareAppSettings settings) {
        log = Logger(LogLevel.All);
        log.add_sink(new ConsoleLogger(true));

        window_manager = WindowManager(&log);
        main_window = window_manager.make_window(WindowSettings(settings.name, 1280, 720, false, null));
    }

    ~this() {
        if (window_manager.is_live(main_window))
            window_manager.destroy_window(main_window);
    }

    abstract void on_init();

    abstract void on_shutdown();

    abstract void run();

    Logger log;
    WindowManager window_manager;
    WindowId main_window;
}

void run_app(App: FlareApp)(ref FlareAppSettings settings) {
    auto app = new App(settings);
    app.on_init();
    app.run();
    app.on_shutdown();
    destroy(app);
}
