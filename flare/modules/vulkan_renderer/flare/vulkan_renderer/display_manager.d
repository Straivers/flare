module flare.vulkan_renderer.display_manager;

import flare.core.logger : Logger;
import flare.core.memory;
import flare.vulkan;

public import flare.display.input;
public import flare.display.manager;

struct VulkanEventSource {
    VulkanDisplayManager manager;
    DisplayId display_id;
    void* user_data;
}

alias OnSwapchainCreate = void function(VulkanEventSource, Swapchain*) nothrow;
alias OnSwapchainDestroy = void function(VulkanEventSource, Swapchain*) nothrow;
alias onSwapchainResize = void function(VulkanEventSource, Swapchain*) nothrow;

/*
Create() -> OsCreate() -> VulkanInit() -> on_create() -> SwapchainCreate() -> on_swapchain_create()
Destroy() -> on_swapchain_destroy() -> SwapchainDestroy() -> on_destroy() -> OsDestroy()
*/
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
    this(Logger* sys_logger, VulkanContext vulkan) {
        super(sys_logger, vulkan.memory);

        _instance = vulkan;
        _swapchains = ObjectPool!SwapchainData(vulkan.memory, max_open_displays);
    }

    ~this() {
        object.destroy(_swapchains);
        object.destroy(_device);
        object.destroy(_instance);
    }

    VulkanDevice device() nothrow {
        return _device;
    }

    void get_next_image(DisplayId id, out SwapchainImage image, VkSemaphore acquire_semaphore) {
        flare.vulkan.acquire_next_image(_device, &(cast(SwapchainData*) super.get_user_data(id)).swapchain, acquire_semaphore, image);
    }

    void swap_buffers(DisplayId id, VkSemaphore present_semaphore) {
        auto data = cast(SwapchainData*) super.get_user_data(id);
        if (!flare.vulkan.swap_buffers(_device, &data.swapchain, present_semaphore)) {
            auto src = EventSource(this, id, data.overridden_user_data);
            _resize_impl(src, data);
        }
    }

    override void* get_user_data(DisplayId id) nothrow {
        return (cast(SwapchainData*) super.get_user_data(id)).overridden_user_data;
    }

    override DisplayId create(ref DisplayProperties properties) nothrow {
        auto vk_props = VulkanDisplayProperties(properties);
        return create(vk_props);
    }

    DisplayId create(ref VulkanDisplayProperties properties) nothrow {
        auto swapchain = _swapchains.make(
                this,
                properties.display_properties.user_data,
                properties.display_properties.callbacks.on_create,
                properties.display_properties.callbacks.on_destroy,
                properties.display_properties.callbacks.on_resize,
                properties.on_swapchain_create,
                properties.on_swapchain_destroy,
                properties.on_swapchain_resize);

        properties.display_properties.user_data = swapchain;

        properties.display_properties.callbacks.on_create = (src) nothrow {
            auto data = cast(SwapchainData*) src.user_data;
            auto self = data.manager;

            data.manager = self;
            data.surface = create_surface(self._instance, data.manager.get_os_handle(src.display_id));

            if (!self._device)
                self._init_device(data.surface);

            if (data.overridden_on_create)
                data.overridden_on_create(_user_source(src, data));

            SwapchainProperties properties;
            get_swapchain_properties(self._device, data.surface, properties);

            if (properties.image_size != VkExtent2D()) {
                create_swapchain(self._device, data.surface, properties, data.swapchain);

                if (data.on_swapchain_create)
                    data.on_swapchain_create(_vk_source(src.display_id, data), &data.swapchain);
            }
            else
                self._sys_logger.trace("Attempted to create 0-size swapchain. Deferring operation.");
        };

        properties.display_properties.callbacks.on_destroy = (src) nothrow {
            auto data = cast(SwapchainData*) src.user_data;
            auto self = data.manager;

            if (data.on_swapchain_destroy)
                data.on_swapchain_destroy(_vk_source(src.display_id, data), &data.swapchain);

            // dfmt off
            self._sys_logger.trace(
                "Destroying swapchain %s and surface %s for window %s.",
                data.swapchain.handle, data.surface, src.display_id.int_value);
            // dfmt on

            destroy_swapchain(self._device, data.swapchain);
            vkDestroySurfaceKHR(self._instance.instance, data.surface, null);

            if (data.overridden_on_destroy)
                data.overridden_on_destroy(_user_source(src, data));

            self._swapchains.dispose(data);
        };

        properties.display_properties.callbacks.on_resize = (src, width, height) nothrow {
            auto data = cast(SwapchainData*) src.user_data;
            auto self = data.manager;

            self._resize_impl(src, data);
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

    void _resize_impl(ref EventSource src, SwapchainData* data) nothrow {
        SwapchainProperties properties;
        get_swapchain_properties(_device, data.surface, properties);

        const is_zero_size = properties.image_size == VkExtent2D();
        const was_zero_size = data.swapchain.image_size == VkExtent2D();

        if (data.overridden_on_resize)
            data.overridden_on_resize(_user_source(src, data), cast(ushort) properties.image_size.width, cast(ushort) properties.image_size.height);

        if (was_zero_size && !is_zero_size) {
            // dfmt off
            _sys_logger.trace(
                "Resizing swapchain for window %8#0x from (0, 0) to (%s, %s); creating swapchain.",
                src.display_id.int_value,
                properties.image_size.width, properties.image_size.height);
            // dfmt on

            create_swapchain(_device, data.surface, properties, data.swapchain);

            if (data.on_swapchain_create)
                data.on_swapchain_create(_vk_source(src.display_id, data), &data.swapchain);
        }
        else if (!was_zero_size && !is_zero_size) {
            // dfmt off
            _sys_logger.trace(
                "Resizing swapchain for window %8#0x from (%s, %s) to (%s, %s); recreating swapchain.",
                src.display_id.int_value,
                data.swapchain.image_size.width, data.swapchain.image_size.height,
                properties.image_size.width, properties.image_size.height);
            // dfmt on

            resize_swapchain(_device, data.surface, properties, data.swapchain);

            if (data.on_swapchain_resize)
                data.on_swapchain_resize(_vk_source(src.display_id, data), &data.swapchain);
        }
        else if (!was_zero_size && is_zero_size) {
            // dfmt off
            _sys_logger.trace(
                "Resizing swapchain for window %8#0x from (%s, %s) to (0, 0); destroying swapchain.",
                src.display_id.int_value,
                data.swapchain.image_size.width, data.swapchain.image_size.height);
            // dfmt on

            destroy_swapchain(_device, data.swapchain);

            if (data.on_swapchain_destroy)
                data.on_swapchain_destroy(_vk_source(src.display_id, data), &data.swapchain);
        }
    }

    static EventSource _user_source(ref EventSource src, SwapchainData* data) nothrow {
        return EventSource(src.manager, src.display_id, data.overridden_user_data);
    }

    static VulkanEventSource _vk_source(DisplayId id, SwapchainData* data) nothrow {
        return VulkanEventSource(data.manager, id, data.overridden_user_data);
    }

    VulkanContext _instance;
    VulkanDevice _device;
    ObjectPool!SwapchainData _swapchains;
}
