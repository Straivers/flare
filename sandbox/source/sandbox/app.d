module sandbox.app;

import flare.core.logger;
import flare.vulkan.api;
import flare.core.memory.temp;
import flare.presentation.window_manager;
import std.algorithm : filter;
import std.range: enumerate;
import std.stdio: writeln, writefln;

import flare.core.memory.buddy_allocator;

void main() {
    auto logger = Logger(LogLevel.All);
    logger.add_sink(new ConsoleLogger(true));

    // auto wm = WindowManager(&logger);


    auto vulkan_api = load_vulkan(&logger);
    auto tmp = scoped!TempAllocator(4.kib);

    auto layers = vulkan_api.get_supported_layer_names(tmp);
    writefln("Layers (%s):", layers.length);
    foreach (ref l; layers)
        writeln(l);
    writeln;

    auto ext = vulkan_api.get_supported_extension_names(tmp);
    writefln("Extensions (%s):", ext.length);
    foreach (ref e; ext)
        writeln(e);
    writeln;


    auto options = InstanceOptions(VkVersion(1, 2, 0), [
        VK_LAYER_KHRONOS_VALIDATION_NAME
    ], [
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_WIN32_SURFACE_EXTENSION_NAME
    ]);

    auto vulkan = vulkan_api.create_instance(options);

    // auto window = wm.make_window(WindowSettings("Hello", 1280, 720, false, null));
    // auto surface = vk.create_surface(wm.get_hwnd(window));

    // auto devices = vk.get_physical_devices();

    // QueueFamilyProperties[32] queue_buffer;
    // auto queues = devices[0].load_queue_families(queue_buffer);
    // auto draw_queues = queues.filter!(has_flags!VK_QUEUE_GRAPHICS_BIT)();
    // auto show_queues = devices[0].filter_renderable_queues_to(&surface, queues);

    // vk.log.trace("Available draw queue families: %-(%s%)", draw_queues);
    // vk.log.trace("Available presentation queue families: %-(%s%)", show_queues);

    // while (wm.num_open_windows > 0) {
    //     wm.wait_events();
    //     wm.destroy_closed_windows();
    // }

    // assert(!draw_queues.empty);
    // assert(!show_queues.empty);

    // VkDeviceQueueCreateInfo[2] qci = [
    //     {
    //         queueFamilyIndex : draw_queues.front.index,
    //         queueCount : 1
    //     },
    //     {
    //         queueFamilyIndex : show_queues.index,
    //         queueCount : 1
    //     }
    // ];

    // VkPhysicalDeviceFeatures features;
    // auto device = devices[0].init_logical_device(qci[0 .. (draw_queues.front.index == show_queues.index ? 1 : 2)], features);

    // destroy(surface);
    // destroy(vk);
}
