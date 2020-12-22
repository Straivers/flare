module sandbox;

import flare.application;
// import flare.display.window;
// import flare.display.display_manager;
import flare.display.manager;
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
                is_resizable: true,
                renderer: renderer
            };

            display = display_manager.create(settings);
        }

        auto device = renderer.get_logical_device();
        auto swap_chain = renderer.get_swapchain(display_manager.get_swapchain(display));

        shaders[0] = device.load_shader("shaders/vert.spv");
        shaders[1] = device.load_shader("shaders/frag.spv");
        pipeline_layout = device.create_pipeline_layout();
        pipeline = device.create_pipeline(swap_chain.image_size, shaders[0], shaders[1], swap_chain.render_pass, pipeline_layout);
    }

    override void on_shutdown() {
        auto device = renderer.get_logical_device();
        device.wait_idle();

        foreach (shader; shaders)
            device.d_destroy_shader_module(shader);

        device.d_destroy_pipeline(pipeline);
        device.d_destroy_pipeline_layout(pipeline_layout);

        destroy(renderer);
        destroy(vulkan);
    }

    override void run() {
        while (display_manager.num_active_displays > 0) {
            display_manager.process_events(false);

            if (display_manager.is_close_requested(display))
                display_manager.destroy(display);
            else if (display_manager.is_visible(display)) {
                auto frame = renderer.get_frame(display_manager.get_swapchain(display));
                auto vk = renderer.get_logical_device().dispatch_table;

                {
                    VkCommandBufferBeginInfo info;
                    vk.BeginCommandBuffer(frame.graphics_commands, &info);
                }

                {
                    VkViewport viewport = {
                        x: 0,
                        y: 0,
                        width: frame.image_size.width,
                        height: frame.image_size.height,
                        minDepth: 0.0f,
                        maxDepth: 1.0f
                    };
                    vk.CmdSetViewport(frame.graphics_commands, 0, 1, &viewport);
                }

                {
                    VkClearValue clear_color;
                    clear_color.color.float32 = [0, 0, 0, 1.0];

                    VkRenderPassBeginInfo render_pass_info = {
                        renderPass: frame.render_pass,
                        framebuffer: frame.framebuffer,
                        renderArea: VkRect2D(VkOffset2D(0, 0), frame.image_size),
                        clearValueCount: 1,
                        pClearValues: &clear_color
                    };
                    vk.CmdBeginRenderPass(frame.graphics_commands, &render_pass_info, VK_SUBPASS_CONTENTS_INLINE);
                }

                vk.CmdBindPipeline(frame.graphics_commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
                vk.CmdDraw(frame.graphics_commands, 3, 1, 0, 0);
                vk.CmdEndRenderPass(frame.graphics_commands);
                vk.EndCommandBuffer(frame.graphics_commands);

                renderer.submit(frame);
                renderer.swap_buffers(display_manager.get_swapchain(display));
            }
        }
    }

    Handle display;
    DisplayManager display_manager;

    VulkanContext vulkan;
    VulkanRenderer renderer;

    VkShaderModule[2] shaders;
    VkPipeline pipeline;
    VkPipelineLayout pipeline_layout;
}
