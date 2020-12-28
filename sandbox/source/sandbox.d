module sandbox;

import flare.application;
import flare.core.math.vector;
import flare.core.memory.api;
import flare.core.memory.buddy_allocator;
import flare.display.manager;
import flare.renderer.vulkan_renderer;
import flare.vulkan.api;
import pipeline;
import std.stdio;

struct Vertex {
    float2 position;
    float3 colour;

    static VkVertexInputBindingDescription binding_description() {
        VkVertexInputBindingDescription desc = {
            binding: 0,
            stride: Vertex.sizeof,
            inputRate: VK_VERTEX_INPUT_RATE_VERTEX
        };

        return desc;
    }

    static VkVertexInputAttributeDescription[2] attrib_description() {
        VkVertexInputAttributeDescription[2] descs = [
            {
                binding: 0,
                location: 0,
                format: VK_FORMAT_R32G32_SFLOAT,
                offset: Vertex.position.offsetof,
            },
            {
                binding: 0,
                location: 1,
                format: VK_FORMAT_R32G32B32_SFLOAT,
                offset: Vertex.colour.offsetof,
            }
        ];

        return descs;
    }
}

immutable Vertex[] vertices = [
    Vertex(float2(0, -0.5), float3(1.0, 0, 0)),
    Vertex(float2(0.5, 0.5), float3(0, 1.0, 0)),
    Vertex(float2(-0.5, 0.5), float3(0, 0, 1.0)),
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

        VkVertexInputBindingDescription[1] binding_descriptions = [Vertex.binding_description];
        VkVertexInputAttributeDescription[2] attrib_descriptions = Vertex.attrib_description;

        pipeline = device.create_graphics_pipeline(*swap_chain, shaders[0], shaders[1], binding_descriptions[], attrib_descriptions[], pipeline_layout);

        vertex_buffer = create_buffer(device, vertices.length * Vertex.sizeof, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        alloc_buffer(device, vertex_buffer);
        copy_host_visible_buffer(device, vertex_buffer, vertices);
    }

    override void on_shutdown() {
        auto device = renderer.get_logical_device();
        device.wait_idle();

        foreach (shader; shaders)
            device.d_destroy_shader_module(shader);

        device.d_destroy_pipeline(pipeline);
        device.d_destroy_pipeline_layout(pipeline_layout);

        device.dispatch_table.DestroyBuffer(vertex_buffer.handle);
        device.dispatch_table.FreeMemory(vertex_buffer.backing_store);

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
                    vk.BeginCommandBuffer(frame.graphics_commands, info);
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
                    vk.CmdSetViewport(frame.graphics_commands, viewport);
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
                    vk.CmdBeginRenderPass(frame.graphics_commands, render_pass_info, VK_SUBPASS_CONTENTS_INLINE);
                }

                vk.CmdBindPipeline(frame.graphics_commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);

                VkBuffer[1] vert_buffers = [vertex_buffer.handle];
                VkDeviceSize[1] offsets = [0];
                vk.CmdBindVertexBuffers(frame.graphics_commands, vert_buffers, offsets);

                vk.CmdDraw(frame.graphics_commands, cast(uint) vertices.length, 1, 0, 0);
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
    Buffer vertex_buffer;
}
