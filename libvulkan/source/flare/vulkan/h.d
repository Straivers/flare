module flare.vulkan.h;

import erupted;
import erupted.platform_extensions;
import flare.core.logger : Logger;
import flare.core.memory.static_allocator : scoped_mem;

version (Windows) {
    import core.sys.windows.windows;

    mixin Platform_Extensions!USE_PLATFORM_WIN32_KHR;
    immutable string[] platform_extensions = [VK_KHR_WIN32_SURFACE_EXTENSION_NAME];
}

immutable string[] extensions = [VK_KHR_SURFACE_EXTENSION_NAME] ~ platform_extensions;

debug
immutable string[] layers = ["VK_LAYER_LUNARG_standard_validation\0"];
else immutable string[] layers = [];

struct VkVersion {
    @safe @nogc pure nothrow:

    uint value;
    alias value this;

    @trusted uint major() const {
        return VK_VERSION_MAJOR(value);
    }

    @trusted uint minor() const {
        return VK_VERSION_MINOR(value);
    }

    @trusted uint patch() const {
        return VK_VERSION_PATCH(value);
    }
}

struct Vulkan {
@safe nothrow:

    @trusted this(Logger* logger) {
        import erupted.vulkan_lib_loader: loadGlobalLevelFunctions;

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

        auto mem = scoped_mem!1024();
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

    @trusted ~this() {
        import erupted.vulkan_lib_loader: freeVulkanLib;

        if (!_is_loaded)
            return;

        if (_instance && vkDestroyInstance)
            vkDestroyInstance(_instance, null);

        _logger.trace("Unloading Vulkan");

        freeVulkanLib();
        _is_loaded = false;
    }

    ref Logger log() return{
        return _logger;
    }

    VkVersion api_version() const pure {
        return _version;
    }

    VkInstance handle() pure {
        return _instance;
    }

private:
    Logger _logger;
    VkInstance _instance;
    VkVersion _version;
    bool _is_loaded;
}
