module sandbox;

import flare.application;
// import flare.display.window;
import flare.display.display_manager;
import flare.renderer.vulkan_renderer;
import flare.vulkan.api;
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
                extensions: VulkanRenderer.required_instance_extensions
            };

            vulkan = init_vulkan(options);
        }

        renderer = new VulkanRenderer(vulkan);
        display_manager = new DisplayManager();

        {
            DisplayProperties settings = {
                title: app_settings.name,
                width: app_settings.main_window_width,
                height: app_settings.main_window_height,
                renderer: renderer
            };

            DisplayCallbacks callbacks;

            const result = display_manager.make_display(settings, callbacks, display);
            assert(result == DisplayResult.NoError);
        }

        auto device = renderer.get_logical_device();
        auto swap_chain = renderer.get_swapchain(display_manager.get_swapchain(display));
        command_pool = device.create_graphics_command_pool();
        command_buffers = vulkan.memory.alloc_array!VkCommandBuffer(swap_chain.num_frames);
        command_pool.allocate(command_buffers);

        shaders[0] = device.load_shader("shaders/vert.spv");
        shaders[1] = device.load_shader("shaders/frag.spv");
        pipeline_layout = device.create_pipeline_layout();
        pipeline = device.create_pipeline(swap_chain.image_size, shaders[0], shaders[1], swap_chain.render_pass, pipeline_layout);

        foreach (i, frame; swap_chain.frames) {
            command_pool.cmd_begin_primary_buffer(command_buffers[i]);

            {
                VkViewport viewport = {
                    x: 0,
                    y: 0,
                    width: swap_chain.image_size.width,
                    height: swap_chain.image_size.height,
                    minDepth: 0.0f,
                    maxDepth: 1.0f
                };
                command_pool.cmd_set_viewport(command_buffers[i], viewport);
            }

            {
                VkClearValue clear_color;
                clear_color.color.float32 = [0, 0, 0, 1.0];

                VkRenderPassBeginInfo render_pass_info = {
                    renderPass: swap_chain.render_pass,
                    framebuffer: frame.framebuffer,
                    renderArea: VkRect2D(VkOffset2D(0, 0), swap_chain.image_size),
                    clearValueCount: 1,
                    pClearValues: &clear_color
                };
                command_pool.cmd_begin_render_pass(command_buffers[i], render_pass_info);
            }

            command_pool.cmd_bind_pipeline(command_buffers[i], VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
            command_pool.cmd_draw(command_buffers[i], 3, 1, 0, 0);
            command_pool.cmd_end_render_pass(command_buffers[i]);
            command_pool.cmd_end_buffer(command_buffers[i]);
        }
    }

    override void on_shutdown() {
        auto device = renderer.get_logical_device();
        device.wait_idle();

        foreach (shader; shaders)
            device.d_destroy_shader_module(shader);

        command_pool.free(command_buffers);
        vulkan.memory.free(command_buffers);
        destroy(command_pool);

        device.d_destroy_pipeline(pipeline);
        device.d_destroy_pipeline_layout(pipeline_layout);

        destroy(renderer);
        destroy(vulkan);
    }

    override void run() {
        while (display_manager.num_active_displays > 0) {
            display_manager.process_events(true);

            if (display_manager.is_live(display)) {
                if (auto frame = renderer.get_frame(display_manager.get_swapchain(display))) {

                    {
                        VkPipelineStageFlags wait_stages = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
                        VkSubmitInfo si = {
                            waitSemaphoreCount: 1,
                            pWaitSemaphores: &frame.image_acquire,
                            pWaitDstStageMask: &wait_stages,
                            commandBufferCount: 1,
                            pCommandBuffers: &command_buffers[frame.index],
                            signalSemaphoreCount: 1,
                            pSignalSemaphores: &frame.render_complete
                        };

                        command_pool.submit(renderer.get_logical_device().graphics, frame.frame_complete_fence, si);
                    }
                }

                display_manager.swap_buffers(display);
            }
        }
    }

    DisplayId display;

    VulkanContext vulkan;
    VulkanRenderer renderer;

    VkShaderModule[2] shaders;
    VkPipeline pipeline;
    VkPipelineLayout pipeline_layout;

    CommandPool command_pool;
    VkCommandBuffer[] command_buffers;
}
