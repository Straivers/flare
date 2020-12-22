module flare.display.manager;

import flare.display.win32;
import flare.renderer.renderer;

public import flare.display.display;
public import flare.core.memory.object_pool: Handle;

final class DisplayManager {
    import flare.core.memory.object_pool: ObjectPool;

    version (Windows)
        import flare.display.win32;

    enum max_title_length = DisplayProperties.max_title_length;

public:
    this() {
        _displays = ObjectPool!(DisplayImpl, 64)(DisplayImpl.init);
    }

    void process_events(bool should_wait = false) {
        _os.process_events(should_wait);
    }

    size_t num_active_displays() {
        return _displays.num_allocated();
    }

    Handle create(ref DisplayProperties properties) {
        auto slot = _displays.alloc();
        _os.create_window(properties, *slot.content);
        return slot.handle;
    }

    void destroy(Handle handle) {
        if (auto slot = _displays.get(handle)) {
            _os.destroy_window(slot);
            _displays.free(handle);
        }
    }

    bool is_live(Handle handle) {
        return _displays.is_valid(handle);
    }

    bool is_visible(Handle handle) {
        if (auto slot = _displays.get(handle)) {
            assert(_displays.is_valid(handle));
            return slot.mode != DisplayMode.Hidden;
        }
        return false;
    }

    bool is_close_requested(Handle handle) {
        if (auto slot = _displays.get(handle))
            return slot.is_close_requested;
        return false;
    }

    void resize(Handle handle, ushort width, ushort height) {
        if (auto slot = _displays.get(handle))
            slot.resize(width, height);
    }

    void retitle(Handle handle, in char[] title) {
        if (auto slot = _displays.get(handle))
            slot.retitle(title);
    }

    void change_window_mode(Handle handle, DisplayMode mode) {
        if (auto slot = _displays.get(handle))
            slot.set_mode(mode);
    }

    SwapchainId get_swapchain(Handle handle) {
        if (auto slot = _displays.get(handle))
            return slot.swapchain;
        return SwapchainId();
    }

private:
    ObjectPool!(DisplayImpl, 64) _displays;
    OsWindowManager _os;
}
