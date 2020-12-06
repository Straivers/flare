module sandbox;

import flare.application;
import flare.display.window;
import flare.renderer.vulkan.api;
import flare.core.memory.api;
import flare.core.memory.buddy_allocator;
import pipeline;

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

        vulkan = init_vulkan(options);        
        
        {
            WindowSettings settings = {
                title: app_settings.name,
                inner_width: app_settings.main_window_width,
                inner_height: app_settings.main_window_height,
            };

            window = window_manager.make_window(settings);
        }
        auto surface = vulkan.create_surface(window_manager.get_hwnd(window));
        VulkanDeviceCriteria device_reqs = {
            graphics_queue: true,
            required_extensions: vulkan_extensions,
            display_target: surface
        };

        VulkanGpuInfo gpu;
        vulkan.select_gpu(device_reqs, gpu);
        device = vulkan.create_device(gpu);

        const width = window_manager.get_status(window).inner_width;
        const height = window_manager.get_status(window).inner_height;
        device.create_swapchain(surface, VkExtent2D(width, height), swapchain);

        command_pool = device.create_graphics_command_pool();
        command_buffers = vulkan.memory.alloc_array!VkCommandBuffer(swapchain.images.length);
        command_pool.allocate(command_buffers);

        render_pass = device.create_render_pass(swapchain.format.format);

        frame_buffers = vulkan.memory.alloc_array!VkFramebuffer(swapchain.images.length);
        device.create_framebuffers(swapchain.size, render_pass, swapchain.image_views, frame_buffers);

        shaders[0] = device.load_shader("shaders/vert.spv");
        shaders[1] = device.load_shader("shaders/frag.spv");
        pipeline_layout = device.create_pipeline_layout();
        pipeline = device.create_pipeline(swapchain.size, shaders[0], shaders[1], render_pass, pipeline_layout);
    
        foreach (i, buffer; command_buffers) {
            command_pool.cmd_begin_primary_buffer(buffer);

            {
                VkClearValue clear_color;
                clear_color.color.float32 = [0, 0, 0, 1.0];

                VkRenderPassBeginInfo render_pass_info = {
                    renderPass: render_pass,
                    framebuffer: frame_buffers[i],
                    renderArea: VkRect2D(VkOffset2D(0, 0), swapchain.size),
                    clearValueCount: 1,
                    pClearValues: &clear_color
                };
                command_pool.cmd_begin_render_pass(buffer, render_pass_info);
            }

            command_pool.cmd_bind_pipeline(buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
            command_pool.cmd_draw(buffer, 3, 1, 0, 0);
            command_pool.cmd_end_render_pass(buffer);
            command_pool.cmd_end_buffer(buffer);
        }

        image_available = device.create_semaphore();
        render_complete = device.create_semaphore();
    }

    override void on_shutdown() {
        foreach (shader; shaders)
            device.d_destroy_shader_module(shader);

        foreach (buffer; frame_buffers)
            device.d_destroy_framebuffer(buffer);
        
        vulkan.memory.free(frame_buffers);

        command_pool.free(command_buffers);
        vulkan.memory.free(command_buffers);
        destroy(command_pool);

        device.d_destroy_pipeline(pipeline);
        device.d_destroy_pipeline_layout(pipeline_layout);

        device.d_destroy_render_pass(render_pass);

        destroy(swapchain);

        if (window_manager.is_live(window))
            window_manager.destroy_window(window);

        device.destroy_semaphore(image_available);
        device.destroy_semaphore(render_complete);

        destroy(device);
        destroy(vulkan);
    }

    override void run() {
        while (window_manager.num_open_windows > 0) {
            window_manager.wait_events();
            window_manager.destroy_closed_windows();

            if (window_manager.is_live(window)) {
                uint image_i;
                device.d_acquire_next_image(swapchain.handle, ulong.max, image_available, null, &image_i);

                {
                    VkPipelineStageFlags wait_stages = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
                    VkSubmitInfo si = {
                        waitSemaphoreCount: 1,
                        pWaitSemaphores: &image_available,
                        pWaitDstStageMask: &wait_stages,
                        commandBufferCount: 1,
                        pCommandBuffers: &command_buffers[image_i],
                        signalSemaphoreCount: 1,
                        pSignalSemaphores: &render_complete
                    };

                    command_pool.submit(device.graphics, si);
                }

                {
                    VkPresentInfoKHR pi = {
                        waitSemaphoreCount: 1,
                        pWaitSemaphores: &render_complete,
                        swapchainCount: 1,
                        pSwapchains: &swapchain.handle,
                        pImageIndices: &image_i,
                        pResults: null,
                    };

                    device.d_queue_present(device.graphics, &pi);
                    device.wait_idle(device.graphics);
                }
            }
        }

        device.wait_idle();
    }

    WindowId window;

    VulkanContext vulkan;
    VulkanDevice device;
    Swapchain swapchain;

    VkShaderModule[2] shaders;
    VkRenderPass render_pass;
    VkPipeline pipeline;
    VkPipelineLayout pipeline_layout;
    CommandPool command_pool;
    VkCommandBuffer[] command_buffers;
    VkFramebuffer[] frame_buffers;

    VkSemaphore image_available;
    VkSemaphore render_complete;
}
