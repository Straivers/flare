module app;

import sandbox;
import flare.application;

void main() {
    FlareAppSettings settings = {
        name: "Flare Sandbox"
    };

    run_app!Sandbox(settings);
}
