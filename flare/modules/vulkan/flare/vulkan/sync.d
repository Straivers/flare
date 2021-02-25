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

VkFence create_fence(VulkanDevice device, bool start_signalled = false) {
    VkFenceCreateInfo ci;

    if (start_signalled)
        ci.flags = VK_FENCE_CREATE_SIGNALED_BIT;

    VkFence fence;
    device.dispatch_table.CreateFence(ci, fence);
    return fence;
}

bool is_signalled(VulkanDevice device, VkFence fence) {
    return device.dispatch_table.GetFenceStatus(fence) == VK_SUCCESS;
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

alias FencePool = SyncPool!(VkFence, create_fence, destroy_fence);
alias SemaphorePool = SyncPool!(VkSemaphore, create_semaphore, destroy_semaphore);

struct SyncPool(SyncObject, alias create_fn, alias destroy_fn)
if (is(SyncObject == VkFence) || is(SyncObject == VkSemaphore)) {
    import flare.core.array : Array;
    import flare.core.memory : Allocator;

    this(VulkanDevice device, Allocator allocator, uint min_objects = 64) {
        _device = device;
        _available_objects = Array!SyncObject(allocator, min_objects);

        foreach (i; 0 .. _available_objects.length)
            _available_objects[i] = create_fn(_device);
        
        debug _num_live_objects = min_objects;
    }

    ~this() {
        debug assert(_available_objects.length == _num_live_objects);

        foreach (i; 0 .. _available_objects.length)
            destroy_fn(_device, _available_objects[i]);

        destroy(_available_objects);
    }

    size_t pool_size() {
        return _available_objects.length;
    }

    SyncObject acquire() {
        if (_available_objects.length)
            return _available_objects.pop_back();
        
        debug _num_live_objects++;
        return create_fn(_device);
    }

    void release(SyncObject sync_object) {
        static if (is(SyncObject == VkFence))
            if (is_signalled(_device, sync_object))
                reset_fence(_device, sync_object);

        _available_objects.push_back(sync_object);
    }

private:
    VulkanDevice _device;
    Array!SyncObject _available_objects;

    debug size_t _num_live_objects;
}
