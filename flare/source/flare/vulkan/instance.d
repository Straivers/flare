module flare.vulkan.instance;

import flare.core.logger: Logger;
import flare.core.memory.temp;
import flare.vulkan.base;
import flare.vulkan.compat;

struct InstanceOptions {
    VkVersion api_version;
    const string[] layers;
    const string[] extensions;
    Logger* parent_logger;
}

struct Vulkan {
    @disable this();

    ~this() {
        if (is_valid) {
            vkDestroyInstance(_instance, null);
            this = Vulkan.init;
        }
    }

    bool is_valid() { return _instance !is null; }

private:
    this(VkInstance i, VkVersion ver, Logger* log) {
        _instance = i;
        _version = ver;
        _logger = log;
    }

    VkInstance _instance;
    VkVersion _version;
    Logger* _logger;
}

Vulkan init_instance(InstanceOptions options) {
    load_vulkan();

    VkApplicationInfo ai = {
        sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,
        pApplicationName: "Flare",
        applicationVersion: VkVersion(0, 0, 0),
        pEngineName: "Flare Engine",
        engineVersion: VkVersion(1, 0, 0),
        apiVersion: options.api_version
    };

    auto layers = options.layers.to_cstr_array();
    auto extensions = options.extensions.to_cstr_array();

    VkInstanceCreateInfo ici = {
        sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        pApplicationInfo: &ai,
        enabledLayerCount: cast(uint) layers.length,
        ppEnabledLayerNames: layers.ptr,
        enabledExtensionCount: cast(uint) extensions.length,
        ppEnabledExtensionNames: extensions.ptr
    };

    VkInstance instance;
    const result = vkCreateInstance(&ici, null, &instance);

    layers.free();
    extensions.free();

    if (result == VK_SUCCESS)
        load_instance_api(instance);

    return Vulkan(instance, options.api_version, options.parent_logger);
}
