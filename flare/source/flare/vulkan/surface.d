module flare.vulkan.surface;

import flare.vulkan.h;
import flare.vulkan.context;

final class RenderSurface {
    VulkanContext context;

    ~this() {
        vkDestroySurfaceKHR(context.instance, handle, null);
    }

    VkSurfaceKHR handle() const {
        return cast(VkSurfaceKHR) _handle;
    }

private:
    const VkSurfaceKHR _handle;

    this(VulkanContext ctx, VkSurfaceKHR handle) {
        context = ctx;
        _handle = handle;
    }
}

version (Windows) {
    import core.sys.windows.windows : HWND, GetModuleHandle, NULL;

    RenderSurface create_surface(ref return VulkanContext ctx, HWND window) {
        VkWin32SurfaceCreateInfoKHR sci = {hwnd: window,
        hinstance: GetModuleHandle(NULL)};

        VkSurfaceKHR handle;
        auto err = vkCreateWin32SurfaceKHR(ctx.instance, &sci, null, &handle);
        if (err == VK_SUCCESS) {
            return new RenderSurface(ctx, handle);
        }

        ctx.logger.fatal("Unable to create window surface: %s", err);
        assert(0, "Unable to create window surface.");
    }
}
