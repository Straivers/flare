module app;

import sandbox;
import flare.application;

void main() {
    FlareAppSettings settings = {
        name: "Flare Sandbox",
        main_window_width: 1920,
        main_window_height: 1080
    };

    run_app!Sandbox(settings);
}
