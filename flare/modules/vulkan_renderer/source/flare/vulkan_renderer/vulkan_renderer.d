module flare.vulkan_renderer.vulkan_renderer;

import flare.renderer.renderer;
import flare.core.memory;
import flare.vulkan;
import flare.vulkan_renderer.frame;

final class VulkanRenderer : Renderer {
    import flare.core.os.types : OsWindow;

    /// Vulkan instance extensions required by the renderer.
    static immutable required_instance_extensions = [
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_WIN32_SURFACE_EXTENSION_NAME
    ];

    /// Vulkan device extensions required by the renderer.
    static immutable required_device_extensions = [
        VK_KHR_SWAPCHAIN_EXTENSION_NAME
    ];

    enum max_frames_in_flight = 3;

nothrow public:
    this(VulkanContext context) {
        _instance = context;
        _swapchains = WeakObjectPool!SwapchainInfo(_instance.memory, 64);
    }

    ~this() {
        _device.wait_idle();

        object.destroy(graphics_command_pool);
        object.destroy(_device);
    }

    VulkanDevice get_logical_device() {
        return _device;
    }

    Swapchain* get_swapchain(SwapchainId id) {
        return &_swapchains.get(SwapchainHandle.from!SwapchainId(id)).swapchain;
    }

    override SwapchainId create_swapchain(OsWindow window) {
        auto surface = _instance.create_surface(window);

        if (!_device)
            init_renderer(surface);

        auto handle = _swapchains.allocate();
        auto slot = _swapchains.get(handle);
        slot.surface = surface;

        // These are only necessary if the window is already of > VkExtent2D(0, 0) size.
        flare.vulkan.create_swapchain(_device, surface, slot.swapchain);
        slot.init_or_resize_frames(_device, graphics_command_pool);

        return handle.to!SwapchainId;
    }

    override void destroy(SwapchainId id) {
        auto swapchain = _swapchains.get(SwapchainHandle.from!SwapchainId(id));
        
        if (swapchain.handle) {
            flare.vulkan.destroy_swapchain(_device, swapchain.swapchain);

            foreach (ref frame; swapchain.frames)
                destroy_frame(_device, frame);
        }
        else
            assert(!swapchain.frames);

        vkDestroySurfaceKHR(_instance.instance, swapchain.surface, null);
        _swapchains.deallocate(SwapchainHandle.from!SwapchainId(id));

    }

    override void resize(SwapchainId id, ushort width, ushort height) {
        auto slot = _swapchains.get(SwapchainHandle.from!SwapchainId(id));
        flare.vulkan.recreate_swapchain(_device, slot.surface, slot.swapchain);
        slot.init_or_resize_frames(_device, graphics_command_pool);
    }

    override void swap_buffers(SwapchainId id) {
        auto slot = _swapchains.get(SwapchainHandle.from!SwapchainId(id));
        flare.vulkan.swap_buffers(_device, &slot.swapchain, slot.current_frame().render_complete);
        slot.frame_counter = (slot.frame_counter + 1) % slot.frames.length;

        if (slot.state == VK_ERROR_OUT_OF_DATE_KHR || slot.state == VK_SUBOPTIMAL_KHR) {
            recreate_swapchain(_device, slot.surface, slot.swapchain);

            foreach (ref frame; slot.frames)
                frame.resize(_device, slot.swapchain.image_size);
        }
    }

    void submit(Frame* frame) {
        VkPipelineStageFlags wait_stages = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        VkSubmitInfo si = {
            waitSemaphoreCount: 1,
            pWaitSemaphores: &frame.image_acquire,
            pWaitDstStageMask: &wait_stages,
            commandBufferCount: 1,
            pCommandBuffers: &frame.graphics_commands,
            signalSemaphoreCount: 1,
            pSignalSemaphores: &frame.render_complete
        };

        graphics_command_pool.submit(_device.graphics, frame.frame_complete_fence, si);
    }

    Frame* get_frame(SwapchainId id) {
        auto slot = _swapchains.get(SwapchainHandle.from!SwapchainId(id));
        assert(slot.swapchain.handle, "Cannot get swapchain frame from hidden window!");

        return slot.next_frame(_device);
    }

nothrow private:
    void init_renderer(VkSurfaceKHR surface) {
        {
            VulkanDeviceCriteria reqs = {
                graphics_queue: true,
                transfer_queue: true,
                required_extensions: required_device_extensions,
                display_target: surface
            };

            VulkanGpuInfo gpu;
            if (_instance.select_gpu(reqs, gpu))
                _device = _instance.create_device(gpu);
            else
                assert(0, "No suitable GPU was detected.");
        }

        graphics_command_pool = create_graphics_command_pool(_device);
    }

    alias SwapchainHandle = _swapchains.Handle;

    VulkanContext _instance;
    VulkanDevice _device;
    CommandPool graphics_command_pool;

    WeakObjectPool!SwapchainInfo _swapchains;
}

private nothrow:

struct SwapchainInfo {
    import flare.vulkan: VkSurfaceKHR, Swapchain;

    Swapchain swapchain;
    alias swapchain this;

    Frame[] frames;
    size_t frame_counter;

    VkSurfaceKHR surface;

    Frame* current_frame() nothrow return {
        return &frames[frame_counter];
    }

    Frame* next_frame(VulkanDevice device) nothrow return {
        auto frame = &frames[frame_counter];
        auto image_index = acquire_next_image(device, &swapchain, frame.image_acquire, frame.frame_complete_fence);

        while (swapchain.state == VK_ERROR_OUT_OF_DATE_KHR) {
            recreate_swapchain(device, surface, swapchain);
            image_index = acquire_next_image(device, &swapchain, frame.image_acquire, frame.frame_complete_fence);

            // TODO: does not handle changing frame count
            foreach (ref f; frames)
                f.resize(device, swapchain.image_size);
        }

        return frame;
    }

    void init_or_resize_frames(VulkanDevice device, CommandPool command_pool) nothrow {
        import std.algorithm: min;
        
        const num_frames = swapchain.images.length;
        const num_shared = min(num_frames, frames.length);

        // Resize frames
        foreach (ref frame; frames[0 .. num_shared]) {
            frame.resize(device, swapchain.image_size);
        }

        // Add more frames
        if (num_frames > num_shared) {
            device.context.memory.resize_array(frames, num_frames);

            foreach (i, ref frame; frames[num_shared .. $]) {
                FramebufferAttachmentSpec[1] attachments = [FramebufferAttachmentSpec(swapchain.views[i])];

                FrameSpec spec = {
                    render_pass: swapchain.render_pass,
                    framebuffer_size: swapchain.image_size,
                    framebuffer_attachments: attachments,
                    graphics_commands: command_pool.allocate(),
                };

                init_frame(device, spec, frame);
            }
        }
        // Remove extra frames
        else if (num_frames == 0 || num_frames < num_shared) {
            foreach (ref frame; frames[num_shared .. $])
                destroy_frame(device, frame);

            device.context.memory.resize_array(frames, num_frames);
        }
    }
}
