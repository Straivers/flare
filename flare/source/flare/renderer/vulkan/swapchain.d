module flare.renderer.vulkan.swapchain;

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

struct VulkanSwapchain {
    VulkanRenderer renderer;
    bool vsync;

    Swapchain swapchain;
    VkSurfaceKHR surface;

    VulkanFrameResources frames;
    alias frames this;
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

void get_next_frame(VulkanSwapchain* window, out VulkanFrame frame) {
    with (window) {
        frame.fence = fences[virtual_frame_id];
        frame.command_buffer = command_buffers[(double_buffer_id * num_virtual_frames) + virtual_frame_id];
        frame.acquire = acquire_semaphores[virtual_frame_id];
        frame.present = present_semaphores[virtual_frame_id];

        if (!window.swapchain.handle)
            window.renderer.resize_swapchain(window);

        if (!acquire_next_image(renderer.device, &swapchain, frame.acquire, frame.image))
            window.renderer.resize_swapchain(window);
    }
}
