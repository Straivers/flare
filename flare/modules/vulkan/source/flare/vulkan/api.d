/**
 Application-agnostic Vulkan wrappers for convenience and improved correctness.
 */
module flare.vulkan.api;

/**
 Functions:
   create_device

 Types:
   VulkanDevice

 Constants:
   device_funcs
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
    create_graphics_command_pool
  
  Types:
      CommandPool
 */
public import flare.vulkan.commands;

/**
 Functions:
    load_gpu_info
    select_gpu

 Types:
    VulkanGpuInfo
    VulkanDeviceCriteria
 */
public import flare.vulkan.gpu;

/**
 Functions:
   create_surface
   create_swapchain
   destroy_swapchain

 Types:
   Frame
   FrameSemaphores
   Swapchain
   SwapchainImage
 */
public import flare.vulkan.swapchain;
