module flare.renderer.vulkan.vulkan_renderer;

import flare.limits : max_open_windows;
import flare.memory;
import flare.renderer.renderer;
import flare.renderer.vulkan.api;
import flare.util.handle_pool;

public import flare.renderer.renderer : SwapchainId;

// TEMP
import flare.renderer.vulkan.mesh;
import flare.renderer.vulkan.rp1;
// TEMP

struct VulkanFrame {
    SwapchainImage image;

    VkFence fence;
    VkCommandBuffer command_buffer;

    VkSemaphore acquire;
    VkSemaphore present;
}

final class VulkanRenderer : Renderer {
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
        _swapchains = SwapchainPool(_context.memory);
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

    SwapchainId create_swapchain(void* hwnd, bool vsync) {
        auto swapchain_id = _swapchains.make(vsync);
        auto swapchain = _swapchains.get(swapchain_id);
        swapchain.surface = create_surface(_context, hwnd);
        // Swapchain creation handled on first resize operation.

        if (!_device)
            _initialize(swapchain.surface);

        swapchain.initialize_resources(_device, &_command_pool);
        return swapchain_id;
    }

    void destroy_swapchain(SwapchainId id) {
        auto swapchain = _swapchains.get(id);
        wait(_device, swapchain.fences);

        foreach (fb; _framebuffers)
            _device.dispatch_table.DestroyFramebuffer(fb);
        _context.memory.dispose(_framebuffers);

        swapchain.destroy_resources(_device, &_command_pool);
        flare.renderer.vulkan.api.destroy_swapchain(_device, swapchain.surface, swapchain.swapchain);
        vkDestroySurfaceKHR(_context.instance, swapchain.surface, null);
        _swapchains.dispose(id);
    }

    void resize_swapchain(SwapchainId id) {
        auto swapchain = _swapchains.get(id);
        wait(_device, swapchain.fences);

        flare.renderer.vulkan.api.resize_swapchain(_device, swapchain.surface, swapchain.swapchain);

        foreach (fb; _framebuffers)
            _device.dispatch_table.DestroyFramebuffer(fb);

        resize_array(_context.memory, _framebuffers, swapchain.n_images);
        foreach (i, ref fb; _framebuffers) {
            fb = _create_framebuffer(_device, _renderpass.handle, swapchain.image_size.width, swapchain.image_size.height, swapchain.views[i]);
        }
    }

    void get_frame(SwapchainId id, out VulkanFrame frame) {
        auto swapchain = _swapchains.get(id);

        frame.fence = swapchain.fences[swapchain.virtual_frame_id];
        frame.command_buffer = swapchain.command_buffers[(swapchain.double_buffer_id * swapchain.num_virtual_frames) + swapchain.virtual_frame_id];
        frame.acquire = swapchain.acquire_semaphores[swapchain.virtual_frame_id];
        frame.present = swapchain.present_semaphores[swapchain.virtual_frame_id];

        // Initialize swapchain if this is the first time get_frame() has been
        // called on it.
        if (!swapchain.handle) {
            _initialize_swapchain(swapchain);
            if (!acquire_next_image(_device, swapchain.swapchain, frame.acquire))
                // We assume that after resize_swapchain, there is no need to
                // check again if the swapchain is valid.
                assert(0, "Assumption about swapchain resize/acquire sequence violated.");
        }

        get_image(swapchain.swapchain, frame.image);
    }

    void present_swapchain(SwapchainId id) {
        auto swapchain = _swapchains.get(id);

        // If swap_buffers() fails, we skip a frame, and continue rendering.
        if (!swap_buffers(_device, swapchain.swapchain, swapchain.present_semaphores[swapchain.virtual_frame_id]))
            resize_swapchain(id);

        swapchain.double_buffer_id ^= 1;
        swapchain.virtual_frame_id = (swapchain.virtual_frame_id + 1) % swapchain.num_virtual_frames;

        // We assume here that if the swapchain needs resizing when
        // present_swapchain() is called, it will be caught by
        // if(!swap_buffers(...)).
        if (!acquire_next_image(_device, swapchain.swapchain, swapchain.acquire_semaphores[swapchain.virtual_frame_id]))
            assert(0, "Assumption about swapchain resize/acquire sequence violated.");
    }

private:
    alias SwapchainPool = HandlePool!(_Swapchain, swapchain_handle_name, max_open_windows);

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

    void _initialize_swapchain(_Swapchain* swapchain) {
        flare.renderer.vulkan.api.create_swapchain(_device, swapchain.surface, swapchain.vsync, swapchain.swapchain);
    
        const VkVertexInputAttributeDescription[2] attrs = Vertex.attribute_descriptions;
        RenderPassSpec rps = {
            swapchain_attachment: AttachmentSpec(swapchain.format, [0, 0, 0, 1]),
            vertex_shader: _vertex_shader,
            fragment_shader: _fragment_shader,
            bindings: Vertex.binding_description,
            attributes: attrs
        };

        create_renderpass_1(_device, rps, _renderpass);

        _framebuffers = _context.memory.make_array!VkFramebuffer(swapchain.images.length);
        foreach (i, ref fb; _framebuffers) {
            fb = _create_framebuffer(_device, _renderpass.handle, swapchain.image_size.width, swapchain.image_size.height, swapchain.views[i]);
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

    SwapchainPool _swapchains;
}

private:

struct _Swapchain {
    enum num_virtual_frames = 3;

    bool vsync;

    alias swapchain this;
    Swapchain swapchain;
    VkSurfaceKHR surface;

    size_t virtual_frame_id;
    size_t double_buffer_id;

    VkFence[num_virtual_frames] fences;
    VkCommandBuffer[num_virtual_frames * 2] command_buffers;

    VkSemaphore[num_virtual_frames] acquire_semaphores;
    VkSemaphore[num_virtual_frames] present_semaphores;

    void initialize_resources(VulkanDevice device, CommandPool* command_pool) nothrow {
        foreach (i; 0 .. num_virtual_frames) {
            fences[i] = device.fence_pool.acquire(true);
            acquire_semaphores[i] = device.semaphore_pool.acquire();
            present_semaphores[i] = device.semaphore_pool.acquire();
        }

        command_pool.allocate(command_buffers);
    }

    void destroy_resources(VulkanDevice device, CommandPool* command_pool) nothrow {
        foreach (i; 0 .. num_virtual_frames) {
            device.fence_pool.release(fences[i]);
            device.semaphore_pool.release(acquire_semaphores[i]);
            device.semaphore_pool.release(present_semaphores[i]);
        }

        command_pool.free(command_buffers);
    }
}

VkFramebuffer _create_framebuffer(VulkanDevice device, VkRenderPass rp, uint width, uint height, VkImageView view) nothrow {
    VkFramebufferCreateInfo ci = {
        renderPass: rp,
        attachmentCount: 1,
        pAttachments: &view,
        width: width,
        height: height,
        layers: 1
    };

    VkFramebuffer fb;
    device.dispatch_table.CreateFramebuffer(ci, fb);
    return fb;
}
