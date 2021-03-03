module flare.vulkan.commands;

import flare.vulkan.device;
import flare.vulkan.h;
import flare.vulkan.memory;

final class CommandPool {
nothrow:
    ~this() {
        _device.dispatch_table.DestroyCommandPool(handle);
    }

    VkCommandPool handle() {
        return _handle;
    }

    VkCommandBuffer allocate(VkCommandBufferLevel level = VK_COMMAND_BUFFER_LEVEL_PRIMARY) {
        VkCommandBufferAllocateInfo ai = {
            commandPool: handle,
            level: level,
            commandBufferCount: 1
        };

        VkCommandBuffer[1] buffer;
        _device.dispatch_table.AllocateCommandBuffers(ai, buffer);
        return buffer[0];
    }

    void allocate(VkCommandBuffer[] buffers, VkCommandBufferLevel level = VK_COMMAND_BUFFER_LEVEL_PRIMARY) {
        VkCommandBufferAllocateInfo ai = {
            commandPool: handle,
            level: level,
            commandBufferCount: cast(uint) buffers.length
        };

        _device.dispatch_table.AllocateCommandBuffers(ai, buffers);
    }

    void free(VkCommandBuffer[] buffers...) {
        _device.dispatch_table.FreeCommandBuffers(handle, buffers);
    }

    void submit(VkQueue queue, VkFence fence_on_complete, VkSubmitInfo[] submissions...) {
        const err = _device.dispatch_table.QueueSubmit(queue, fence_on_complete, submissions);
        if (err != VK_SUCCESS) {
            _device.context.logger.fatal("Failed call to vkQueueSubmit: %s", err);
            assert(0, "Failed call to vkQueueSubmit");
        }
    }

private:
    VulkanDevice _device;
    VkCommandPool _handle;

    this(VulkanDevice host, VkCommandPool handle) {
        _device = host;
        _handle = handle;
    }
}

CommandPool create_graphics_command_pool(VulkanDevice device) nothrow {
    VkCommandPool handle;
    {
        VkCommandPoolCreateInfo ci = {
            queueFamilyIndex: device.graphics.family,
            flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
        };

        device.dispatch_table.CreateCommandPool(ci, handle);
    }

    return new CommandPool(device, handle);
}

CommandPool create_transfer_command_pool(VulkanDevice device) nothrow {
    VkCommandPool handle;
    {
        VkCommandPoolCreateInfo ci = {
            queueFamilyIndex: device.transfer.family,
            flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT | VK_COMMAND_POOL_CREATE_TRANSIENT_BIT
        };

        device.dispatch_table.CreateCommandPool(ci, handle);
    }

    return new CommandPool(device, handle);
}
