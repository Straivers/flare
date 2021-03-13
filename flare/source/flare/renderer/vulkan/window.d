module flare.renderer.vulkan.window;

import flare.os.window;
import flare.os.window_manager;
import flare.renderer.vulkan.api;
import flare.renderer.vulkan.vulkan_renderer;
import flare.util.checked_pointer : CheckedVoidPtr;
import flare.util.functions : if_not_null;
import flare.util.object_pool : ObjectPool;

public import flare.os.window: WindowId, CursorIcon, WindowMode, WindowProperties, WindowState;

struct VulkanFrame {
    SwapchainImage image;

    VkFence fence;
    VkCommandBuffer command_buffer;

    VkSemaphore acquire;
    VkSemaphore present;
}

struct VulkanWindow {
    WindowId handle;
    VulkanRenderer renderer;
    VulkanWindowOverrides overrides;

    Swapchain swapchain;
    VkSurfaceKHR surface;

    VulkanFrameResources frames;
    alias frames this;
}

struct VulkanWindowOverrides {
    CheckedVoidPtr user_data;
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

WindowId create_vulkan_window(ref WindowManager manager, VulkanRenderer renderer, WindowProperties properties) {
    struct Overrides {
        VulkanWindowOverrides overrides;
        CheckedVoidPtr aux;
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
        auto overrides = user_data.get!Overrides();
        auto renderer = aux.get!VulkanRenderer();

        auto window = renderer.on_window_create(id, overrides.overrides, mgr.get_os_handle(id));
        mgr.set_user_data(id, CheckedVoidPtr(window));

        window.overrides.on_create.if_not_null(mgr, id, window.overrides.user_data, overrides.aux);
    };

    properties.callbacks.on_resize = (mgr, id, user_data, width, height) {
        auto window = user_data.get!VulkanWindow();
        window.renderer.on_window_resize(window, mgr.get_state(id).vsync);
        window.overrides.on_resize.if_not_null(mgr, id, window.overrides.user_data, width, height);
    };

    properties.callbacks.on_destroy = (mgr, id, user_data) nothrow {
        auto window = user_data.get!VulkanWindow();
        window.renderer.on_window_destroy(window);
        window.overrides.on_destroy.if_not_null(mgr, id, window.overrides.user_data);
    };

    properties.user_data = &overrides;
    properties.aux_data = renderer;

    return manager.create(properties);
}

void get_next_frame(ref WindowManager manager, WindowId id, out VulkanFrame frame) {
    auto window = manager.get_user_data(id).get!VulkanWindow();

    with (window) {
        frame.fence = fences[virtual_frame_id];
        frame.command_buffer = command_buffers[(double_buffer_id * num_virtual_frames) + virtual_frame_id];
        frame.acquire = acquire_semaphores[virtual_frame_id];
        frame.present = present_semaphores[virtual_frame_id];

        if (!acquire_next_image(renderer.device, &swapchain, frame.acquire, frame.image))
            window.renderer.on_window_resize(window, manager.get_state(id).vsync);
    }
}

void swap_buffers(ref WindowManager manager, WindowId id) {
    auto window = manager.get_user_data(id).get!VulkanWindow();

    with (window) {
        if (!flare.renderer.vulkan.api.swap_buffers(renderer.device, &swapchain, present_semaphores[virtual_frame_id]))
            window.renderer.on_window_resize(window, manager.get_state(id).vsync);

        double_buffer_id ^= 1;
        virtual_frame_id = (virtual_frame_id + 1) % num_virtual_frames;
    }
}
