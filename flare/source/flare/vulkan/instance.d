module flare.vulkan.instance;

import flare.core.logger: Logger;
import flare.core.memory.api;
import flare.core.memory.temp;
import flare.vulkan.base;

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

    VkPhysicalDevice[] get_physical_devices(Allocator allocator) in(is_valid) {
        uint count;
        if (vkEnumeratePhysicalDevices(_instance, &count, null) >= VK_SUCCESS) {
            auto result = allocator.alloc_arr!VkPhysicalDevice(count);
            
            if (result && vkEnumeratePhysicalDevices(_instance, &count, result.ptr) >= VK_SUCCESS) {
                _logger.trace("Identified %s Graphics Device%s", count, count > 1 ? "s" : "");
                return result;
            }
        }

        _logger.fatal("Unable to enumerate physical devices.");
        assert(0, "Unable to enumerate physical devices.");
    }

private:
    VkInstance _instance;
    Logger _logger;
}
