/**
 Application-agnostic Vulkan wrappers for convenience and improved correctness.
 */
module flare.vulkan.api;

/**
 Functions:
   create_device

 Types:
   VulkanDevice
 */
public import flare.vulkan.device;

/**
 Machine-translated Vulkan headers
 */
public import flare.vulkan.h;

/**
 Functions:
    init_vulkan

 Types:
    ContextOptions
    VulkanContext

 Constants:
    VK_LAYER_LUNARG_API_DUMP_NAME
    VK_LAYER_KHRONOS_VALIDATION_NAME
 */
public import flare.vulkan.context;

/**
 Functions:
    filter_physical_devices
    get_physical_devices
    get_queue_families
    get_supported_extensions

 Types:
    VulkanDeviceCriteria
    VulkanSelectedDevice
 */
public import flare.vulkan.physical_device;

/**
 Functions:
   create_surface

 Types:
   RenderSurface
 */
public import flare.vulkan.surface;
