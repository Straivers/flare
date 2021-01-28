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

        SwapchainProperties properties;
        get_swapchain_properties(_device, surface, properties);

        if (properties.image_size != VkExtent2D()) {
            flare.vulkan.create_swapchain(_device, surface, properties, slot.swapchain);
            slot.init_or_resize_frames(_device, graphics_command_pool);
        }

        return handle.to!SwapchainId;
    }

    override void destroy(SwapchainId id) {
        auto swapchain = _swapchains.get(SwapchainHandle.from!SwapchainId(id));
        
        if (swapchain.handle) {
            foreach (ref frame; swapchain.frames)
                destroy_frame(_device, frame);

            flare.vulkan.destroy_swapchain(_device, swapchain.swapchain);
            _device.dispatch_table.DestroyRenderPass(swapchain.render_pass);
        }
        else
            assert(!swapchain.frames);

        vkDestroySurfaceKHR(_instance.instance, swapchain.surface, null);
        _swapchains.deallocate(SwapchainHandle.from!SwapchainId(id));

    }

    override void resize(SwapchainId id, ushort width, ushort height) {
        auto slot = _swapchains.get(SwapchainHandle.from!SwapchainId(id));

        SwapchainProperties properties;
        get_swapchain_properties(_device, slot.surface, properties);
        
        const was_zero_size = slot.image_size == VkExtent2D();
        const is_zero_size = properties.image_size == VkExtent2D();

        if (was_zero_size && !is_zero_size) {
            flare.vulkan.create_swapchain(_device, slot.surface, properties, slot.swapchain);
            slot.render_pass = _create_render_pass(_device, slot.swapchain.format);
        }
        else if (!was_zero_size && !is_zero_size) {
            const old_format = slot.swapchain.format;
            
            flare.vulkan.resize_swapchain(_device, slot.surface, properties, slot.swapchain);

            if (slot.swapchain.format != old_format) {
                _device.dispatch_table.DestroyRenderPass(slot.render_pass);
                slot.render_pass = _create_render_pass(_device, slot.swapchain.format);
            }
        }
        else if (!was_zero_size && is_zero_size) {
            flare.vulkan.destroy_swapchain(_device, slot.swapchain);
            _device.dispatch_table.DestroyRenderPass(slot.render_pass);
            slot.render_pass = null;
        }
        else {
            // was_zero_size && is_zero_size
            // Is this possible, and does it do anything?
            assert(0);
        }

        slot.init_or_resize_frames(_device, graphics_command_pool);
    }

    override void swap_buffers(SwapchainId id) {
        auto slot = _swapchains.get(SwapchainHandle.from!SwapchainId(id));
        flare.vulkan.swap_buffers(_device, &slot.swapchain, slot.current_frame().render_complete);
        slot.frame_counter = (slot.frame_counter + 1) % slot.frames.length;

        if (slot.state == VK_ERROR_OUT_OF_DATE_KHR || slot.state == VK_SUBOPTIMAL_KHR) {
            resize(id, 0, 0);
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

        auto frame = &slot.frames[slot.frame_counter];
        auto image_index = acquire_next_image(_device, &slot.swapchain, frame.image_acquire, frame.frame_complete_fence);

        while (slot.swapchain.state == VK_ERROR_OUT_OF_DATE_KHR) {
            resize(id, 0, 0);
            image_index = acquire_next_image(_device, &slot.swapchain, frame.image_acquire, frame.frame_complete_fence);
        }

        return frame;
    }

    VkRenderPass get_renderpass(SwapchainId id) {
        return _swapchains.get(SwapchainHandle.from(id)).render_pass;
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
    VkRenderPass render_pass;

    Frame* current_frame() nothrow return {
        return &frames[frame_counter];
    }

    void init_or_resize_frames(VulkanDevice device, CommandPool command_pool) nothrow {
        import std.algorithm: min;
        
        const num_frames = swapchain.images.length;
        const num_shared = min(num_frames, frames.length);

        // Resize frames
        foreach (i, ref frame; frames[0 .. num_shared]) {
            FramebufferAttachmentSpec[1] attachments = [FramebufferAttachmentSpec(swapchain.views[i])];
            resize_frame(device, frame, swapchain.image_size, attachments, render_pass);
        }

        // Add more frames
        if (num_frames > num_shared) {
            device.context.memory.resize_array(frames, num_frames);

            foreach (i, ref frame; frames[num_shared .. $]) {
                FramebufferAttachmentSpec[1] attachments = [FramebufferAttachmentSpec(swapchain.views[i])];

                FrameSpec spec = {
                    render_pass: render_pass,
                    framebuffer_size: swapchain.image_size,
                    framebuffer_attachments: attachments,
                    graphics_commands: command_pool.allocate(),
                };

                init_frame(device, spec, frame);
            }
        }
        // Remove extra frames
        else if (num_frames == 0 || num_frames < num_shared) {
            foreach (ref frame; frames[num_shared .. $]) {
                destroy_frame(device, frame);
                command_pool.free(frame.graphics_commands);
            }

            device.context.memory.resize_array(frames, num_frames);
        }
    }
}

VkRenderPass _create_render_pass(VulkanDevice device, VkFormat format) {
    VkAttachmentDescription color_attachment = {
        format: format,
        samples: VK_SAMPLE_COUNT_1_BIT,
        loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
        storeOp: VK_ATTACHMENT_STORE_OP_STORE,
        stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
        finalLayout: VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    };

    VkAttachmentReference color_attachment_ref = {
        attachment: 0,
        layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    };

    VkSubpassDescription subpass = {
        pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
        colorAttachmentCount: 1,
        pColorAttachments: &color_attachment_ref
    };

    VkSubpassDependency dependency = {
        srcSubpass: VK_SUBPASS_EXTERNAL,
        dstSubpass: 0,
        srcStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        srcAccessMask: 0,
        dstStageMask: VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        dstAccessMask: VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };

    VkRenderPassCreateInfo ci = {
        attachmentCount: 1,
        pAttachments: &color_attachment,
        subpassCount: 1,
        pSubpasses: &subpass,
        dependencyCount: 1,
        pDependencies: &dependency
    };

    VkRenderPass render_pass;
    device.dispatch_table.CreateRenderPass(ci, render_pass);
    return render_pass;
}
