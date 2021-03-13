module flare.renderer.vulkan.api.sync;

import flare.util.array : Array;
import flare.memory : Allocator;
import flare.renderer.vulkan.api.device;
import flare.renderer.vulkan.api.dispatch;
import flare.renderer.vulkan.api.h;

nothrow:

bool wait(bool all = true)(VulkanDevice device, VkFence[] fences...) {
    return device.dispatch_table.WaitForFences(fences, all ? VK_TRUE : VK_FALSE, ulong.max) == VK_SUCCESS;
}

void reset(VulkanDevice device, VkFence[] fences...) {
    device.dispatch_table.ResetFences(fences);
}

void wait_and_reset(bool all = true)(VulkanDevice device, VkFence[] fences...) {
    if (wait!all(device, fences))
        reset(device, fences);
}

struct FencePool {
nothrow:
    this(DispatchTable* vk, Allocator allocator) {
        _vk = vk;
        _fences = Array!VkFence(allocator);
    }

    @disable this(this);

    ~this() {
        foreach (fence; _fences[])
            _vk.DestroyFence(fence);

        destroy(_fences);
    }

    VkFence acquire(bool start_signalled = false) {
        if (_fences.length && !start_signalled)
            return _fences.pop_back();
        
        VkFenceCreateInfo ci;

        if (start_signalled)
            ci.flags = VK_FENCE_CREATE_SIGNALED_BIT;
        
        VkFence fence;
        _vk.CreateFence(ci, fence);
        return fence;
    }

    void release(VkFence fence) {
        if (_vk.GetFenceStatus(fence) != VK_SUCCESS)
            _vk.ResetFences(fence);
        _fences.push_back(fence);
    }

private:
    DispatchTable* _vk;
    Array!VkFence _fences;
}

struct SemaphorePool {
nothrow:
    this(DispatchTable* vk, Allocator allocator) {
        _vk = vk;
        _semaphores = Array!VkSemaphore(allocator);
    }

    @disable this(this);

    ~this() {
        foreach (fence; _semaphores[])
            _vk.DestroySemaphore(fence);
        destroy(_semaphores);
    }

    VkSemaphore acquire() {
        if (_semaphores.length)
            return _semaphores.pop_back();
        
        VkSemaphoreCreateInfo ci;
        VkSemaphore semaphore;
        _vk.CreateSemaphore(ci, semaphore);
        return semaphore;
    }

    void release(VkSemaphore semaphore) {
        _semaphores.push_back(semaphore);
    }

private:
    DispatchTable* _vk;
    Array!VkSemaphore _semaphores;
}
