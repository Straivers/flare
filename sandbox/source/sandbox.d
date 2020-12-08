module sandbox;

import flare.application;
import flare.display.window;
import flare.renderer.vulkan.api;
import flare.core.memory.api;
import flare.core.memory.buddy_allocator;
import pipeline;
import std.stdio;

immutable vulkan_extensions = [
    VK_KHR_SWAPCHAIN_EXTENSION_NAME
];

final class Sandbox : FlareApp {
    this(ref FlareAppSettings settings) {
        super(settings);
    }

    override void on_init() {
        {
            ContextOptions options = {
                api_version: VkVersion(1, 2, 0),
                memory: new as_api!BuddyAllocator(512.kib),
                parent_logger: &log,
                layers: [VK_LAYER_KHRONOS_VALIDATION_NAME],
                extensions: [VK_KHR_SURFACE_EXTENSION_NAME, VK_KHR_WIN32_SURFACE_EXTENSION_NAME]
            };

            vulkan = init_vulkan(options);        
        }

        {
            WindowSettings settings = {
                title: app_settings.name,
                inner_width: app_settings.main_window_width,
                inner_height: app_settings.main_window_height,
            };

            window = window_manager.make_window(settings);
        }

        auto surface = vulkan.create_surface(window_manager.get_hwnd(window));

        {
            VulkanDeviceCriteria device_reqs = {
                graphics_queue: true,
                required_extensions: vulkan_extensions,
                display_target: surface
            };

            VulkanGpuInfo gpu;
            vulkan.select_gpu(device_reqs, gpu);
            device = vulkan.create_device(gpu);    
        }

        command_pool = device.create_graphics_command_pool();
        create_vulkan_window(device, surface, command_pool, vulkan_window);

        shaders[0] = device.load_shader("shaders/vert.spv");
        shaders[1] = device.load_shader("shaders/frag.spv");
        pipeline_layout = device.create_pipeline_layout();
        pipeline = device.create_pipeline(vulkan_window.image_size, shaders[0], shaders[1], vulkan_window.render_pass, pipeline_layout);

        foreach (i, frame; vulkan_window.frames[0 .. vulkan_window.num_frames]) {
            command_pool.cmd_begin_primary_buffer(frame.command_buffer);

            {
                VkClearValue clear_color;
                clear_color.color.float32 = [0, 0, 0, 1.0];

                VkRenderPassBeginInfo render_pass_info = {
                    renderPass: vulkan_window.render_pass,
                    framebuffer: frame.framebuffer,
                    renderArea: VkRect2D(VkOffset2D(0, 0), vulkan_window.image_size),
                    clearValueCount: 1,
                    pClearValues: &clear_color
                };
                command_pool.cmd_begin_render_pass(frame.command_buffer, render_pass_info);
            }

            command_pool.cmd_bind_pipeline(frame.command_buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
            command_pool.cmd_draw(frame.command_buffer, 3, 1, 0, 0);
            command_pool.cmd_end_render_pass(frame.command_buffer);
            command_pool.cmd_end_buffer(frame.command_buffer);
        }
    }

    override void on_shutdown() {
        device.wait_idle();

        foreach (shader; shaders)
            device.d_destroy_shader_module(shader);

        destroy_vulkan_window(command_pool, vulkan_window);

        destroy(command_pool);

        device.d_destroy_pipeline(pipeline);
        device.d_destroy_pipeline_layout(pipeline_layout);

        if (window_manager.is_live(window))
            window_manager.destroy_window(window);

        destroy(device);
        destroy(vulkan);
    }

    override void run() {
        while (window_manager.num_open_windows > 0) {
            window_manager.wait_events();
            window_manager.destroy_closed_windows();

            if (window_manager.is_live(window)) {
                auto frame = vulkan_window.acquire_next_frame();
                auto semaphores = vulkan_window.current_semaphores();

                {
                    VkPipelineStageFlags wait_stages = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
                    VkSubmitInfo si = {
                        waitSemaphoreCount: 1,
                        pWaitSemaphores: &semaphores.image_acquire,
                        pWaitDstStageMask: &wait_stages,
                        commandBufferCount: 1,
                        pCommandBuffers: &frame.command_buffer,
                        signalSemaphoreCount: 1,
                        pSignalSemaphores: &semaphores.render_complete
                    };

                    command_pool.submit(device.graphics, frame.frame_complete_fence, si);
                }

                vulkan_window.swap_buffers();

                writeln("Draw!");
            }
        }
    }

    WindowId window;

    VulkanContext vulkan;
    VulkanDevice device;

    VkShaderModule[2] shaders;
    VkPipeline pipeline;
    VkPipelineLayout pipeline_layout;
    CommandPool command_pool;

    VulkanWindow vulkan_window;
}
