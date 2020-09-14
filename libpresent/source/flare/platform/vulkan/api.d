module flare.platform.vulkan.api;

import flare.core.logger : Logger;
import flare.core.memory.measures : kib;
import flare.core.memory.static_allocator : StaticAllocator;
import core.sys.windows.windows;
import erupted;
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

        auto dev = select_physical_device(this);
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

private:
    Logger _logger;
    VkInstance _instance;
    VkVersion _version;
    bool _is_loaded;
}

private:

VkPhysicalDevice select_physical_device(ref Vulkan vulkan) {
    enum max_physical_devices = 64;
    StaticAllocator!(VkPhysicalDevice.sizeof * max_physical_devices) mem;
    
    auto devices = () {
        uint count;
        auto err = vkEnumeratePhysicalDevices(vulkan.instance, &count, null);
        if (err >= VK_SUCCESS) {
            if (count > max_physical_devices)
                count = max_physical_devices;

            auto devices = mem.alloc_array!VkPhysicalDevice(count);
            err = vkEnumeratePhysicalDevices(vulkan.instance, &count, &devices[0]);
            if (err >= VK_SUCCESS)
                return devices;
        }

        vulkan.log.fatal("Unable to enumerate physical devices.");
        assert(0, "Unable to enumerate physical devices.");
    } ();

    vulkan.log.trace("Identified %s Graphics Device%s", devices.length, devices.length > 1 ? "s" : "");

    auto device = devices[0];
    VkPhysicalDeviceProperties properties;
    vkGetPhysicalDeviceProperties(device, &properties);

    int length;
    for (; properties.deviceName[length] != '\0'; length++) {}

    auto driver_version = VkVersion(properties.driverVersion);

    vulkan.log.trace("Selected GPU: %s v%s.%s.%s", properties.deviceName[0 .. length], driver_version.major, driver_version.minor, driver_version.patch);
    return device;
}
