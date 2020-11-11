module flare.vulkan.base;

public import erupted.types;
public import erupted.functions;


// Platform-Specific Interface
import erupted.platform_extensions;
version (Windows) {
    public import core.sys.windows.windows;
    mixin Platform_Extensions!USE_PLATFORM_WIN32_KHR;
}


// Library Lifetime and Function Loading
void load_vulkan() {
    import erupted.vulkan_lib_loader: loadGlobalLevelFunctions;

    if (!loadGlobalLevelFunctions())
        assert(0, "Unable to load Vulkan API");
}

void load_instance_api(VkInstance instance) {
    loadInstanceLevelFunctionsExt(instance);
}

alias VulkanDeviceAPI = DispatchDeviceExt;

VulkanDeviceAPI load_device_api(VkDevice device) {
    return DispatchDeviceExt(device);
}


// Convenience Types
struct VkVersion {
@safe @nogc pure nothrow:

    uint value;
    alias value this;

    @trusted this(uint major, uint minor, uint patch) {
        value = VK_MAKE_VERSION(major, minor, patch);
    }

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
