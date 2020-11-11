module flare.vulkan.base;

// version (Windows) {
    public import core.sys.windows.windows;
    import erupted.platform_extensions;

    mixin Platform_Extensions!USE_PLATFORM_WIN32_KHR;
// }

void load_vulkan() {
    loadGlobalLevelFunctions();
}

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
