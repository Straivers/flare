/**
 Application-agnostic Vulkan wrappers for convenience and improved correctness.
 */
module flare.vulkan.api;

/**
 Functions:
    load_vulkan

 Types:
    VkVersion
    VulkanAPI
 */
public import flare.vulkan.base;

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
 Types:
    InstanceOptions
    Vulkan
 */
public import flare.vulkan.instance;

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
