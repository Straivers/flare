module sandbox;

import flare.application;
import flare.core.math.vector;
import flare.vulkan;
import flare.core.memory;
import flare.vulkan_renderer;
import flare.display;
import flare.core.time;
import flare.core.buffer_writer;
import std.format;

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

class Sandbox : FlareApp {
    import flare.core.memory: AllocatorApi, BuddyAllocator, mib;

public:
    this(ref FlareAppSettings settings) {
        super(settings);

        {
            ContextOptions options = {
                api_version: VkVersion(1, 2, 0),
                memory: memory,
                parent_logger: &log,
                layers: [VK_LAYER_KHRONOS_VALIDATION_NAME],
                extensions: VulkanRenderer.required_instance_extensions
            };

            _vulkan = init_vulkan(options);
            _renderer = new VulkanRenderer(_vulkan, displays.max_open_displays);
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
                vsync: true,
                callbacks: {
                    on_key: (mgr, id, usr, key, state) nothrow {
                        if (key == KeyCode.Escape && state == ButtonState.Released)
                            mgr.close(id);
                    },
                    on_close: (mgr, id, user) nothrow {
                        mgr.destroy(id);
                    }
                }
            };

            _display_id = create_vulkan_window(displays, _renderer, properties);
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
        destroy(_renderer);
    }

    override void on_update(Duration dt) {
        import std.stdio;
        writeln("on_update: ", dt.to_msecs);
    }

    override void on_draw(Duration dt) {
        if (!displays.is_live(_display_id))
            return;
        
        if (!displays.is_visible(_display_id))
            return;

        char[256] title_storage;
        auto writer = TypedWriter!char(title_storage);
        formattedWrite(writer, "%s: %s fps", app_settings.name, 1.secs / dt);
        displays.retitle(_display_id, writer.data);
        writer.clear();

        auto device = _renderer.device;

        VulkanFrame frame;
        get_next_frame(displays, _display_id, frame);
        wait_and_reset(device, frame.fence);

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

            _renderer.submit(submit_i, frame.fence);
        }

        swap_buffers(displays, _display_id);
    }

private:
    VulkanContext _vulkan;

    DisplayId _display_id;

    VulkanRenderer _renderer;

    RawDeviceMemoryAllocator _device_memory;
    LinearPool _memory_pool;
    BufferManager _buffers;

    GpuMesh _mesh;
}
