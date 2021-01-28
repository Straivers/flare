module sandbox;

import flare.application;
import flare.core.math.vector;
import flare.core.memory;
import flare.display.manager;
import flare.display.input;
import flare.vulkan_renderer;
import flare.vulkan;
import pipeline;
import std.stdio;

struct Mesh {
    Vertex[] vertices;
    ushort[] indices;

    size_t vertices_size() const {
        return Vertex.sizeof * vertices.length;
    }

    size_t indices_size() const {
        return ushort.sizeof * indices.length;
    }

    size_t size() const {
        return Vertex.sizeof * vertices.length + ushort.sizeof * indices.length;
    }
}

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

immutable mesh = Mesh(
    [
        // 0 ----- 1
        // |       |
        // 2 ----- 3
        Vertex(float2(-0.5, -0.5), float3(1, 0, 0)),
        Vertex(float2(0.5, -0.5), float3(0, 1, 0)),
        Vertex(float2(-0.5, 0.5), float3(0, 0, 1)),
        Vertex(float2(0.5, 0.5), float3(1, 1, 1))
    ],
    [
    0, 1, 2,
    2, 1, 3
    ]
);

final class Sandbox : FlareApp {
    this(ref FlareAppSettings settings) {
        super(settings);
    }

    override void on_init() {
        {
            ContextOptions options = {
                api_version: VkVersion(1, 2, 0),
                memory: new AllocatorApi!BuddyAllocator(new void[](16.mib)),
                parent_logger: &log,
                layers: [VK_LAYER_KHRONOS_VALIDATION_NAME],
                extensions: VulkanRenderer.required_instance_extensions
            };

            vulkan = init_vulkan(options);
        }

        renderer = new VulkanRenderer(vulkan);
        display_manager = new DisplayManager(vulkan.memory);

        {
            DisplayProperties settings = {
                title: app_settings.name,
                width: app_settings.main_window_width,
                height: app_settings.main_window_height,
                is_resizable: true,
                renderer: renderer,
                input_callbacks: {
                    on_key: (mgr, id, key, state, user) nothrow {
                        if (key == KeyCode.Escape)
                            mgr.close(id);
                        
                        if (key == KeyCode.H)
                            mgr.change_window_mode(id, DisplayMode.Minimized);
                        
                        if (key == KeyCode.S && !mgr.is_visible(id))
                            mgr.change_window_mode(id, DisplayMode.Windowed);
                        
                        if (key == KeyCode.R)
                            mgr.resize(id, 1280, 720);
                        
                        if (key == KeyCode.T)
                            mgr.resize(id, 1920, 1080);
                    }
                }
            };

            display = display_manager.create(settings);
        }

        auto device = renderer.get_logical_device();

        auto swapchain_id = display_manager.get_swapchain(display);
        auto swap_chain = renderer.get_swapchain(swapchain_id);

        shaders[0] = device.load_shader("shaders/vert.spv");
        shaders[1] = device.load_shader("shaders/frag.spv");
        pipeline_layout = device.create_pipeline_layout();

        VkVertexInputBindingDescription[1] binding_descriptions = [Vertex.binding_description];
        VkVertexInputAttributeDescription[2] attrib_descriptions = Vertex.attrib_description;

        pipeline = device.create_graphics_pipeline(*swap_chain, renderer.get_renderpass(swapchain_id), shaders[0], shaders[1], binding_descriptions[], attrib_descriptions[], pipeline_layout);

        transfer_command_pool = create_transfer_command_pool(device);

        staging_allocator = VulkanStackAllocator(device.memory);
        auto staging_buffer = staging_allocator.create_buffer(VK_BUFFER_USAGE_TRANSFER_SRC_BIT, ResourceUsage.transfer, 32.mib);

        mesh_allocator = VulkanStackAllocator(device.memory);
        mesh_buffer = mesh_allocator.create_buffer(VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, ResourceUsage.write_static, mesh.size);

        auto staging_mem = MappedMemory(device.memory, staging_buffer);
        auto vertex_range = staging_mem.put(mesh.vertices);
        auto index_range = staging_mem.put(mesh.indices);
        destroy(staging_mem);

        auto transfer_command_buffer = transfer_command_pool.allocate();
        {
            begin_transfer(device.dispatch_table, transfer_command_buffer);

            auto vertex_op = BufferTransferOp(
                vertex_range,
                mesh_buffer[0 .. mesh.vertices_size],
                device.transfer_family,
                device.graphics_family,
                VK_ACCESS_MEMORY_WRITE_BIT,
                VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT
            );
            record_transfer(device.dispatch_table, transfer_command_buffer, vertex_op);

            auto index_op = BufferTransferOp(
                index_range,
                mesh_buffer[mesh.vertices_size .. $],
                device.transfer_family,
                device.graphics_family,
                VK_ACCESS_MEMORY_WRITE_BIT,
                VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT
            );
            record_transfer(device.dispatch_table, transfer_command_buffer, index_op);

            submit_transfer(device.dispatch_table, transfer_command_buffer, device.transfer);
        }

        device.wait_idle(device.transfer);
        staging_allocator.destroy_buffer(staging_buffer);

        transfer_command_pool.free(transfer_command_buffer);
    }

    override void on_shutdown() {
        auto device = renderer.get_logical_device();
        device.wait_idle();

        foreach (shader; shaders)
            device.dispatch_table.DestroyShaderModule(shader);

        device.dispatch_table.DestroyPipeline(pipeline);
        device.dispatch_table.DestroyPipelineLayout(pipeline_layout);

        destroy(staging_allocator);
        destroy(transfer_command_pool);

        mesh_allocator.destroy_buffer(mesh_buffer);
        destroy(mesh_allocator);

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
                        renderPass: renderer.get_renderpass(display_manager.get_swapchain(display)),
                        framebuffer: frame.framebuffer,
                        renderArea: VkRect2D(VkOffset2D(0, 0), frame.image_size),
                        clearValueCount: 1,
                        pClearValues: &clear_color
                    };
                    vk.CmdBeginRenderPass(frame.graphics_commands, render_pass_info, VK_SUBPASS_CONTENTS_INLINE);
                }

                vk.CmdBindPipeline(frame.graphics_commands, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);

                VkBuffer[1] vert_buffers = [mesh_buffer.handle];
                VkDeviceSize[1] offsets = [0];
                vk.CmdBindVertexBuffers(frame.graphics_commands, vert_buffers, offsets);
                vk.CmdBindIndexBuffer(frame.graphics_commands, mesh_buffer.handle, mesh.vertices_size, VK_INDEX_TYPE_UINT16);

                vk.CmdDrawIndexed(frame.graphics_commands, cast(uint) mesh.indices.length, 1, 0, 0, 0);
                vk.CmdEndRenderPass(frame.graphics_commands);
                vk.EndCommandBuffer(frame.graphics_commands);

                renderer.submit(frame);
                renderer.swap_buffers(display_manager.get_swapchain(display));
            }
        }
    }

    DisplayId display;
    DisplayManager display_manager;

    VulkanContext vulkan;
    VulkanRenderer renderer;

    VkShaderModule[2] shaders;
    VkPipeline pipeline;
    VkPipelineLayout pipeline_layout;

    VulkanStackAllocator mesh_allocator;
    VulkanStackAllocator staging_allocator;

    Buffer mesh_buffer;

    CommandPool transfer_command_pool;
}
