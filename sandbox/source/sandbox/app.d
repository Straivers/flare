module sandbox.app;

import flare.core.logger;
import flare.platform.vulkan.api;
import flare.platform.vulkan.surface;
import flare.presentation.window_manager;
import std.algorithm : filter;
import std.range: enumerate;

void main() {
    auto logger = Logger(LogLevel.All);
    logger.add_sink(new ConsoleLogger(true));

    auto wm = WindowManager(&logger);
    auto vk = Vulkan(&logger);

    auto window = wm.make_window(WindowSettings("Hello", 1280, 720, false, null));
    auto surface = vk.create_surface(wm, window);

    PhysicalDevice[32] device_buffer;
    auto devices = vk.load_physical_devices(device_buffer);

    QueueFamilyProperties[32] queue_buffer;
    auto queues = devices[0].load_queue_families(queue_buffer);
    auto draw_queues = queues.filter!(has_flags!VK_QUEUE_GRAPHICS_BIT)();
    auto show_queues = devices[0].filter_renderable_queues_to(&surface, queues);

    vk.log.trace("Available draw queue families: %-(%s%)", draw_queues);
    vk.log.trace("Available presentation queue families: %-(%s%)", show_queues);

    while (wm.num_open_windows > 0) {
        wm.wait_events();
        wm.destroy_closed_windows();
    }

    assert(!draw_queues.empty);
    assert(!show_queues.empty);

    VkDeviceQueueCreateInfo[2] qci = [
        {
            queueFamilyIndex : draw_queues.front.index,
            queueCount : 1
        },
        {
            queueFamilyIndex : show_queues.index,
            queueCount : 1
        }
    ];

    VkPhysicalDeviceFeatures features;
    auto device = devices[0].init_logical_device(qci[0 .. (draw_queues.front.index == show_queues.index ? 1 : 2)], features);

    destroy(surface);
    destroy(vk);
}
