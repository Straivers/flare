module app;

import sandbox;
import flare.application;

void main() {
    FlareAppSettings settings = {
        name: "Flare Sandbox",
        main_window_width: 1920,
        main_window_height: 1080
    };

    // run_app!Sandbox(settings);
    run_app!Test(settings);
}

import flare.core.math.vector;
import flare.vulkan;
import renderpass;

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

class Test : FlareApp {
    import flare.core.memory: AllocatorApi, BuddyAllocator, mib;
    import flare.vulkan : ContextOptions, init_vulkan, VulkanContext, VkVersion, VK_LAYER_KHRONOS_VALIDATION_NAME, SwapchainImage;
    import flare.vulkan_renderer.display_manager : DisplayId, VulkanDisplayManager, VulkanDisplayProperties, KeyCode, ButtonState;
    import std.stdio : writefln, writeln;

public:
    this(ref FlareAppSettings settings) {
        super(settings);
    }

    override void on_init() {
        ContextOptions options = {
            api_version: VkVersion(1, 2, 0),
            memory: new AllocatorApi!BuddyAllocator(new void[](16.mib)),
            parent_logger: &log,
            layers: [VK_LAYER_KHRONOS_VALIDATION_NAME],
            extensions: VulkanDisplayManager.required_instance_extensions
        };

        _display_manager = new VulkanDisplayManager(init_vulkan(options));

        {
            VulkanDisplayProperties display_properties = {
                display_properties: {
                    title: app_settings.name,
                    width: app_settings.main_window_width,
                    height: app_settings.main_window_height,
                    is_resizable: true,
                    callbacks: {
                        on_key: (src, key, state) nothrow {
                            if (key == KeyCode.Escape && state == ButtonState.Released)
                                src.manager.close(src.display_id);
                        },
                        on_resize: (src, width, height) nothrow {
                            debug writefln("Resizing window to (%s, %s)", width, height);
                        },
                        on_create: (src) nothrow {
                            debug writeln("Creating window");
                        },
                        on_destroy: (src) nothrow {
                            debug writeln("Destroying window");
                        }
                    }
                },
                on_swapchain_create: (src, swapchain) nothrow {
                    debug writefln("Creating new swapchain. ID = %s", swapchain.handle);
                },
                on_swapchain_destroy: (src, swapchain) nothrow {
                    debug writefln("Destroying swapchain. ID = %s", swapchain.handle);
                },
                on_swapchain_resize: (src, swapchain) nothrow {
                    debug writefln("Recreating swapchain. Id = %s", swapchain.handle);
                }
            };

            _display_id = _display_manager.create(display_properties);
        }

        import resources;
        auto m = new VulkanResourceManager(_display_manager.device);

        {
            AttachmentSpec[1] attachments = [{
                swapchain_attachment: true
            }];

            auto attributes = Vertex.attrib_description;

            RenderPassSpec spec = {
                attachments: attachments,
                vertex_shader: load_shader(_display_manager.device, "shaders/vert.spv"),
                fragment_shader: load_shader(_display_manager.device, "shaders/frag.spv"),
                bindings: Vertex.binding_description,
                attributes: attributes
            };

            create_renderpass_1(_display_manager.device, spec, _renderpass);
        }

        _command_pool = create_graphics_command_pool(_display_manager.device);

        foreach (ref frame; _virtual_frames) with (frame) {
            fence = create_fence(_display_manager.device, true);
            begin_semaphore = create_semaphore(_display_manager.device);
            done_semaphore = create_semaphore(_display_manager.device);
            command_buffer = _command_pool.allocate();
        }

        /*
        _resource_manager = new DeviceResourceManager(_display_manager.device);

        {
            BufferAllocInfo alloc_i = {
                type: ResourceType.write_static,
                usage: BufferUsage.VertexBuffer | BufferUsage.IndexBuffer | BufferUsage.TransferDst,
                size: mesh.size
            };

            auto buffer = _resource_manger.allocate(alloc_i);

            DeviceBuffer.Parition[2] part_specs = [{mesh.vertices_size}, {mesh.indices_size}];
            DeviceBuffer[2] parts;
            buffer.partition(part_specs, parts);
            _vertex_buffer = parts[0];
            _index_buffer = parts[1];
        }

        _staging_manager = new DeviceStagingManager(_resource_manager);
        _staging_manager.stage(mesh.vertices, _vertex_buffer);
        _staging_manager.stage(mesh.indices, _index_buffer);
        _staging_manager.flush();
        _staging_manager.wait();
        */
    }

    override void on_shutdown() {
        destroy(_display_manager);
    }

    override void run() {
        while (_display_manager.is_live(_display_id)) {
            _display_manager.process_events(false);

            if (_display_manager.is_close_requested(_display_id)) {
                _display_manager.destroy(_display_id);
            }
            else {
                SwapchainImage swapchain_image;
                _display_manager.get_next_image(_display_id, swapchain_image);
                auto device = _display_manager.device;
                auto vk = device.dispatch_table;
                auto frame = &_virtual_frames[_frame_counter % _virtual_frames.length];

                {
                    record_preamble(device, _renderpass, frame.command_buffer, frame.framebuffer, swapchain_image.image_size);
                    // render_pass.write_commands(command_buffers[swapchain_image.index]);

                    {
                        VkBuffer[1] vertex_buffers /* = [mesh_buffer.handle] */;
                        VkDeviceSize[1] offsets = [0];
                        vk.CmdBindVertexBuffers(frame.command_buffer, vertex_buffers, offsets);
                    }

                    // vk.CmdBindIndexBuffer(frame.command_buffer, mesh_buffer.handle, mesh.vertices_size, VK_INDEX_TYPE_UINT16);
                    // vk.CmdDrawIndexed(frame.command_buffer, cast(uint) mesh.indices.length, 1, 0, 0, 0);

                    record_postamble(device, _renderpass, frame.command_buffer);
                }

                {
                    uint wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
                    VkSubmitInfo submit_i = {
                        waitSemaphoreCount: 1,
                        pWaitSemaphores: &frame.begin_semaphore,
                        pWaitDstStageMask: &wait_stage,
                        commandBufferCount: 1,
                        pCommandBuffers: &frame.command_buffer,
                        signalSemaphoreCount: 1,
                        pSignalSemaphores: &frame.done_semaphore
                    };

                    wait_and_reset_fence(device, frame.fence);
                    _command_pool.submit(device.graphics, frame.fence, submit_i);
                }

                _display_manager.swap_buffers(_display_id);
                _frame_counter++;
            }
        }
    }

private:
    DisplayId _display_id;
    VulkanDisplayManager _display_manager;

    RenderPass1 _renderpass;

    ulong _frame_counter;
    VirtualFrame[3] _virtual_frames;

    CommandPool _command_pool;
}
