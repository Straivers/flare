module sandbox;

import flare.application;
import flare.core.math.vector;
import flare.vulkan;
import flare.core.memory;
import renderpass;
import mem.buffer;
import meshes;
import flare.vulkan_renderer.display_manager;

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

class Sandbox : FlareApp {
    import flare.core.memory: AllocatorApi, BuddyAllocator, mib;

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
            DisplayProperties properties = {
                title: app_settings.name,
                width: app_settings.main_window_width,
                height: app_settings.main_window_height,
                mode: DisplayMode.Windowed,
                is_resizable: true,
            };

            VulkanCallbacks callbacks = {
                callbacks: {
                    on_key: (src, key, state) nothrow {
                        if (key == KeyCode.Escape && state == ButtonState.Released)
                            src.manager.close(src.display_id);
                    },
                    on_create: (src) nothrow {
                        auto vk_mgr = cast(VulkanDisplayManager) src.manager;
                        auto frames = cast(RenderContext*) vk_mgr.get_user_data(src.display_id);

                        foreach (ref frame_resources; frames.resources) with (frame_resources) {
                            fence = vk_mgr.device.fence_pool.acquire(true);
                            begin_semaphore = vk_mgr.device.semaphore_pool.acquire();
                            done_semaphore = vk_mgr.device.semaphore_pool.acquire();
                        }
                    },
                    on_destroy: (src) nothrow {
                        auto vk_mgr = cast(VulkanDisplayManager) src.manager;
                        auto frames = cast(RenderContext*) vk_mgr.get_user_data(src.display_id);

                        foreach (ref frame_resources; frames.resources) with (frame_resources) {
                            vk_mgr.device.fence_pool.release(fence);
                            vk_mgr.device.semaphore_pool.release(begin_semaphore);
                            vk_mgr.device.semaphore_pool.release(done_semaphore);
                        }

                        destroy_renderpass(vk_mgr.device, frames.render_pass);
                    }
                },
                on_swapchain_create: (src, swapchain) nothrow {
                    auto frames = cast(RenderContext*) src.manager.get_user_data(src.display_id);

                    if (frames.render_pass.handle && frames.render_pass.swapchain_attachment.format != swapchain.format) {
                        destroy_renderpass(src.manager.device, frames.render_pass);
                    }

                    if (!frames.render_pass.handle) {
                        VkVertexInputAttributeDescription[2] attrs = Vertex.attribute_descriptions;
                        RenderPassSpec rps = {
                            swapchain_attachment: AttachmentSpec(swapchain.format, [0, 0, 0, 1]),
                            vertex_shader: load_shader(src.manager.device, "shaders/vert.spv"),
                            fragment_shader: load_shader(src.manager.device, "shaders/frag.spv"),
                            bindings: Vertex.binding_description,
                            attributes: attrs
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

            _display_id = _display_manager.create(properties, callbacks, new RenderContext());
        }

        _command_pool = create_graphics_command_pool(_display_manager.device);

        _device_memory = new RawDeviceMemoryAllocator(_display_manager.device);

        auto tid = get_type_index(&_device_memory, DeviceHeap.Dynamic, BufferAllocInfo(64, BufferType.Mesh, Transferability.Receive));
        _memory_pool = new LinearPool(&_device_memory, _display_manager.device.context.memory, tid, DeviceHeap.Dynamic);
        _buffers = BufferManager(_memory_pool);
        create_mesh_buffers(_buffers, mesh, _mesh);

        auto v = cast(Vertex[]) _buffers.map(_mesh.vertices);
        v[] = mesh.vertices;
        _buffers.unmap(_mesh.vertices);

        auto i = cast(ushort[]) _buffers.map(_mesh.indices);
        i[] = mesh.indices;
        _buffers.unmap(_mesh.indices);
    }

    override void on_shutdown() {
        _buffers.destroy_buffer(_mesh.vertices);
        _buffers.destroy_buffer(_mesh.indices);
        _memory_pool.clear();
        destroy(_memory_pool);
        destroy(_device_memory);
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
                    wait(device, resources.fence);

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
                    record_mesh_draw(device.dispatch_table, commands, _buffers, _mesh);
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

                    wait_and_reset(device, frame.fence);

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
    RawDeviceMemoryAllocator _device_memory;
    LinearPool _memory_pool;
    BufferManager _buffers;

    GpuMesh _mesh;
}
