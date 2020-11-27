module sandbox;

import flare.application;
import flare.renderer.vulkan.api;
import flare.core.memory.api;
import flare.core.memory.buddy_allocator;

immutable vulkan_extensions = [
    VK_KHR_SWAPCHAIN_EXTENSION_NAME
];

final class Sandbox : FlareApp {
    this(ref FlareAppSettings settings) {
        super(settings);
    }

    override void on_init() {
        ContextOptions options = {
            api_version: VkVersion(1, 2, 0),
            memory: new as_api!BuddyAllocator(512.kib),
            parent_logger: &log,
            layers: [VK_LAYER_KHRONOS_VALIDATION_NAME],
            extensions: [VK_KHR_SURFACE_EXTENSION_NAME, VK_KHR_WIN32_SURFACE_EXTENSION_NAME]
        };

        auto vulkan = init_vulkan(options);        

        auto surface = vulkan.create_surface(window_manager.get_hwnd(main_window));
        VulkanDeviceCriteria device_reqs = {
            graphics_queue: true,
            required_extensions: vulkan_extensions,
            display_target: surface
        };

        VulkanGpuInfo gpu;
        vulkan.select_gpu(device_reqs, gpu);
        device = vulkan.create_device(gpu);

        const width = window_manager.get_status(main_window).inner_width;
        const height = window_manager.get_status(main_window).inner_height;
        device.create_swapchain(surface, VkExtent2D(width, height), swapchain);
    }

    override void on_shutdown() {
        destroy(swapchain);
        destroy(device);
        destroy(vulkan);
    }

    override void run() {
        while (window_manager.num_open_windows > 0) {
            window_manager.wait_events();
            window_manager.destroy_closed_windows();
        }
    }

    VulkanContext vulkan;
    VulkanDevice device;
    Swapchain swapchain;
}
