module flare.vulkan_renderer.display_manager;

import flare.core.memory;
import flare.vulkan;

public import flare.display.input;
public import flare.display.manager;

alias OnSwapchainCreate = void function(EventSource, Swapchain*) nothrow;
alias OnSwapchainDestroy = void function(EventSource, Swapchain*) nothrow;
alias onSwapchainResize = void function(EventSource, Swapchain*) nothrow;

struct VulkanDisplayProperties {
    DisplayProperties display_properties;

    /**
    Called after a swapchain is created. If this is called during a display
    resize, it will be called before `on_resize`.
    */
    OnSwapchainCreate on_swapchain_create;

    /**
    Called after a swapchain is destroyed. This will be called before
    `on_resize` and `on_destroy`
    */
    OnSwapchainDestroy on_swapchain_destroy;

    /**
    Called after a swapchain has been resized. This will be called before
    `on_resize`.
    */
    onSwapchainResize on_swapchain_resize;
}

final class VulkanDisplayManager : DisplayManager {

    /// Vulkan instance extensions required by the renderer.
    static immutable required_instance_extensions = [
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_WIN32_SURFACE_EXTENSION_NAME
    ];

    /// Vulkan device extensions required by the renderer.
    static immutable required_device_extensions = [
        VK_KHR_SWAPCHAIN_EXTENSION_NAME
    ];

public:
    this(VulkanContext vulkan) {
        super(vulkan.memory);

        _instance = vulkan;
        _swapchains = ObjectPool!SwapchainData(vulkan.memory, max_open_displays);
    }

    ~this() {
        object.destroy(_swapchains);
        object.destroy(_device);
        object.destroy(_instance);
    }

    void acquire_next_image(DisplayId id, out SwapchainImage image) {
        flare.vulkan.acquire_next_image(_device, &(cast(SwapchainData*) super.get_user_data(id)).swapchain, image);
    }

    VulkanDevice device() {
        return _device;
    }

    override void* get_user_data(DisplayId id) nothrow {
        return (cast(SwapchainData*) super.get_user_data(id)).overridden_user_data;
    }

    override DisplayId create(ref DisplayProperties properties) nothrow {
        auto vk_props = VulkanDisplayProperties(properties);
        return create(vk_props);
    }

    DisplayId create(ref VulkanDisplayProperties properties) nothrow {
        auto swapchain = _swapchains.allocate(
            this,
            properties.display_properties.user_data,
            properties.display_properties.callbacks.on_create,
            properties.display_properties.callbacks.on_destroy,
            properties.display_properties.callbacks.on_resize,
            properties.on_swapchain_create,
            properties.on_swapchain_destroy,
            properties.on_swapchain_resize
        );

        properties.display_properties.user_data = swapchain;

        properties.display_properties.callbacks.on_create = (src) nothrow {
            auto data = cast(SwapchainData*) src.user_data;
            auto self = data.manager;

            data.manager = self;

            data.surface = create_surface(self._instance, data.manager.get_os_handle(src.display_id));

            if (!self._device)
                self._init_device(data.surface);

            SwapchainProperties properties;
            get_swapchain_properties(self._device, data.surface, properties);

            if (properties.image_size != VkExtent2D())
                create_swapchain(self._device, data.surface, properties, data.swapchain);

            if (data.overridden_on_create)
                data.overridden_on_create(_user_source(src, data));
        };

        properties.display_properties.callbacks.on_destroy = (src) nothrow {
            auto data = cast(SwapchainData*) src.user_data;
            auto self = data.manager;

            destroy_swapchain(self._device, data.swapchain);
            vkDestroySurfaceKHR(self._instance.instance, data.surface, null);    

            if (data.overridden_on_destroy)
                data.overridden_on_destroy(_user_source(src, data));
            
            self._swapchains.deallocate(data);
        };

        properties.display_properties.callbacks.on_resize = (src, width, height) nothrow {
            auto data = cast(SwapchainData*) src.user_data;
            auto self = data.manager;

            SwapchainProperties properties;
            get_swapchain_properties(self._device, data.surface, properties);

            const is_zero_size = properties.image_size == VkExtent2D();
            const was_zero_size = data.swapchain.image_size == VkExtent2D();

            if (data.overridden_on_resize)
                data.overridden_on_resize(_user_source(src, data), width, height);

            if (was_zero_size && !is_zero_size) {
                create_swapchain(self._device, data.surface, properties, data.swapchain);

                if (data.on_swapchain_create)
                    data.on_swapchain_create(_user_source(src, data), &data.swapchain);
            }
            else if (!was_zero_size && !is_zero_size) {
                resize_swapchain(self._device, data.surface, properties, data.swapchain);

                if (data.on_swapchain_resize)
                    data.on_swapchain_resize(_user_source(src, data), &data.swapchain);
            }
            else if (!was_zero_size && is_zero_size) {
                destroy_swapchain(self._device, data.swapchain);

                if (data.on_swapchain_destroy)
                    data.on_swapchain_destroy(_user_source(src, data), &data.swapchain);
            }
        };

        return super.create(properties.display_properties);
    }

private:
    struct SwapchainData {
        VulkanDisplayManager manager;

        // Overrides needed for swapchain management
        void* overridden_user_data;
        OnCreate overridden_on_create;
        OnDestroy overridden_on_destroy;
        OnResize overridden_on_resize;

        // Callbacks for swapchain events
        OnSwapchainCreate on_swapchain_create;
        OnSwapchainDestroy on_swapchain_destroy;
        onSwapchainResize on_swapchain_resize;

        VkSurfaceKHR surface;
        Swapchain swapchain;
    }

    void _init_device(VkSurfaceKHR surface) nothrow {
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

    static EventSource _user_source(ref EventSource src, SwapchainData* data) nothrow {
        return EventSource(src.manager, src.display_id, data.overridden_user_data);
    }

    VulkanContext _instance;
    VulkanDevice _device;
    ObjectPool!SwapchainData _swapchains;
}
