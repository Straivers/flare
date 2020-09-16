module flare.platform.vulkan.api;

public import erupted;
import erupted.platform_extensions;
import flare.core.logger : Logger;
import flare.core.memory.static_allocator : scoped_mem;
import flare.platform.vulkan.surface;

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

    VkInstance instance() pure {
        return _instance;
    }

    @trusted PhysicalDevice[] load_physical_devices(PhysicalDevice[] buffer) {
        uint count;
        auto err = vkEnumeratePhysicalDevices(_instance, &count, null);
        if (err >= VK_SUCCESS) {
            if (count > buffer.length)
                count = cast(uint) buffer.length;

            auto mem = scoped_mem!(PhysicalDevice.sizeof * 32);
            auto tmp_buff = mem.alloc_array!VkPhysicalDevice(count);
            err = vkEnumeratePhysicalDevices(_instance, &count, cast(VkPhysicalDevice*) &tmp_buff[0]);
            if (err >= VK_SUCCESS) {
                foreach (i, dev; tmp_buff[0 .. count])
                    buffer[i] = PhysicalDevice(this, tmp_buff[i]);

                auto devices = buffer[0 .. count];
                _logger.trace("Identified %s Graphics Device%s", count, count > 1 ? "s" : "");
                return devices;
            }
        }

        _logger.fatal("Unable to enumerate physical devices.");
        assert(0, "Unable to enumerate physical devices.");
    }

private:
    Logger _logger;
    VkInstance _instance;
    VkVersion _version;
    bool _is_loaded;
}

struct PhysicalDevice {
    @safe nothrow:

    @trusted @nogc bool can_render_to(RenderSurface* surface, uint with_queue_family) {
        VkBool32 out_;
        if (!vkGetPhysicalDeviceSurfaceSupportKHR(_device, with_queue_family, surface.handle, &out_))
            return out_ != 0;

        assert(false);
    }

    auto filter_renderable_queues_to(RenderSurface* surface, in QueueFamilyProperties[] families) {
        struct Range {
            @safe @nogc nothrow:
            uint index() const { return _index; }

            bool empty() const { return _index == _families.length; }

            ref const(QueueFamilyProperties) front() const {
                return _families[_index];
            }

            void popFront() nothrow {
                _index++;
                advance();
            }

        private:
            void advance() nothrow {
                while (!empty && !_device.can_render_to(_surface, _index))
                    _index++;
            }

            RenderSurface* _surface;
            PhysicalDevice* _device;
            const QueueFamilyProperties[] _families;
            uint _index;
        }

        auto ret = Range(surface, &this, families, 0);
        ret.advance();
        return ret;
    }

    @trusted const(QueueFamilyProperties[]) load_queue_families(QueueFamilyProperties[] buffer) {
        uint count;
        vkGetPhysicalDeviceQueueFamilyProperties(_device, &count, null);

        auto mem = scoped_mem!(VkQueueFamilyProperties.sizeof * 32);
        auto tmp = mem.alloc_array!VkQueueFamilyProperties(count);
        vkGetPhysicalDeviceQueueFamilyProperties(_device, &count, &tmp[0]);

        foreach (i, ref t; tmp[0 .. count])
            buffer[i] = QueueFamilyProperties(cast(uint) i, t);

        return buffer[0 .. count];
    }

    @trusted LogicalDevice init_logical_device(VkDeviceQueueCreateInfo[] queues, ref VkPhysicalDeviceFeatures features) {
        VkDeviceCreateInfo dci = {
            pQueueCreateInfos: queues.ptr,
            queueCreateInfoCount: cast(uint) queues.length,
            pEnabledFeatures : &features
        };

        VkDevice device;
        auto err = vkCreateDevice(_device, &dci, null, &device);
        if (err != VK_SUCCESS) {
            _vulkan.log.fatal("Failed to initialize graphics device. Error: %s", err);
            assert(false, "Failed to initialize graphics device.");
        }

        return LogicalDevice(_vulkan, device);
    }

private:
    @trusted this(ref Vulkan vulkan, VkPhysicalDevice device) {
        _vulkan = &vulkan;
        _device = device;
    }

    Vulkan* _vulkan;
    VkPhysicalDevice _device;
}

struct QueueFamilyProperties {
    uint index;
    VkQueueFamilyProperties properties;
    alias properties this;
}

struct LogicalDevice {
    Vulkan* _vulkan;
    VkDevice _device;
}

bool has_flags(VkQueueFlagBits flags)(in VkQueueFamilyProperties props) {
    return (props.queueFlags & flags) != 0;
}
