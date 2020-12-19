module flare.renderer.vulkan_renderer;

public import flare.renderer.renderer;

final class VulkanRenderer : Renderer {
    import flare.core.os.types : OsWindow;
    import flare.vulkan.api;

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
    }

    ~this() {
        foreach (ref swapchain; _swapchains) {
            if (swapchain)
                destroy_unchecked(&swapchain);
        }

        object.destroy(_device);
    }

    VulkanDevice get_logical_device() {
        return _device;
    }

    Swapchain* get_swapchain(SwapchainId id) {
        if (auto slot = get_swapchain_from_id(id))
            return &slot.swapchain;
        return null;
    }

    override SwapchainId create_swapchain(OsWindow window) {
        auto surface = _instance.create_surface(window);

        if (!_device)
            init_renderer(surface);

        size_t index;
        SwapchainInfo* info = () {
            foreach (i, ref swap; _swapchains)
                if (swap.id == SwapchainIdImpl()) {
                    index = i;
                    return &swap;
                }
            
            return null;
        } ();

        assert(info, "All window slots are occupied! Unable to create new windows.");

        info.id.index = cast(ubyte) index;
        info.surface = surface;
        flare.vulkan.api.create_swapchain(_device, surface, info.swapchain);

        return info.id.value;
    }

    override void destroy(SwapchainId id) {
        if (auto slot = get_swapchain_from_id(id)) {
            destroy_unchecked(slot);
        }
        else {
            assert(false, "Attempted to manipulate nonexistent swapchain");
        }
    }

    override void resize(SwapchainId id, ushort width, ushort height) {
        if (auto slot = get_swapchain_from_id(id)) {
            //*************** TODO ***************//
        }
        else {
            assert(false, "Attempted to manipulate nonexistent swapchain");
        }
    }

    override void swap_buffers(SwapchainId id) {
        if (auto slot = get_swapchain_from_id(id)) {
            slot.swap_buffers(_device);
        }
        else {
                assert(false, "Attempted to manipulate nonexistent swapchain");
        }
    }

    Frame get_frame(SwapchainId id) {
        if (auto slot = get_swapchain_from_id(id)) {
            return slot.get_frame(_device);
        }
        else {
            assert(false, "Attempted to manipulate nonexistent swapchain");
        }
    }

nothrow private:
    void init_renderer(VkSurfaceKHR surface) {
        _device = () nothrow {
            VulkanDeviceCriteria reqs = {
                graphics_queue: true,
                required_extensions: required_device_extensions,
                display_target: surface
            };

            VulkanGpuInfo gpu;
            _instance.select_gpu(reqs, gpu);
            return _instance.create_device(gpu);
        } ();
    }

    SwapchainInfo* get_swapchain_from_id(SwapchainId id) {
        auto swap_id = SwapchainIdImpl(id);
        const slot_id = _swapchains[swap_id.index].id;

        if (id == slot_id.value)
            return &_swapchains[swap_id.index];

        return null;
    }

    void destroy_unchecked(SwapchainInfo* slot) {
        slot.id.generation++;

        flare.vulkan.api.destroy_swapchain(_device, slot.swapchain);
        vkDestroySurfaceKHR(_instance.instance, slot.surface, null);
    }

    VulkanContext _instance;
    VulkanDevice _device;

    SwapchainInfo[max_swapchains] _swapchains;
}

private:

struct SwapchainIdImpl {
    union {
        SwapchainId value;

        struct {
            ubyte index;
            ubyte[1] pad0;
            ushort generation;
            ubyte[4] pad1;
        }
    }
}

struct SwapchainInfo {
    import flare.vulkan.h: VkSurfaceKHR;
    import flare.vulkan.swapchain: Swapchain;

    SwapchainIdImpl id;
    Swapchain swapchain;

    VkSurfaceKHR surface;

    alias swapchain this;
}
