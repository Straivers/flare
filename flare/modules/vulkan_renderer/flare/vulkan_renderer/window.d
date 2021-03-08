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
    DisplayId handle;
    VulkanRenderer renderer;
    VulkanWindowOverrides overrides;

    Swapchain swapchain;
    VkSurfaceKHR surface;

    VulkanFrameResources frames;
    alias frames this;
}

struct VulkanWindowOverrides {
    void* user_data;
    OnCreate on_create;
    OnResize on_resize;
    OnDestroy on_destroy;
}

struct VulkanFrameResources {
    enum num_virtual_frames = 3;

    size_t virtual_frame_id;
    size_t double_buffer_id;

    VkFence[num_virtual_frames] fences;
    VkCommandBuffer[num_virtual_frames * 2] command_buffers;

    VkSemaphore[num_virtual_frames] acquire_semaphores;
    VkSemaphore[num_virtual_frames] present_semaphores;

    void initialize(VulkanDevice device, CommandPool* command_pool) nothrow {
        foreach (i; 0 .. num_virtual_frames) {
            fences[i] = device.fence_pool.acquire(true);
            acquire_semaphores[i] = device.semaphore_pool.acquire();
            present_semaphores[i] = device.semaphore_pool.acquire();
        }

        command_pool.allocate(command_buffers);
    }

    void destroy(VulkanDevice device, CommandPool* command_pool) nothrow {
        foreach (i; 0 .. num_virtual_frames) {
            device.fence_pool.release(fences[i]);
            device.semaphore_pool.release(acquire_semaphores[i]);
            device.semaphore_pool.release(present_semaphores[i]);
        }

        command_pool.free(command_buffers);
    }
}

DisplayId create_vulkan_window(ref DisplayManager manager, VulkanRenderer renderer, DisplayProperties properties) {
    struct Overrides {
        VulkanWindowOverrides overrides;
        void* aux;
    }

    Overrides overrides = {
        overrides: {
            user_data: properties.user_data,
            on_create: properties.callbacks.on_create,
            on_resize: properties.callbacks.on_resize,
            on_destroy: properties.callbacks.on_destroy
        },
        aux: properties.aux_data
    };

    properties.callbacks.on_create = (mgr, id, user_data, aux) nothrow {
        auto overrides = cast(Overrides*) user_data;
        auto renderer = cast(VulkanRenderer) aux;

        auto window = renderer.on_window_create(id, overrides.overrides, mgr.get_os_handle(id));
        mgr.set_user_data(id, window);

        window.overrides.on_create.if_not_null(mgr, id, window.overrides.user_data, overrides.aux);
    };

    properties.callbacks.on_resize = (mgr, id, user_data, width, height) {
        auto window = cast(VulkanWindow*) user_data;
        window.renderer.on_window_resize(window);
        window.overrides.on_resize.if_not_null(mgr, id, window.overrides.user_data, width, height);
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

void get_next_frame(ref DisplayManager manager, DisplayId id, out VulkanFrame frame) {
    auto window = cast(VulkanWindow*) manager.get_user_data(id);

    with (window) {
        frame.fence = fences[virtual_frame_id];
        frame.command_buffer = command_buffers[(double_buffer_id * num_virtual_frames) + virtual_frame_id];
        frame.acquire = acquire_semaphores[virtual_frame_id];
        frame.present = present_semaphores[virtual_frame_id];

        if (!acquire_next_image(renderer.device, &swapchain, frame.acquire, frame.image))
            window.renderer.on_window_resize(window);
    }
}

void swap_buffers(ref DisplayManager manager, DisplayId id) {
    auto window = cast(VulkanWindow*) manager.get_user_data(id);

    with (window) {
        if (!flare.vulkan.swap_buffers(renderer.device, &swapchain, present_semaphores[virtual_frame_id]))
            window.renderer.on_window_resize(window);

        double_buffer_id ^= 1;
        virtual_frame_id = (virtual_frame_id + 1) % num_virtual_frames;
    }
}
