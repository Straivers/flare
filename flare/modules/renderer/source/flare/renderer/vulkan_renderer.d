module flare.renderer.vulkan_renderer;

public import flare.renderer.renderer;
import flare.vulkan.api;

struct Frame {
    uint index;
    VkFramebuffer framebuffer;
    VkExtent2D image_size;

    VkFence frame_complete_fence;
    VkSemaphore image_acquire;
    VkSemaphore render_complete;

    VkRenderPass render_pass;
    VkCommandBuffer graphics_commands;
}

final class VulkanRenderer : Renderer {
    import flare.core.os.types : OsWindow;
    import flare.core.memory.object_pool: ObjectPool;

    /// Vulkan instance extensions required by the renderer.
    static immutable required_instance_extensions = [
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_WIN32_SURFACE_EXTENSION_NAME
    ];

    /// Vulkan device extensions required by the renderer.
    static immutable required_device_extensions = [
        VK_KHR_SWAPCHAIN_EXTENSION_NAME
    ];

    enum max_frames_in_flight = max_swapchains * 3;

nothrow public:
    this(VulkanContext context) {
        _instance = context;
        _swapchains = ObjectPool!(SwapchainInfo, 64)(SwapchainInfo.init);
    }

    ~this() {
        _device.wait_idle();

        foreach (slot; _swapchains.get_all_allocated()) {
            destroy_unchecked(slot.handle);
        }

        object.destroy(graphics_command_pool);
        object.destroy(_device);
    }

    VulkanDevice get_logical_device() {
        return _device;
    }

    Swapchain* get_swapchain(SwapchainId id) {
        if (auto slot = _swapchains.get(id))
            return &slot.swapchain;
        return null;
    }

    override SwapchainId create_swapchain(OsWindow window) {
        auto surface = _instance.create_surface(window);

        if (!_device)
            init_renderer(surface);

        auto slot = _swapchains.alloc();
        slot.surface = surface;
        flare.vulkan.api.create_swapchain(_device, graphics_command_pool, surface, slot.swapchain);

        return slot.handle;
    }

    override void destroy(SwapchainId id) {
        if (auto slot = _swapchains.get(id)) {
            destroy_unchecked(id);
        }
    }

    override void resize(SwapchainId id, ushort width, ushort height) {
        if (auto slot = _swapchains.get(id)) {
            // if (slot.handle is null)
                flare.vulkan.api.recreate_swapchain(_device, graphics_command_pool, slot.surface, slot.swapchain);
        }
    }

    override void swap_buffers(SwapchainId id) {
        if (auto slot = _swapchains.get(id)) {
            flare.vulkan.api.swap_buffers(_device, &slot.swapchain);

            if (slot.state == VK_ERROR_OUT_OF_DATE_KHR || slot.state == VK_SUBOPTIMAL_KHR)
                recreate_swapchain(_device, graphics_command_pool, slot.surface, slot.swapchain);
        }
    }

    void submit(ref Frame frame) {
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

    Frame get_frame(SwapchainId id) {
        if (auto slot = _swapchains.get(id)) {
            assert(slot.swapchain.handle, "Cannot get swapchain frame from hidden window!");

            SwapchainImage image;
            acquire_next_image(_device, &slot.swapchain, image);

            while (slot.state == VK_ERROR_OUT_OF_DATE_KHR) {
                recreate_swapchain(_device, graphics_command_pool, slot.surface, slot.swapchain);
                acquire_next_image(_device, &slot.swapchain, image);
            }

            return Frame(
                image.index,
                image.framebuffer,
                slot.swapchain.image_size,
                image.frame_fence,
                image.image_acquire,
                image.render_complete,
                slot.swapchain.render_pass,
                image.command_buffer
            );
        }

        assert(0, "Cannot get frame from invalid swapchain id");
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

    void destroy_unchecked(SwapchainId handle) {
        auto slot = _swapchains.get(handle);

        if (slot.handle) {
            flare.vulkan.api.destroy_swapchain(_device, graphics_command_pool, slot.swapchain);
        }
        vkDestroySurfaceKHR(_instance.instance, slot.surface, null);
        _swapchains.free(handle);
    }

    VulkanContext _instance;
    VulkanDevice _device;
    CommandPool graphics_command_pool;

    ObjectPool!(SwapchainInfo, 64) _swapchains;
}

private:

struct SwapchainInfo {
    import flare.vulkan.api: VkSurfaceKHR, Swapchain;

    Swapchain swapchain;
    alias swapchain this;

    VkSurfaceKHR surface;
}
