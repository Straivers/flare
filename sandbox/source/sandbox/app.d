module sandbox.app;

import flare.core.logger;
import flare.core.memory.api;
import flare.core.memory.temp;
import flare.presentation.window_manager;
import flare.vulkan.api;
import std.stdio : writefln, writeln;

import flare.core.memory.buddy_allocator;

void main() {
    a();
}

void a() {
    auto logger = Logger(LogLevel.All);
    logger.add_sink(new ConsoleLogger(true));

    auto wm = WindowManager(&logger);

    ContextOptions options = {
        api_version: VkVersion(1, 2, 0),
        memory: new as_api!BuddyAllocator(512.kib),
        parent_logger: &logger,
        layers: [VK_LAYER_KHRONOS_VALIDATION_NAME],
        extensions: [VK_KHR_SURFACE_EXTENSION_NAME, VK_KHR_WIN32_SURFACE_EXTENSION_NAME]
    };
    auto vulkan = init_vulkan(options);

    auto window = wm.make_window(WindowSettings("Hello", 1280, 720, false, null));
    auto surface = vulkan.create_surface(wm.get_hwnd(window));

    string[] exts = [
        VK_KHR_SWAPCHAIN_EXTENSION_NAME
    ];

    import flare.vulkan.device;
    VulkanDeviceCriteria criteria = {
        graphics_queue: true,
        required_extensions: exts,
        display_target: surface
    };

    VulkanGpuInfo gpu;
    vulkan.select_gpu(criteria, gpu);
    auto device = vulkan.create_device(gpu);

    Swapchain swapchain;
    create_swapchain(device, surface, VkExtent2D(wm.get_status(window).inner_width, wm.get_status(window).inner_height), swapchain);

    while (wm.num_open_windows > 0) {
        wm.wait_events();
        wm.destroy_closed_windows();
    }

    destroy(swapchain);
    destroy(device);
    destroy(vulkan);
}
