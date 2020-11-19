module flare.vulkan.instance;

import flare.core.logger: Logger;
import flare.core.memory.api;
import flare.core.memory.temp;
import flare.vulkan.base;
import flare.vulkan.device;
import flare.vulkan.surface;
import flare.vulkan.h;

struct InstanceOptions {
    VkVersion api_version;
    const string[] layers;
    const string[] extensions;
}

struct Vulkan {
    this(Logger* parent_logger, VkInstance instance) {
        _logger = Logger(parent_logger.log_level, parent_logger);
        _instance = instance;
    }

    ~this() {
        if (is_valid) {
            vkDestroyInstance(_instance, null);
            _instance = null;
            _logger = Logger.init;
        }
    }

    @disable this(this);

    bool is_valid() { return _instance !is null; }

    VkInstance handle() { return _instance; }

    ref Logger log() return { return _logger; }

    VkPhysicalDevice[] get_physical_devices(Allocator mem) {
        return flare.vulkan.device.get_physical_devices(this, mem);
    }

    VkQueueFamilyProperties[] get_queue_families(VkPhysicalDevice device, Allocator mem) {
        return flare.vulkan.device.get_queue_families(this, device, mem);
    }

    VkDevice create_logical_device(VkPhysicalDevice physical_device, VkDeviceQueueCreateInfo[] queues, ref VkPhysicalDeviceFeatures features) {
        return flare.vulkan.device.create_logical_device(this, physical_device, queues, features);
    }

    version (Windows) {
        import core.sys.windows.windows: HWND;

        RenderSurface create_surface(HWND hwnd) return {
            return create_surface_win32(this, hwnd);
        }
    }

    bool can_device_render_to(VkPhysicalDevice device, ref RenderSurface surface, uint with_queue_family) {
        return flare.vulkan.surface.can_device_render_to(this, device, surface, with_queue_family);
    }

private:
    VkInstance _instance;
    Logger _logger;
}
