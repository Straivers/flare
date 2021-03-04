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
struct VulkanCallbacks {
    Callbacks callbacks;
    alias callbacks this;

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
            _resize_impl(id, data);
        }
    }

    override void* get_user_data(DisplayId id) nothrow {
        return (cast(SwapchainData*) super.get_user_data(id)).overridden_user_data;
    }

    override DisplayId create(ref DisplayProperties properties, Callbacks callbacks, void* user_data) nothrow {
        return create(properties, VulkanCallbacks(callbacks), user_data);
    }

    DisplayId create(ref DisplayProperties properties, VulkanCallbacks callbacks, void* user_data) nothrow {
        auto swapchain = _swapchains.make(
                this,
                user_data,
                callbacks.on_swapchain_create,
                callbacks.on_swapchain_destroy,
                callbacks.on_swapchain_resize);

        return super.create(properties, callbacks, swapchain);
    }

protected:
    override void _on_create(DisplayId id) {
        auto data = cast(SwapchainData*) super.get_user_data(id);

        data.surface = create_surface(_instance, get_os_handle(id));

        if (!_device)
            _init_device(data.surface);

        super._on_create(id);

        SwapchainProperties properties;
        get_swapchain_properties(_device, data.surface, properties);

        if (properties.image_size != VkExtent2D()) {
            create_swapchain(_device, data.surface, properties, data.swapchain);
            data.try_call!"on_swapchain_create"(_vk_source(id, data), &data.swapchain);
        }
        // else
        //     _sys_logger.trace("Attempted to create 0-size swapchain. Deferring operation.");
    }

    override void _on_destroy(DisplayId id) {
        auto data = cast(SwapchainData*) super.get_user_data(id);

        data.try_call!"on_swapchain_destroy"(_vk_source(id, data), &data.swapchain);
        
        destroy_swapchain(_device, data.swapchain);
        vkDestroySurfaceKHR(_instance.instance, data.surface, null);
        _swapchains.dispose(data);

        super._on_destroy(id);
    }

    override void _on_resize(DisplayId id, ushort width, ushort height) {
        _resize_impl(id, cast(SwapchainData*) super.get_user_data(id));
        super._on_resize(id, width, height);
    }

private:
    struct SwapchainData {
        VulkanDisplayManager manager;

        // Overrides needed for swapchain management
        void* overridden_user_data;

        // Callbacks for swapchain events
        OnSwapchainCreate on_swapchain_create;
        OnSwapchainDestroy on_swapchain_destroy;
        onSwapchainResize on_swapchain_resize;

        VkSurfaceKHR surface;
        Swapchain swapchain;

        void try_call(string name, Args...)(Args args) {
            mixin("if(" ~ name ~ ") " ~ name ~ "(args);");
        }
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

    void _resize_impl(DisplayId id, SwapchainData* data) nothrow {
        SwapchainProperties properties;
        get_swapchain_properties(_device, data.surface, properties);

        const is_zero_size = properties.image_size == VkExtent2D();
        const was_zero_size = data.swapchain.image_size == VkExtent2D();

        if (was_zero_size && !is_zero_size) {
            // dfmt off
            // _sys_logger.trace(
            //     "Resizing swapchain for window %8#0x from (0, 0) to (%s, %s); creating swapchain.",
            //     id.int_value,
            //     properties.image_size.width, properties.image_size.height);
            // dfmt on

            create_swapchain(_device, data.surface, properties, data.swapchain);
            data.try_call!"on_swapchain_create"(_vk_source(id, data), &data.swapchain);
        }
        else if (!was_zero_size && !is_zero_size) {
            // dfmt off
            // _sys_logger.trace(
            //     "Resizing swapchain for window %8#0x from (%s, %s) to (%s, %s); recreating swapchain.",
            //     id.int_value,
            //     data.swapchain.image_size.width, data.swapchain.image_size.height,
            //     properties.image_size.width, properties.image_size.height);
            // dfmt on

            resize_swapchain(_device, data.surface, properties, data.swapchain);
            data.try_call!"on_swapchain_resize"(_vk_source(id, data), &data.swapchain);
        }
        else if (!was_zero_size && is_zero_size) {
            // dfmt off
            // _sys_logger.trace(
            //     "Resizing swapchain for window %8#0x from (%s, %s) to (0, 0); destroying swapchain.",
            //     id.int_value,
            //     data.swapchain.image_size.width, data.swapchain.image_size.height);
            // dfmt on

            destroy_swapchain(_device, data.swapchain);
            data.try_call!"on_swapchain_destroy"(_vk_source(id, data), &data.swapchain);
        }
    }

    VulkanEventSource _vk_source(DisplayId id, SwapchainData* data) nothrow {
        return VulkanEventSource(this, id, data.overridden_user_data);
    }

    VulkanContext _instance;
    VulkanDevice _device;
    ObjectPool!SwapchainData _swapchains;
}
