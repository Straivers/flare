module flare.vulkan.surfaces;

import flare.vulkan.api;

struct RenderSurface {
    private this(Vulkan* instance, VkSurfaceKHR surface) {
        _vulkan = instance;
        _surface = surface;
    }

    @disable this(this);

    ~this() {
        if (_surface != VK_NULL_HANDLE)
            vkDestroySurfaceKHR(_vulkan.handle, _surface, null);
    }

    @safe @nogc VkSurfaceKHR handle() pure nothrow { return _surface; }

private:
    Vulkan* _vulkan;
    VkSurfaceKHR _surface;
}

version (Windows) {
    import core.sys.windows.windows: HWND, GetModuleHandle, NULL;

    RenderSurface create_surface(ref Vulkan vk, HWND hwnd) {

        VkWin32SurfaceCreateInfoKHR sci = {
            hwnd : hwnd,
            hinstance : GetModuleHandle(NULL)
        };

        VkSurfaceKHR surface;
        auto err = vkCreateWin32SurfaceKHR(vk.handle, &sci, null, &surface);
        if (err == VK_SUCCESS)
            return RenderSurface(&vk, surface);

        vk.log.fatal("Unable to create window surface. Error: %s", err);
        assert(0, "Unable to create window surface");
    }
}
else
    static assert(0, "Unsupported platform.");