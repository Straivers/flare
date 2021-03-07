module sandbox;

import flare.application;
import flare.core.math.vector;
import flare.vulkan;
import flare.core.memory;
import flare.vulkan_renderer;
import flare.display;

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

// VulkanCallbacks!RenderContext vk_window_callbacks = {
//     callbacks: {
//         on_key: (mgr, id, usr, key, state) nothrow {
//             if (key == KeyCode.Escape && state == ButtonState.Released)
//                 mgr.close(id);
//         },
//         on_create: (mgr, id, usr, aux) nothrow {
//             auto vk_mgr = cast(VulkanDisplayManager!RenderContext) mgr;
//             auto context = &vk_mgr.get_typed_user_data(id);
//             assert(cast(void*) context == usr);

//             /*
//             assert(aux);
//             auto renderer = cast(VulkanRenderer*) aux;

//             if (!renderer.initialized)
//                 renderer.initialize(vk_mgr.device);
//             */

//             foreach (ref frame_resources; context.resources) with (frame_resources) {
//                 fence = vk_mgr.device.fence_pool.acquire(true);
//                 begin_semaphore = vk_mgr.device.semaphore_pool.acquire();
//                 done_semaphore = vk_mgr.device.semaphore_pool.acquire();
//             }

//             context.command_pool = create_graphics_command_pool(vk_mgr.device);
//         },
//         on_close: (mgr, id, usr) nothrow {
//             mgr.destroy(id);
//         },
//         on_destroy: (mgr, id, usr) nothrow {
//             auto vk_mgr = cast(VulkanDisplayManager!RenderContext) mgr;
//             auto context = &vk_mgr.get_typed_user_data(id);
//             assert(cast(void*) context == usr);

//             foreach (ref frame_resources; context.resources) with (frame_resources) {
//                 wait(vk_mgr.device, fence);
//                 vk_mgr.device.fence_pool.release(fence);
//                 vk_mgr.device.semaphore_pool.release(begin_semaphore);
//                 vk_mgr.device.semaphore_pool.release(done_semaphore);
//             }

//             if (context.render_pass.handle)
//                 destroy_renderpass(vk_mgr.device, context.render_pass);

//             context.command_pool.free(context.pending_command_buffers);
//             destroy(context.command_pool);
//         }
//     },
//     on_swapchain_create: (mgr, id, context, swapchain) nothrow {
//         if (context.render_pass.handle && context.render_pass.swapchain_attachment.format != swapchain.format) {
//             destroy_renderpass(mgr.device, context.render_pass);
//         }

//         if (!context.render_pass.handle) {
//             VkVertexInputAttributeDescription[2] attrs = Vertex.attribute_descriptions;
//             RenderPassSpec rps = {
//                 swapchain_attachment: AttachmentSpec(swapchain.format, [0, 0, 0, 1]),
//                 vertex_shader: load_shader(mgr.device, "shaders/vert.spv"),
//                 fragment_shader: load_shader(mgr.device, "shaders/frag.spv"),
//                 bindings: Vertex.binding_description,
//                 attributes: attrs
//             };

//             create_renderpass_1(mgr.device, rps, context.render_pass);
//         }

//         context.frame_buffers = mgr.device.context.memory.make_array!VkFramebuffer(swapchain.images.length);
//         foreach (i, ref fb; context.frame_buffers) {
//             VkFramebufferCreateInfo framebuffer_ci = {
//                 renderPass: context.render_pass.handle,
//                 attachmentCount: 1,
//                 pAttachments: &swapchain.views[i],
//                 width: swapchain.image_size.width,
//                 height: swapchain.image_size.height,
//                 layers: 1
//             };

//             mgr.device.dispatch_table.CreateFramebuffer(framebuffer_ci, fb);
//         }
//     },
//     on_swapchain_resize: (mgr, id, context, swapchain) nothrow {
//         foreach (frame; context.resources)
//             wait(mgr.device, frame.fence);

//         foreach (fb; context.frame_buffers)
//             mgr.device.dispatch_table.DestroyFramebuffer(fb);

//         foreach (i, ref fb; context.frame_buffers) {
//             VkFramebufferCreateInfo framebuffer_ci = {
//                 renderPass: context.render_pass.handle,
//                 attachmentCount: 1,
//                 pAttachments: &swapchain.views[i],
//                 width: swapchain.image_size.width,
//                 height: swapchain.image_size.height,
//                 layers: 1
//             };

