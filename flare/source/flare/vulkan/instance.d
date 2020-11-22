module flare.vulkan.instance;

import flare.core.logger : Logger;
import flare.core.memory.api;
import flare.core.memory.temp;
import flare.vulkan.base;
import flare.vulkan.device;
import flare.vulkan.h;
import flare.vulkan.surface;

struct InstanceOptions {
    VkVersion api_version;
    const string[] layers;
    const string[] extensions;
}

final class Vulkan {
    this(Logger* parent_logger, VkInstance instance) {
        _logger = Logger(parent_logger.log_level, parent_logger);
        _handle = instance;
    }

    ~this() {
        vkDestroyInstance(handle, null);
    }

    VkInstance handle() const {
        return cast(VkInstance) _handle;
    }

    ref Logger log() return  {
        return _logger;
    }

private:
    VkInstance _handle;
    Logger _logger;
}
