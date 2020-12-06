/**
 Application-agnostic Vulkan wrappers for convenience and improved correctness.
 */
module flare.renderer.vulkan.api;

/**
 Functions:
   create_device

 Types:
   VulkanDevice

 Constants:
   device_funcs
 */
public import flare.renderer.vulkan.device;

/**
 Machine-translated Vulkan headers
 */
public import flare.renderer.vulkan.h;

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
public import flare.renderer.vulkan.context;

/**
 Functions:
    create_graphics_command_pool
  
  Types:
      CommandPool
 */
public import flare.renderer.vulkan.commands;

/**
 Functions:
    load_gpu_info
    select_gpu

 Types:
    VulkanGpuInfo
    VulkanDeviceCriteria
 */
public import flare.renderer.vulkan.gpu;

/**
 Functions:
   load_swapchain_support
   create_swapchain
   create_surface

 Types:
   Swapchain
   SwapchainSupport
 */
public import flare.renderer.vulkan.swapchain;