//             mgr.device.dispatch_table.CreateFramebuffer(framebuffer_ci, fb);
//         }
//     },
//     on_swapchain_destroy: (mgr, id, context, swapchain) nothrow {
//         foreach (frame; context.resources)
//             wait(mgr.device, frame.fence);

//         foreach (fb; context.frame_buffers)
//             mgr.device.dispatch_table.DestroyFramebuffer(fb);
//     }
// };

class Sandbox : FlareApp {
    import flare.core.memory: AllocatorApi, BuddyAllocator, mib;

public:
    this(ref FlareAppSettings settings) {
        super(settings);
        
        _displays = new DisplayManager(&log, new AllocatorApi!Arena(new void[](1.mib)));

        {
            ContextOptions options = {
                api_version: VkVersion(1, 2, 0),
                memory: new AllocatorApi!BuddyAllocator(new void[](16.mib)),
                parent_logger: &log,
                layers: [VK_LAYER_KHRONOS_VALIDATION_NAME],
                extensions: VulkanRenderer.required_instance_extensions
            };

            _vulkan = init_vulkan(options);
            _renderer = new VulkanRenderer(_vulkan, _displays.max_open_displays);
        }
    }

    override void on_init() {
        {
            DisplayProperties properties = {
                title: app_settings.name,
                width: app_settings.main_window_width,
                height: app_settings.main_window_height,
                mode: DisplayMode.Windowed,
                is_resizable: true,
                callbacks: {
                    on_key: (mgr, id, usr, key, state) nothrow {
                        import std.stdio; debug writeln(key);
                        if (key == KeyCode.Escape && state == ButtonState.Released)
                            mgr.close(id);
                    },
                    on_close: (mgr, id, user) nothrow {
                        mgr.destroy(id);
                    }
                }
            };

            _display_id = create_vulkan_window(_displays, _renderer, properties);
        }

        {
            _device_memory = new RawDeviceMemoryAllocator(_renderer.device);

            auto tid = get_type_index(&_device_memory, DeviceHeap.Dynamic, BufferAllocInfo(64, BufferType.Mesh, Transferability.Receive));
            _memory_pool = new LinearPool(&_device_memory, _renderer.device.context.memory, tid, DeviceHeap.Dynamic);
            _buffers = BufferManager(_memory_pool);
            create_mesh_buffers(_buffers, mesh, _mesh);

            auto v = cast(Vertex[]) _buffers.map(_mesh.vertices);
            v[] = mesh.vertices;
            _buffers.unmap(_mesh.vertices);

            auto i = cast(ushort[]) _buffers.map(_mesh.indices);
            i[] = mesh.indices;
            _buffers.unmap(_mesh.indices);
        }
    }

    override void on_shutdown() {
        _buffers.destroy_buffer(_mesh.vertices);
        _buffers.destroy_buffer(_mesh.indices);
        _memory_pool.clear();
        destroy(_memory_pool);
        destroy(_device_memory);
        destroy(_displays);
    }

    override void run() {
        auto device = _renderer.device;

        while (_displays.is_live(_display_id)) {
            _displays.process_events(false);

            if (!_displays.is_live(_display_id))
                continue;

            if (_displays.is_visible(_display_id)) {
                VulkanFrame frame;
                get_next_frame(_displays, _display_id, frame);

                {
                    record_preamble(device, *_renderer.rp1, frame.command_buffer, _renderer.fb(frame.image.index), frame.image.image_size);
                    record_mesh_draw(device.dispatch_table, frame.command_buffer, _buffers, _mesh);
                    record_postamble(device, *_renderer.rp1, frame.command_buffer);
                }
                {
                    uint wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
                    VkSubmitInfo submit_i = {
                        waitSemaphoreCount: 1,
                        pWaitSemaphores: &frame.acquire,
                        pWaitDstStageMask: &wait_stage,
                        commandBufferCount: 1,
                        pCommandBuffers: &frame.command_buffer,
                        signalSemaphoreCount: 1,
                        pSignalSemaphores: &frame.present
                    };

                    wait_and_reset(device, frame.fence);

                    _renderer.submit(submit_i, frame.fence);
                }

                swap_buffers(_displays, _display_id);
            }
        }
    }

private:
    VulkanContext _vulkan;

    DisplayId _display_id;
    DisplayManager _displays;

    VulkanRenderer _renderer;

    RawDeviceMemoryAllocator _device_memory;
    LinearPool _memory_pool;
    BufferManager _buffers;

    GpuMesh _mesh;
}
