module flare.renderer.vulkan.vulkan_renderer;

import flare.memory;
import flare.renderer.renderer;
import flare.renderer.vulkan.api;
import flare.renderer.vulkan.swapchain;
import flare.util.object_pool;

// TEMP
import flare.renderer.vulkan.mesh;
import flare.renderer.vulkan.rp1;
// TEMP

final class VulkanRenderer {
    /// Vulkan instance extensions required by the renderer.
    static immutable required_instance_extensions = [
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_WIN32_SURFACE_EXTENSION_NAME
    ];

    /// Vulkan device extensions required by the renderer.
    static immutable required_device_extensions = [
        VK_KHR_SWAPCHAIN_EXTENSION_NAME
    ];

nothrow:
    this(VulkanContext context, size_t max_swapchains) {
        _context = context;
        _swapchains = ObjectPool!VulkanSwapchain(_context.memory, max_swapchains);
    }

    ~this() {
        destroy(_command_pool);
        destroy_renderpass(_device, _renderpass);
        _device.dispatch_table.DestroyShaderModule(_vertex_shader);
        _device.dispatch_table.DestroyShaderModule(_fragment_shader);

        if (_device)
            destroy(_device);

        destroy(_swapchains);
    }

    VulkanDevice device() {
        assert(_device);
        return _device;
    }

    // TEMP
    VkFramebuffer fb(size_t i) {
        return _framebuffers[i];
    }

    RenderPass1* rp1() {
        return &_renderpass;
    }

    void submit(ref VkSubmitInfo si, VkFence fence) {
        _command_pool.submit(_device.graphics, fence, si);
    }
    // TEMP

    VulkanSwapchain* create_swapchain(void* hwnd, bool vsync) {
        auto swapchain = _swapchains.make(this, vsync);
        swapchain.surface = create_surface(_context, hwnd);
        // Swapchain creation handled on first resize operation.

        if (!_device)
            _initialize(swapchain.surface);

        swapchain.frames.initialize(_device, &_command_pool);
        return swapchain;
    }

    void destroy_swapchain(VulkanSwapchain* swapchain) {
        wait(_device, swapchain.fences);

        swapchain.frames.destroy(_device, &_command_pool);
        flare.renderer.vulkan.api.destroy_swapchain(_device, swapchain.surface, swapchain.swapchain);

        foreach (fb; _framebuffers)
            _device.dispatch_table.DestroyFramebuffer(fb);

        vkDestroySurfaceKHR(_context.instance, swapchain.surface, null);

        _swapchains.dispose(swapchain);
    }

    void resize_swapchain(VulkanSwapchain* swapchain) {
        wait(_device, swapchain.fences);

        flare.renderer.vulkan.api.resize_swapchain(_device, swapchain.surface, swapchain.swapchain);

        foreach (fb; _framebuffers)
            _device.dispatch_table.DestroyFramebuffer(fb);

        VkFramebufferCreateInfo framebuffer_ci = {
            renderPass: _renderpass.handle,
            attachmentCount: 1,
            width: swapchain.swapchain.image_size.width,
            height: swapchain.swapchain.image_size.height,
            layers: 1
        };

        resize_array(_context.memory, _framebuffers, swapchain.swapchain.n_images);
        foreach (i, ref fb; _framebuffers) {
            framebuffer_ci.pAttachments = &swapchain.swapchain.views[i];
            _device.dispatch_table.CreateFramebuffer(framebuffer_ci, fb);
        }
    }

    void get_frame(VulkanSwapchain* swapchain, out VulkanFrame frame) {
        frame.fence = swapchain.fences[swapchain.virtual_frame_id];
        frame.command_buffer = swapchain.command_buffers[(swapchain.double_buffer_id * swapchain.num_virtual_frames) + swapchain.virtual_frame_id];
        frame.acquire = swapchain.acquire_semaphores[swapchain.virtual_frame_id];
        frame.present = swapchain.present_semaphores[swapchain.virtual_frame_id];

        // Initialize swapchain if this is the first time get_frame() has been
        // called on it.
        if (!swapchain.swapchain.handle) {
            _initialize_swapchain(swapchain);
            if (!acquire_next_image(_device, &swapchain.swapchain, frame.acquire))
                // We assume that after resize_swapchain, there is no need to
                // check again if the swapchain is valid.
                assert(0, "Assumption about swapchain resize/acquire sequence violated.");
        }

        get_image(&swapchain.swapchain, frame.image);
    }

    void present_swapchain(VulkanSwapchain* swapchain) {
        // If swap_buffers() fails, we skip a frame, and continue rendering.
        if (!swap_buffers(_device, &swapchain.swapchain, swapchain.present_semaphores[swapchain.virtual_frame_id]))
            resize_swapchain(swapchain);

        swapchain.double_buffer_id ^= 1;
        swapchain.virtual_frame_id = (swapchain.virtual_frame_id + 1) % swapchain.num_virtual_frames;

        // We assume here that if the swapchain needs resizing when
        // present_swapchain() is called, it will be caught by
        // if(!swap_buffers(...)).
        if (!acquire_next_image(_device, &swapchain.swapchain, swapchain.acquire_semaphores[swapchain.virtual_frame_id]))
            assert(0, "Assumption about swapchain resize/acquire sequence violated.");
    }

private:
    void _initialize(VkSurfaceKHR surface) {
        VulkanDeviceCriteria reqs = {
            graphics_queue: true,
            transfer_queue: true,
            required_extensions: required_device_extensions,
            display_target: surface
        };

        VulkanGpuInfo gpu;
        if (_context.select_gpu(reqs, gpu))
            _device = _context.create_device(gpu);
        else
            assert(0, "No suitable GPU was detected.");

        create_graphics_command_pool(_device, true, _command_pool);

        _vertex_shader = load_shader(_device, "shaders/vert.spv");
        _fragment_shader = load_shader(_device, "shaders/frag.spv");
    }

    void _initialize_swapchain(VulkanSwapchain* swapchain) {
        flare.renderer.vulkan.api.create_swapchain(_device, swapchain.surface, swapchain.vsync, swapchain.swapchain);
    
        const VkVertexInputAttributeDescription[2] attrs = Vertex.attribute_descriptions;
        RenderPassSpec rps = {
            swapchain_attachment: AttachmentSpec(swapchain.swapchain.format, [0, 0, 0, 1]),
            vertex_shader: _vertex_shader,
            fragment_shader: _fragment_shader,
            bindings: Vertex.binding_description,
            attributes: attrs
        };

        create_renderpass_1(_device, rps, _renderpass);

        _framebuffers = _context.memory.make_array!VkFramebuffer(swapchain.swapchain.images.length);
        foreach (i, ref fb; _framebuffers) {
            VkFramebufferCreateInfo framebuffer_ci = {
                renderPass: _renderpass.handle,
                attachmentCount: 1,
                pAttachments: &swapchain.swapchain.views[i],
                width: swapchain.swapchain.image_size.width,
                height: swapchain.swapchain.image_size.height,
                layers: 1
            };

            _device.dispatch_table.CreateFramebuffer(framebuffer_ci, fb);
        }
    }

    // TEMP
    VkFramebuffer[] _framebuffers;
    RenderPass1 _renderpass;
    VkShaderModule _vertex_shader;
    VkShaderModule _fragment_shader;
    // TEMP

    VulkanContext _context;
    VulkanDevice _device;
    CommandPool _command_pool;

    ObjectPool!VulkanSwapchain _swapchains;
}
