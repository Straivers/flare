module flare.vulkan_renderer.renderer;

public import flare.renderer.renderer;
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

        slot.frames = _instance.memory.make_array!Frame(slot.swapchain.views.length);

        foreach (i, ref frame; slot.frames) {
            FrameSpec spec = {
                render_pass: slot.swapchain.render_pass,
                framebuffer_size: slot.swapchain.image_size,
                graphics_commands: graphics_command_pool.allocate(),
            };

            FramebufferAttachmentSpec[1] attachments = [FramebufferAttachmentSpec(slot.swapchain.views[i])];
            spec.framebuffer_attachments = attachments;

            init_frame(_device, spec, frame);
        }

        return handle.to!SwapchainId;
    }

    override void destroy(SwapchainId id) {
        auto swapchain = _swapchains.get(SwapchainHandle.from!SwapchainId(id));
        
        flare.vulkan.destroy_swapchain(_device, swapchain.swapchain);
        vkDestroySurfaceKHR(_instance.instance, swapchain.surface, null);
        _swapchains.deallocate(SwapchainHandle.from!SwapchainId(id));

        foreach (ref frame; swapchain.frames)
            destroy_frame(_device, frame);
    }

    override void resize(SwapchainId id, ushort width, ushort height) {
        auto slot = _swapchains.get(SwapchainHandle.from!SwapchainId(id));
        flare.vulkan.recreate_swapchain(_device, slot.surface, slot.swapchain);

        if (slot.frames.length != slot.swapchain.views.length) {
            _instance.memory.dispose(slot.frames);
            slot.frames = _instance.memory.make_array!Frame(slot.swapchain.views.length);

            foreach (i, ref frame; slot.frames) {
                FrameSpec spec = {
                    render_pass: slot.swapchain.render_pass,
                    framebuffer_size: slot.swapchain.image_size,
                    graphics_commands: graphics_command_pool.allocate(),
                };

                // auto tmp = TempAllocator(_device.context.memory);
                // spec.framebuffer_attachments = tmp.alloc_array!FramebufferAttachmentSpec(1);
                // spec.framebuffer_attachments[0] = FramebufferAttachmentSpec(slot.swapchain.views[i]);
                spec.framebuffer_attachments = [FramebufferAttachmentSpec(slot.swapchain.views[i])];

                init_frame(_device, spec, frame);
            }
        }

        foreach (ref frame; slot.frames)
            resize_frame(_device, frame, slot.swapchain.image_size);
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
        auto current_frame = slot.current_frame();

        SwapchainImage image;
        acquire_next_image(_device, &slot.swapchain, current_frame.image_acquire, current_frame.frame_complete_fence, image);

        while (slot.state == VK_ERROR_OUT_OF_DATE_KHR) {
            recreate_swapchain(_device, slot.surface, slot.swapchain);
            acquire_next_image(_device, &slot.swapchain, current_frame.image_acquire, current_frame.frame_complete_fence, image);
            
            foreach (ref frame; slot.frames)
                frame.resize(_device, slot.swapchain.image_size);
        }

        return current_frame;
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
}
