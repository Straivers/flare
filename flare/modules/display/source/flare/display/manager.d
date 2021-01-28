module flare.display.manager;

import flare.core.memory;
import flare.display.win32;
import flare.renderer.renderer;

public import flare.display.display;

version (Windows)
    import flare.display.win32;

final class DisplayManager {

    enum max_title_length = DisplayProperties.max_title_length;

public:
    this(Allocator allocator) {
        _displays = WeakObjectPool!DisplayImpl(allocator, 64);
    }

    void process_events(bool should_wait = false) {
        _os.process_events(should_wait);
    }

    size_t num_active_displays() {
        return _num_allocated;
    }

    DisplayId create(ref DisplayProperties properties) {
        auto id = _displays.allocate();
        _os.create_window(properties, *_displays.get(id));
        _num_allocated++;
        return id.to!DisplayId;
    }

    void destroy(DisplayId id) {
        _os.destroy_window(_displays.get(Handle.from(id)));
        _displays.deallocate(Handle.from(id));
        _num_allocated--;
    }

    bool is_live(DisplayId id) {
        return _displays.owns(Handle.from(id)) == Ternary.yes;
    }

    bool is_visible(DisplayId id) {
        auto display = _displays.get(Handle.from(id));
        return (display.mode & (DisplayMode.Hidden | DisplayMode.Minimized)) == 0;
    }

    bool is_close_requested(DisplayId id) {
        return _displays.get(Handle.from(id)).is_close_requested;
    }

    void resize(DisplayId id, ushort width, ushort height) {
        _displays.get(Handle.from(id)).resize(width, height);
    }

    void retitle(DisplayId id, in char[] title) {
        _displays.get(Handle.from(id)).retitle(title);
    }

    void change_window_mode(DisplayId id, DisplayMode mode) {
        _displays.get(Handle.from(id)).set_mode(mode);
    }

    SwapchainId get_swapchain(DisplayId id) {
        return _displays.get(Handle.from(id)).swapchain;
    }

private:
    OsWindowManager _os;
    size_t _num_allocated;
    WeakObjectPool!DisplayImpl _displays;

    alias Handle = _displays.Handle;
}
