module flare.vulkan_renderer.window;

import flare.core.memory: ObjectPool;
import flare.core.functions: if_not_null;
import flare.vulkan;
import flare.display;
import flare.vulkan_renderer.vulkan_renderer;

public import flare.display: DisplayId, CursorIcon, DisplayMode, DisplayProperties, DisplayState;

struct VulkanFrame {
    SwapchainImage image;

    VkFence fence;
    VkCommandBuffer command_buffer;

    VkSemaphore acquire;
    VkSemaphore present;
}

struct VulkanWindow {
    enum num_virtual_frames = 3;

    DisplayId handle;
    VulkanWindowOverrides overrides;


    Swapchain swapchain;
    VkSurfaceKHR surface;


    size_t virtual_frame_id;
    size_t double_buffer_id;

    VkFence[num_virtual_frames] fences;
    VkCommandBuffer[num_virtual_frames * 2] command_buffers;

    VkSemaphore[num_virtual_frames] acquire_semaphores;
    VkSemaphore[num_virtual_frames] present_semaphores;

    VulkanRenderer renderer;
}

struct VulkanWindowOverrides {
    void* user_data;
    OnCreate on_create;
    OnDestroy on_destroy;
}

DisplayId create_vulkan_window(DisplayManager manager, VulkanRenderer renderer, DisplayProperties properties) {
    struct Overrides {
        VulkanWindowOverrides overrides;
        void* aux;
    }

    auto overrides = Overrides(
        VulkanWindowOverrides(properties.user_data, properties.callbacks.on_create, properties.callbacks.on_destroy),
        properties.aux_data);

    properties.callbacks.on_create = (mgr, id, user_data, aux) nothrow {
        auto overrides = cast(Overrides*) user_data;
        auto renderer = cast(VulkanRenderer) aux;

        auto window = renderer.on_window_create(id, overrides.overrides, mgr.get_os_handle(id));
        mgr.set_user_data(id, window);

        window.overrides.on_create.if_not_null(mgr, id, window.overrides.user_data, overrides.aux);
    };

    properties.callbacks.on_destroy = (mgr, id, user_data) nothrow {
        auto window = cast(VulkanWindow*) user_data;
        window.renderer.on_window_destroy(window);
        window.overrides.on_destroy.if_not_null(mgr, id, window.overrides.user_data);
    };

    properties.user_data = &overrides;
    properties.aux_data = cast(void*) renderer;

    return manager.create(properties);
}

void get_next_frame(DisplayManager manager, DisplayId id, out VulkanFrame frame) {
    auto window = cast(VulkanWindow*) manager.get_user_data(id);

    with (window) {
        frame.fence = fences[virtual_frame_id];
        frame.command_buffer = command_buffers[(double_buffer_id * num_virtual_frames) + virtual_frame_id];
        frame.acquire = acquire_semaphores[virtual_frame_id];
        frame.present = present_semaphores[virtual_frame_id];

        if (!swapchain.handle || !acquire_next_image(renderer.device, &swapchain, frame.acquire, frame.image)) {
            SwapchainProperties properties;
            get_swapchain_properties(renderer.device, surface, properties);
            final switch (resize_swapchain2(renderer.device, surface, properties, swapchain)) with (SwapchainResizeOp) {
            case Create: return renderer.on_swapchain_create(window);
            case Destroy: return renderer.on_swapchain_destroy(window);
            case Replace: return renderer.on_swapchain_create(window);
            }
        }
    }
}

void swap_buffers(DisplayManager manager, DisplayId id) {
    auto window = cast(VulkanWindow*) manager.get_user_data(id);

    with (window) {
        if (!flare.vulkan.swap_buffers(renderer.device, &swapchain, present_semaphores[virtual_frame_id])) {
            SwapchainProperties properties;
            get_swapchain_properties(renderer.device, surface, properties);
            final switch (resize_swapchain2(renderer.device, surface, properties, swapchain)) with (SwapchainResizeOp) {
            case Create: return renderer.on_swapchain_create(window);
            case Destroy: return renderer.on_swapchain_destroy(window);
            case Replace: return renderer.on_swapchain_create(window);
            }
        }

        double_buffer_id |= 1;
        virtual_frame_id = (virtual_frame_id + 1) % num_virtual_frames;
    }
}
