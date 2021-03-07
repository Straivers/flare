module flare.vulkan_renderer.vulkan_renderer;

import flare.renderer.renderer;
import flare.core.memory;
import flare.core.os.types: OsWindow;
import flare.vulkan;
import flare.vulkan_renderer.window;

// TEMP
import flare.vulkan_renderer.mesh;
import flare.vulkan_renderer.rp1;
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
    this(VulkanContext context, size_t max_windows) {
        _context = context;
        _windows = ObjectPool!VulkanWindow(_context.memory, max_windows);
    }

    ~this() {
        destroy(_command_pool);
        destroy_renderpass(_device, _renderpass);
        _device.dispatch_table.DestroyShaderModule(_vertex_shader);
        _device.dispatch_table.DestroyShaderModule(_fragment_shader);

        if (_device)
            destroy(_device);

        destroy(_windows);
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

    VulkanWindow* on_window_create(DisplayId id, ref VulkanWindowOverrides overrides, OsWindow hwnd) {
        auto window = _windows.make(id, this, overrides, true);
        window.surface = create_surface(_context, hwnd);

        if (!_device)
            _initialize(window.surface);

        // Swapchain construction deferred to first get_next_frame()

        foreach (i; 0 .. window.num_virtual_frames) {
            window.fences[i] = _device.fence_pool.acquire(true);
            window.acquire_semaphores[i] = _device.semaphore_pool.acquire();
            window.present_semaphores[i] = _device.semaphore_pool.acquire();
        }

        _command_pool.allocate(window.command_buffers);

        return window;
    }

    void on_window_destroy(VulkanWindow* window) {
        foreach (i; 0 .. window.num_virtual_frames) {
            _device.fence_pool.release(window.fences[i]);
            _device.semaphore_pool.release(window.acquire_semaphores[i]);
            _device.semaphore_pool.release(window.present_semaphores[i]);
        }

        _command_pool.free(window.command_buffers);

        destroy_swapchain(_device, window.swapchain);
        on_swapchain_destroy(window);
        vkDestroySurfaceKHR(_context.instance, window.surface, null);
        _windows.dispose(window);
    }

    void on_swapchain_create(VulkanWindow* window) {
        if (_renderpass.handle && _renderpass.swapchain_attachment.format != window.swapchain.format) {
            destroy_renderpass(_device, _renderpass);
        }

        if (!_renderpass.handle) {
            VkVertexInputAttributeDescription[2] attrs = Vertex.attribute_descriptions;
            RenderPassSpec rps = {
                swapchain_attachment: AttachmentSpec(window.swapchain.format, [0, 0, 0, 1]),
                vertex_shader: _vertex_shader,
                fragment_shader: _fragment_shader,
                bindings: Vertex.binding_description,
                attributes: attrs
            };

            create_renderpass_1(_device, rps, _renderpass);
        }

        _framebuffers = _context.memory.make_array!VkFramebuffer(window.swapchain.images.length);
        foreach (i, ref fb; _framebuffers) {
            VkFramebufferCreateInfo framebuffer_ci = {
                renderPass: _renderpass.handle,
                attachmentCount: 1,
                pAttachments: &window.swapchain.views[i],
                width: window.swapchain.image_size.width,
                height: window.swapchain.image_size.height,
                layers: 1
            };

            _device.dispatch_table.CreateFramebuffer(framebuffer_ci, fb);
        }
    }

    void on_swapchain_resize(VulkanWindow* window) {
        wait(_device, window.fences);

        assert(window.swapchain.n_images == _framebuffers.length);

        foreach (fb; _framebuffers)
            _device.dispatch_table.DestroyFramebuffer(fb);

        foreach (i, ref fb; _framebuffers) {
            VkFramebufferCreateInfo framebuffer_ci = {
                renderPass: _renderpass.handle,
                attachmentCount: 1,
                pAttachments: &window.swapchain.views[i],
                width: window.swapchain.image_size.width,
                height: window.swapchain.image_size.height,
                layers: 1
            };

            _device.dispatch_table.CreateFramebuffer(framebuffer_ci, fb);
        }
    }

    void on_swapchain_destroy(VulkanWindow* window) {
        wait(_device, window.fences);

        foreach (fb; _framebuffers)
            _device.dispatch_table.DestroyFramebuffer(fb);
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
        
        _command_pool = create_graphics_command_pool(_device);

        _vertex_shader = load_shader(_device, "shaders/vert.spv");
        _fragment_shader = load_shader(_device, "shaders/frag.spv");
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

    ObjectPool!VulkanWindow _windows;
}
