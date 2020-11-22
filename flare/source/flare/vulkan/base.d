module flare.vulkan.base;

import flare.core.logger: Logger;
import flare.vulkan.h;

enum VK_LAYER_LUNARG_API_DUMP_NAME = "VK_LAYER_LUNARG_api_dump";
enum VK_LAYER_KHRONOS_VALIDATION_NAME = "VK_LAYER_KHRONOS_validation";

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

// Library Lifetime and Function Loading
VulkanAPI load_vulkan(Logger* parent_logger) {
    import erupted.vulkan_lib_loader: loadGlobalLevelFunctions;

    if (!loadGlobalLevelFunctions())
        assert(0, "Unable to load Vulkan API");
    
    return new VulkanAPI(parent_logger);
}

final class VulkanAPI {
    import flare.core.logger: Logger;
    import flare.core.memory.temp: Allocator, TempAllocator, scoped, kib;
    import flare.vulkan.instance: Vulkan, InstanceOptions;
    import flare.vulkan.compat: to_cstr_array;

    this(Logger* parent) {
        _logger = Logger(parent.log_level, parent);
    }

    VkLayerProperties[] get_supported_layers(Allocator mem) {
        uint count;
        const r1 = vkEnumerateInstanceLayerProperties(&count, null);
        if (r1 != VK_SUCCESS) {
            _logger.fatal("Call to vkEnumerateInstanceLayerProperties failed: %s", r1);
            return [];
        }

        auto layers = mem.alloc_arr!VkLayerProperties(count);
        if (!layers) {
            _logger.fatal("Out of Temporary Memory!");
            return [];
        }

        const r2 = vkEnumerateInstanceLayerProperties(&count, layers.ptr);
        if (r2 != VK_SUCCESS) {
            _logger.fatal("Call to vkEnumerateInstanceLayerProperties failed: %s", r2);
            return [];
        }

        return layers;
    }

    VkExtensionProperties[] get_supported_extensions(Allocator mem) {
        uint count;
        const r1 = vkEnumerateInstanceExtensionProperties(null, &count, null);
        if (r1 != VK_SUCCESS) {
            _logger.fatal("Call to vkEnumerateInstanceExtensionProperties failed: %s", r1);
            return [];
        }

        auto extensions = mem.alloc_arr!VkExtensionProperties(count);
        if (!extensions) {
            _logger.fatal("Out of Temporary Memory!");
            return [];
        }

        const r2 = vkEnumerateInstanceExtensionProperties(null, &count, extensions.ptr);
        if (r2 != VK_SUCCESS) {
            _logger.fatal("Call to vkEnumerateInstanceExtensionProperties failed: %s", r2);
            return [];
        }

        return extensions;
    }

    string[] get_supported_layer_names(Allocator allocator) {
        return get_supported_property_names!get_supported_layers(allocator);
    }

    string[] get_supported_extension_names(Allocator allocator) {
        return get_supported_property_names!get_supported_extensions(allocator);
    }

    Vulkan create_instance(ref InstanceOptions options) {
        VkApplicationInfo ai = {
            sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,
            pApplicationName: "Flare",
            applicationVersion: VkVersion(0, 0, 0),
            pEngineName: "Flare Engine",
            engineVersion: VkVersion(1, 0, 0),
            apiVersion: options.api_version
        };

        auto tmp = scoped!TempAllocator(4.kib);
        auto layers = options.layers.to_cstr_array(tmp);
        auto extensions = options.extensions.to_cstr_array(tmp);

        if (layers && extensions) {
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

            if (result != VK_SUCCESS) {
                _logger.fatal("Could not create instance: %s", result);
                assert(0, "Could not create vulkan instance.");
            }

            _logger.info("Vulkan instance created with:\n\tLayers:%-( %s%)\n\tExtensions:%-( %s%)", options.layers, options.extensions);
            loadInstanceLevelFunctionsExt(instance);
            return new Vulkan(&_logger, instance);
        }

        _logger.fatal("Failed to create Vulkan instance: Out of Temporary Memory");
        assert(0, "Failed to create Vulkan instance: Out of Temporary Memory");
    }

private:
    Logger _logger;

    string[] get_supported_property_names(alias get_properties)(Allocator allocator) {
        import core.stdc.string: strlen;

        auto tmp = scoped!TempAllocator(16.kib);
        auto properties = get_properties(tmp);
        auto names = allocator.alloc_arr!string(properties.length);
        assert(names.length == properties.length);

        foreach (i, ref property; properties) {
            auto length = strlen(name_of(property));
            auto str = allocator.alloc_arr!char(length);
            if (str)
                str[] = name_of(property)[0 .. length];

            names[i] = cast(string) str;
        }

        if (names != [] && names[$ - 1] != [])
            return names;
        return [];
    }
    
    char* name_of(ref return VkExtensionProperties properties) {
        return &properties.extensionName[0];
    }

    char* name_of(ref return VkLayerProperties properties) {
        return &properties.layerName[0];
    }
}
