module flare.presentation.renderer;

import flare.presentation.window_manager;

struct WindowOutputId {
    short value;
}

interface Renderer {
    WindowOutputId add_render_output(WindowManager wmg, WindowId id);

    void resize_render_output(WindowOutputId, ushort new_width, ushort new_height);

    WindowOutputId remove_render_output();
}
