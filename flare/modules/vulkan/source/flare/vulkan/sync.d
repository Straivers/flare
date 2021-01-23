module flare.vulkan.sync;

import flare.vulkan.device;
import flare.vulkan.h;

nothrow:

VkSemaphore create_semaphore(VulkanDevice device) {
    VkSemaphoreCreateInfo ci;
    VkSemaphore semaphore;

    device.dispatch_table.CreateSemaphore(ci, semaphore);
    return semaphore;
}

void destroy_semaphore(VulkanDevice device, VkSemaphore semaphore) {
    device.dispatch_table.DestroySemaphore(semaphore);
}

VkFence create_fence(VulkanDevice device, bool start_signalled) {
    VkFenceCreateInfo ci;

    if (start_signalled)
        ci.flags = VK_FENCE_CREATE_SIGNALED_BIT;

    VkFence fence;
    device.dispatch_table.CreateFence(ci, fence);
    return fence;
}

void destroy_fence(VulkanDevice device, VkFence fence) {
    device.dispatch_table.DestroyFence(fence);
}

void reset_fence(VulkanDevice device, VkFence fence) {
    reset_fences(device, fence);
}

void reset_fences(VulkanDevice device, VkFence[] fences...) {
    device.dispatch_table.ResetFences(fences);
}

bool wait_fence(VulkanDevice device, VkFence fence, ulong timeout = ulong.max) {
    return wait_fences(device, true, timeout, fence);
}

bool wait_fences(VulkanDevice device, bool wait_all, ulong timeout, VkFence[] fences...) {
    return device.dispatch_table.WaitForFences(fences, wait_all, timeout) == VK_SUCCESS;
}

bool wait_and_reset_fence(VulkanDevice device, VkFence fence, ulong timeout = ulong.max) {
    const success = wait_fence(device, fence, timeout);

    if (success)
        reset_fence(device, fence);

    return success;
}
