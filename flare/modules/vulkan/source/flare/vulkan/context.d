module flare.vulkan.context;

import flare.core.logger : Logger;
import flare.core.memory;
import flare.vulkan.h;

enum VK_LAYER_LUNARG_API_DUMP_NAME = "VK_LAYER_LUNARG_api_dump";
enum VK_LAYER_KHRONOS_VALIDATION_NAME = "VK_LAYER_KHRONOS_validation";

struct ContextOptions {
    VkVersion api_version;
    Allocator memory;
    Logger* parent_logger;
    const string[] layers;
    const string[] extensions;
}

final class VulkanContext {
    VkInstance instance;
    Allocator memory;
    Logger logger;

    ~this() {
        vkDestroyInstance(instance, null);
    }

private:
    this(Logger* parent_logger, Allocator memory, VkInstance instance) {
        logger = Logger(parent_logger.log_level, parent_logger);
        this.memory = memory;
        this.instance = instance;
    }
}

VulkanContext init_vulkan(ref ContextOptions options) {
    load_vulkan();
    auto instance = create_instance(options);
    if (instance)
        return new VulkanContext(options.parent_logger, options.memory, instance);
    return null;
}

private:

void load_vulkan() {
    import erupted.vulkan_lib_loader: loadGlobalLevelFunctions;

    if (!loadGlobalLevelFunctions())
        assert(0, "Unable to initialize Vulkan");
}

VkInstance create_instance(ref ContextOptions options) {
    import flare.vulkan.compat: to_cstr_array;

    VkApplicationInfo ai = {
        sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,
        pApplicationName: "Flare",
        applicationVersion: VkVersion(0, 0, 0),
        pEngineName: "Flare Engine",
        engineVersion: VkVersion(1, 0, 0),
        apiVersion: options.api_version
    };

    auto mem = scoped_arena(options.memory);
    auto layers = options.layers.to_cstr_array(mem);
    auto extensions = options.extensions.to_cstr_array(mem);

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

    if (result != VK_SUCCESS)
        options.parent_logger.error("Could not create Vulkan instance: %s", result);
    else
        loadInstanceLevelFunctionsExt(instance);
    
    options.parent_logger.info("Vulkan instance created with:\n\tLayers:%-( %s%)\n\tExtensions:%-( %s%)", options.layers, options.extensions);

    return instance;
}
