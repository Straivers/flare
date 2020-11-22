module flare.vulkan.surface;

import flare.vulkan.h;
import flare.vulkan.instance;

final class RenderSurface {
    const Vulkan instance;

    ~this() {
        vkDestroySurfaceKHR(instance.handle, handle, null);
    }

    VkSurfaceKHR handle() const {
        return cast(VkSurfaceKHR) _handle;
    }

private:
    const VkSurfaceKHR _handle;

    this(Vulkan instance, VkSurfaceKHR handle) {
        this.instance = instance;
        _handle = handle;
    }
}

bool can_device_render_to(ref Vulkan instance, VkPhysicalDevice device, ref RenderSurface surface, uint queue_family) {
    VkBool32 result;
    const err = vkGetPhysicalDeviceSurfaceSupportKHR(device, queue_family, surface.handle, &result);
    if (err == VK_SUCCESS)
        return result != 0;

    instance.log.fatal("Call to vkGetPhysicalDeviceSurfaceSupportKHR failed: %s", result);
    assert(0, "Call to vkGetPhysicalDeviceSurfaceSupportKHR failed");
}

version (Windows) {
    import core.sys.windows.windows : HWND, GetModuleHandle, NULL;

    RenderSurface create_surface(ref return Vulkan instance, HWND window) {
        VkWin32SurfaceCreateInfoKHR sci = {hwnd: window,
        hinstance: GetModuleHandle(NULL)};

        VkSurfaceKHR handle;
        auto err = vkCreateWin32SurfaceKHR(instance.handle, &sci, null, &handle);
        if (err == VK_SUCCESS) {
            return new RenderSurface(instance, handle);
        }

        instance.log.fatal("Unable to create window surface: %s", err);
        assert(0, "Unable to create window surface.");
    }
}
