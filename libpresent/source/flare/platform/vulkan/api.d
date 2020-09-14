module flare.platform.vulkan.api;

import flare.core.logger : Logger;
import flare.core.memory.static_allocator : StaticAllocator;
import core.sys.windows.windows;
public import erupted;
import erupted.platform_extensions;

version (Windows) {
    mixin Platform_Extensions!USE_PLATFORM_WIN32_KHR;
    immutable string[] platform_extensions = [VK_KHR_WIN32_SURFACE_EXTENSION_NAME];
}

immutable string[] extensions = [VK_KHR_SURFACE_EXTENSION_NAME] ~ platform_extensions;

debug
immutable string[] layers = ["VK_LAYER_LUNARG_standard_validation\0"];
else immutable string[] layers = [];

struct VkVersion {
    uint value;
    alias value this;

    uint major() {
        return VK_VERSION_MAJOR(value);
    }

    uint minor() {
        return VK_VERSION_MINOR(value);
    }

    uint patch() {
        return VK_VERSION_PATCH(value);
    }
}

struct Vulkan {
    this(Logger* logger) {
        import erupted.vulkan_lib_loader;

        _logger = Logger(logger.log_level, logger);

        if (!loadGlobalLevelFunctions()) {
            _logger.fatal("Unable to load Vulkan");
            assert(0, "Unable to load Vulkan");
        }

        _is_loaded = true;
        _logger.trace("Loaded Vulkan");

        if (vkEnumerateInstanceVersion)
            vkEnumerateInstanceVersion(&_version.value);
        else
            _version.value = VK_VERSION_1_0;

        VkApplicationInfo ai = {
            pApplicationName: "Flare",
            applicationVersion: VK_MAKE_VERSION(0, 0, 0),
            pEngineName: "Flare Engine",
            engineVersion: VK_MAKE_VERSION(1, 0, 0),
            apiVersion: _version.value
        };

        StaticAllocator!1024 mem;
        auto layers_ = mem.alloc_array!(char*)(layers.length);
        foreach (i, l; layers)
            layers_[i] = cast(char*) l.ptr;

        auto ext_ = mem.alloc_array!(char*)(extensions.length);
        foreach (i, e; extensions)
            ext_[i] = cast(char*) e.ptr;

        VkInstanceCreateInfo ici = {
            pApplicationInfo: &ai,
            enabledLayerCount: cast(uint) layers_.length,
            ppEnabledLayerNames: &layers_[0],
            enabledExtensionCount: cast(uint) ext_.length,
            ppEnabledExtensionNames: &ext_[0]
        };

        if (auto status = vkCreateInstance(&ici, null, &_instance)) {
            _logger.fatal("Could not initialize Vulkan API. Error: %s", status);
            assert(0, "Could not initialize Vulkan API");
        }

        loadInstanceLevelFunctions(_instance);
        _logger.trace("Initialized Vulkan API version %s.%s.%s", _version.major, _version.minor, _version.patch);
    }

    ~this() {
        import erupted.vulkan_lib_loader;

        if (!_is_loaded)
            return;

        if (_instance && vkDestroyInstance)
            vkDestroyInstance(_instance, null);

        _logger.trace("Unloading Vulkan");

        freeVulkanLib();
        _is_loaded = false;
    }

    ref Logger log() return {
        return _logger;
    }

    VkVersion api_version() const {
        return _version;
    }

    VkInstance instance() {
        return _instance;
    }

    VkPhysicalDevice[] load_physical_devices(VkPhysicalDevice[] buffer) {
        uint count;
        auto err = vkEnumeratePhysicalDevices(_instance, &count, null);
        if (err >= VK_SUCCESS) {
            if (count > buffer.length)
                count = cast(uint) buffer.length;

            err = vkEnumeratePhysicalDevices(_instance, &count, &buffer[0]);
            if (err >= VK_SUCCESS) {
                auto devices = buffer[0 .. count];
                _logger.trace("Identified %s Graphics Device%s", devices.length, devices.length > 1 ? "s" : "");
                return devices;
            }
        }

        _logger.fatal("Unable to enumerate physical devices.");
        assert(0, "Unable to enumerate physical devices.");
    }

    VkQueueFamilyProperties[] load_queue_families(VkPhysicalDevice device, VkQueueFamilyProperties[] buffer) {
        uint count;
        vkGetPhysicalDeviceQueueFamilyProperties(device, &count, null);
        vkGetPhysicalDeviceQueueFamilyProperties(device, &count, &buffer[0]);
        return buffer[0 .. count];
    }

private:
    Logger _logger;
    VkInstance _instance;
    VkVersion _version;
    bool _is_loaded;
}

/**
 Filters queue families for specific feature flags.

 Returns: a forward range with an additional `range.index()` property for the queue family's index.
 */
auto filter_features(VkQueueFamilyProperties[] families, VkQueueFlagBits features) {
    struct Range {
        VkQueueFamilyProperties[] families;
        VkQueueFlagBits required_features;
        private size_t _index;

        @safe @nogc pure nothrow:

        // dfmt off
        bool empty()        const { return _index == families.length; }
        size_t index()      const { return _index; }
        ref auto front()    const { return families[_index]; }
        // dfmt on

        void popFront() {
            _index++;

            while (!empty && (families[_index].queueFlags & required_features) == 0)
                _index++;
        }
    }

    return Range(families, features);
}
