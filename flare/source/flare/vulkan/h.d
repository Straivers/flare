module flare.vulkan.h;

public import erupted.types;
public import erupted.functions;

// Platform-Specific Interface
import erupted.platform_extensions;
version (Windows) {
    public import core.sys.windows.windows;
    mixin Platform_Extensions!USE_PLATFORM_WIN32_KHR;
}
