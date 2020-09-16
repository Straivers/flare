module flare.platform.vulkan.surface;

import flare.platform.vulkan.api;
import flare.presentation.window_manager;

struct RenderSurface {
    private this(Vulkan* instance, VkSurfaceKHR surface) {
        _vulkan = instance;
        _surface = surface;
    }

    @disable this(this);

    ~this() {
        if (_surface != VK_NULL_HANDLE)
            vkDestroySurfaceKHR(_vulkan.instance, _surface, null);
    }

    @safe @nogc VkSurfaceKHR handle() pure nothrow { return _surface; }

private:
    Vulkan* _vulkan;
    VkSurfaceKHR _surface;
}

RenderSurface create_surface(ref Vulkan vk, ref WindowManager wm, WindowId id) {
    version (Windows) {
        import core.sys.windows.windows: GetModuleHandle, NULL;

        VkWin32SurfaceCreateInfoKHR sci = {
            hwnd : wm.get_hwnd(id),
            hinstance : GetModuleHandle(NULL)
        };

        VkSurfaceKHR surface;
        auto err = vkCreateWin32SurfaceKHR(vk.instance, &sci, null, &surface);
        if (err == VK_SUCCESS)
            return RenderSurface(&vk, surface);

        vk.log.fatal("Unable to create window surface. Error: %s", err);
        assert(0, "Unable to create window surface");
    }
    else
        static assert(0, "Unsupported platform.");
}
