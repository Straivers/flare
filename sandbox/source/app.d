module app;

import sandbox;
import flare.application;
import flare.core.memory;

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

nothrow:
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

nothrow:
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

struct RenderContext {
    ulong frame_counter;

    FrameResources[3] resources;
    VkCommandBuffer[3] pending_command_buffers;

    RenderPass1 render_pass;
    VkFramebuffer[] frame_buffers;
}

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

        _display_manager = new VulkanDisplayManager(&log, init_vulkan(options));

        {
            VulkanDisplayProperties display_properties = {
                display_properties: {
                    title: app_settings.name,
                    width: app_settings.main_window_width,
                    height: app_settings.main_window_height,
                    is_resizable: true,
                    user_data: new RenderContext(),
                    callbacks: {
                        on_key: (src, key, state) nothrow {
                            if (key == KeyCode.Escape && state == ButtonState.Released)
                                src.manager.close(src.display_id);
                        },
                        on_create: (src) nothrow {
                            auto vk_mgr = cast(VulkanDisplayManager) src.manager;
                            auto frames = cast(RenderContext*) vk_mgr.get_user_data(src.display_id);

                            foreach (ref frame_resources; frames.resources) with (frame_resources) {
                                fence = create_fence(vk_mgr.device, true);
                                begin_semaphore = create_semaphore(vk_mgr.device);
                                done_semaphore = create_semaphore(vk_mgr.device);
                            }
                        },
                        on_destroy: (src) nothrow {
                            auto vk_mgr = cast(VulkanDisplayManager) src.manager;
                            auto frames = cast(RenderContext*) vk_mgr.get_user_data(src.display_id);

                            foreach (ref frame_resources; frames.resources) with (frame_resources) {
                                destroy_fence(vk_mgr.device, fence);
                                destroy_semaphore(vk_mgr.device, begin_semaphore);
                                destroy_semaphore(vk_mgr.device, done_semaphore);
                            }

                            destroy_renderpass(vk_mgr.device, frames.render_pass);
                        }
                    }
                },
                on_swapchain_create: (src, swapchain) nothrow {
                    auto frames = cast(RenderContext*) src.manager.get_user_data(src.display_id);

                    if (frames.render_pass.swapchain_attachment.format != swapchain.format) {
                        destroy_renderpass(src.manager.device, frames.render_pass);
                    }

                    if (!frames.render_pass.handle) {
                        RenderPassSpec rps = {
                            swapchain_attachment: AttachmentSpec(swapchain.format, [0, 0, 0, 1]),
                            vertex_shader: load_shader(src.manager.device, "shaders/vert.spv"),
                            fragment_shader: load_shader(src.manager.device, "shaders/frag.spv"),
                            bindings: Vertex.binding_description,
                            attributes: Vertex.attrib_description
                        };

                        create_renderpass_1(src.manager.device, rps, frames.render_pass);
                    }

                    frames.frame_buffers = src.manager.device.context.memory.make_array!VkFramebuffer(swapchain.images.length);
                    foreach (i, ref fb; frames.frame_buffers) {
                        VkFramebufferCreateInfo framebuffer_ci = {
                            renderPass: frames.render_pass.handle,
                            attachmentCount: 1,
                            pAttachments: &swapchain.views[i],
                            width: swapchain.image_size.width,
                            height: swapchain.image_size.height,
                            layers: 1
                        };

                        src.manager.device.dispatch_table.CreateFramebuffer(framebuffer_ci, fb);
                    }
                },
                on_swapchain_resize: (src, swapchain) nothrow {
                    auto frames = cast(RenderContext*) src.manager.get_user_data(src.display_id);

                    foreach (fb; frames.frame_buffers)
                        src.manager.device.dispatch_table.DestroyFramebuffer(fb);

                    foreach (i, ref fb; frames.frame_buffers) {
                        VkFramebufferCreateInfo framebuffer_ci = {
                            renderPass: frames.render_pass.handle,
                            attachmentCount: 1,
                            pAttachments: &swapchain.views[i],
                            width: swapchain.image_size.width,
                            height: swapchain.image_size.height,
                            layers: 1
                        };

                        src.manager.device.dispatch_table.CreateFramebuffer(framebuffer_ci, fb);
                    }
                },
                on_swapchain_destroy: (src, swapchain) nothrow {
                    auto frames = cast(RenderContext*) src.manager.get_user_data(src.display_id);

                    foreach (fb; frames.frame_buffers)
                        src.manager.device.dispatch_table.DestroyFramebuffer(fb);
                }
            };

            _display_id = _display_manager.create(display_properties);
        }

        _command_pool = create_graphics_command_pool(_display_manager.device);

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
        destroy(_command_pool);
        destroy(_display_manager);
    }

    override void run() {
        auto device = _display_manager.device;
        // auto vk = device.dispatch_table;

        while (_display_manager.is_live(_display_id)) {
            _display_manager.process_events(false);

            if (_display_manager.is_close_requested(_display_id)) {
                // clean up command buffers
                auto frames = cast(RenderContext*) _display_manager.get_user_data(_display_id);

                foreach (ref resources; frames.resources)
                    wait_fence(device, resources.fence);

                _command_pool.free(frames.pending_command_buffers);
                _display_manager.destroy(_display_id);
            }
            else if (_display_manager.is_visible(_display_id)) {

                auto frames = cast(RenderContext*) _display_manager.get_user_data(_display_id);
                const frame_id = frames.frame_counter % frames.resources.length;
                auto frame = &frames.resources[frame_id];

                SwapchainImage swapchain_image;
                _display_manager.get_next_image(_display_id, swapchain_image, frame.begin_semaphore);

                auto commands = _command_pool.allocate();
                {
                    record_preamble(device, frames.render_pass, commands, frames.frame_buffers[swapchain_image.index], swapchain_image.image_size);

                    // {
                    //     VkBuffer[1] vertex_buffers /* = [mesh_buffer.handle] */;
                    //     VkDeviceSize[1] offsets = [0];
                    //     vk.CmdBindVertexBuffers(commands, vertex_buffers, offsets);
                    // }

                    // vk.CmdBindIndexBuffer(commands, mesh_buffer.handle, mesh.vertices_size, VK_INDEX_TYPE_UINT16);
                    // vk.CmdDrawIndexed(commands, cast(uint) mesh.indices.length, 1, 0, 0, 0);

                    record_postamble(device, frames.render_pass, commands);
                }
                {
                    uint wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
                    VkSubmitInfo submit_i = {
                        waitSemaphoreCount: 1,
                        pWaitSemaphores: &frame.begin_semaphore,
                        pWaitDstStageMask: &wait_stage,
                        commandBufferCount: 1,
                        pCommandBuffers: &commands,
                        signalSemaphoreCount: 1,
                        pSignalSemaphores: &frame.done_semaphore
                    };

                    wait_and_reset_fence(device, frame.fence);

                    if (auto pending = frames.pending_command_buffers[frame_id])
                        _command_pool.free(pending);

                    _command_pool.submit(device.graphics, frame.fence, submit_i);
                    frames.pending_command_buffers[frame_id] = commands;
                }

                _display_manager.swap_buffers(_display_id, frame.done_semaphore);
                frames.frame_counter++;
            }
        }
    }

private:
    DisplayId _display_id;
    VulkanDisplayManager _display_manager;

    CommandPool _command_pool;
}
