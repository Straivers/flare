module flare.vulkan.instance;

import flare.core.logger : Logger;
import flare.core.memory.temp;
import flare.vulkan.base;
import flare.vulkan.compat;

struct InstanceOptions {
    VkVersion api_version;
    const string[] layers;
    const string[] extensions;
    Logger* parent_logger;
}

VkInstance init_instance(InstanceOptions options) {
    load_vulkan();

    VkApplicationInfo ai = {
        sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,
        pApplicationName: "Flare",
        applicationVersion: VkVersion(0, 0, 0),
        pEngineName: "Flare Engine",
        engineVersion: VkVersion(1, 0, 0),
        apiVersion: options.api_version
    };

    auto layers_ = options.layers.to_cstr_array();
    auto ext_ = options.extensions.to_cstr_array();

    VkInstanceCreateInfo ici = {
        sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        pApplicationInfo: &ai,
        enabledLayerCount: cast(uint) layers_.length,
        ppEnabledLayerNames: &layers_[0],
        enabledExtensionCount: cast(uint) ext_.length,
        ppEnabledExtensionNames: &ext_[0]
    };

    VkInstance instance;
    vkCreateInstance(&ici, null, &instance);

    tmp_free(layers_.memory);
    tmp_free(ext_.memory);

    return instance;
}

// struct Vulkan {
//     static void load(Logger* for_errors) {
//         load_vulkan(for_errors);
//     }

//     static Vulkan create_instance(InstanceOptions options) {
//         VkApplicationInfo ai = {
//             sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,
//             pApplicationName: "Flare",
//             applicationVersion: VkVersion(0, 0, 0),
//             pEngineName: "Flare Engine",
//             engineVersion: VkVersion(1, 0, 0),
//             apiVersion: options.api_version
//         };

//         auto layers_ = options.layers.to_cstr_array();
//         auto ext_ = options.extensions.to_cstr_array();

//         VkInstanceCreateInfo ici = {
//             sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
//             pApplicationInfo: &ai,
//             enabledLayerCount: cast(uint) layers_.length,
//             ppEnabledLayerNames: &layers_[0],
//             enabledExtensionCount: cast(uint) ext_.length,
//             ppEnabledExtensionNames: &ext_[0]
//         };

//         VkInstance instance;
//         vkCreateInstance(&ici, null, &instance);

//         tmp_free(layers_.memory);
//         tmp_free(ext_.memory);

//         return Vulkan(instance, options.api_version, options.parent_logger);
//     }

// public:
//     @disable this(this);

//     ~this() {
//         DestroyInstance(_instance, null);
//     }

//     /// Accesses the Vulkan-specific logger.
//     ref Logger log() return  {
//         return _logger;
//     }

//     VkVersion api_version() {
//         return _version;
//     }

//     VkInstance handle() {
//         return _instance;
//     }

//     PhysicalDevice[] get_physical_devices() {
//         void error() {
//             _logger.fatal("Unable to enumerate physical devices.");
//             assert(0, "Unable to enumerate physical devices.");
//         }

//         uint count;
//         if (EnumeratePhysicalDevices(_instance, &count, null) < VK_SUCCESS)
//             error();

//         auto array = tmp_array!VkPhysicalDevice(count);
//         // auto array = _scratch.allocate_array!VkPhysicalDevice(count);
//         if (EnumeratePhysicalDevices(_instance, &count, array.ptr) < VK_SUCCESS)
//             error();

//         auto storage = tmp_array!PhysicalDevice(count);
//         foreach (i, d; array)
//             storage[i] = PhysicalDevice(this, d);

//         return storage;
//     }

// private:
//     this(VkInstance instance, VkVersion api_version, Logger* parent_logger) {
//         _instance = instance;
//         _version = api_version;
//         _logger = Logger(parent_logger.log_level, parent_logger);

//         load_instance_api(_instance);
//     }

//     Logger _logger;
//     VkInstance _instance;
//     VkVersion _version;
// }
