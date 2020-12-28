module flare.vulkan.commands;

import flare.vulkan.device;
import flare.vulkan.h;

final class CommandPool {
nothrow:
    ~this() {
        _device.d_destroy_command_pool(handle);
    }

    VkCommandPool handle() {
        return _handle;
    }

    void allocate(VkCommandBuffer[] buffers, VkCommandBufferLevel level = VK_COMMAND_BUFFER_LEVEL_PRIMARY) {
        VkCommandBufferAllocateInfo ai = {
            commandPool: handle,
            level: level,
            commandBufferCount: cast(uint) buffers.length
        };

        auto err = vkAllocateCommandBuffers(_device.handle, &ai, buffers.ptr);
        if (err != VK_SUCCESS) {
            _device.context.logger.fatal("Unable to allocate %s command buffers: %s", buffers.length, err);
            assert(0, "Unable to allocate command buffers.");
        }
    }

    void free(VkCommandBuffer[] buffers...) {
        vkFreeCommandBuffers(_device.handle, handle, cast(uint) buffers.length, buffers.ptr);
    }

    void submit(VkQueue queue, VkFence fence_on_complete, VkSubmitInfo[] submissions...) {
        const err = vkQueueSubmit(queue, cast(uint) submissions.length, submissions.ptr, fence_on_complete);
        if (err != VK_SUCCESS) {
            _device.context.logger.fatal("Failed call to vkQueueSubmit: %s", err);
            assert(0, "Failed call to vkQueueSubmit");
        }
    }

    void cmd_begin_primary_buffer(VkCommandBuffer buffer) {
        VkCommandBufferBeginInfo info = {
            flags: 0,
            pInheritanceInfo: null
        };
        vkBeginCommandBuffer(buffer, &info);
    }

    VkResult cmd_end_buffer(VkCommandBuffer buffer) {
        return vkEndCommandBuffer(buffer);
    }

    void cmd_set_viewport(VkCommandBuffer buffer, VkViewport[] viewports...) {
        vkCmdSetViewport(buffer, 0, cast(uint) viewports.length, viewports.ptr);
    }

    void cmd_begin_render_pass(VkCommandBuffer buffer, ref VkRenderPassBeginInfo render_pass_info) {
        vkCmdBeginRenderPass(buffer, &render_pass_info, VK_SUBPASS_CONTENTS_INLINE);
    }

    void cmd_end_render_pass(VkCommandBuffer buffer) {
        vkCmdEndRenderPass(buffer);
    }

    void cmd_bind_pipeline(VkCommandBuffer buffer, VkPipelineBindPoint bind_point, VkPipeline pipeline) {
        vkCmdBindPipeline(buffer, bind_point, pipeline);
    }

    void cmd_draw(VkCommandBuffer buffer, uint n_verts, uint n_instances, uint first_vert, uint first_instance) {
        vkCmdDraw(buffer, n_verts, n_instances, first_vert, first_instance);
    }

private:
    VulkanDevice _device;
    VkCommandPool _handle;

    static immutable command_pool_functions = [
        "vkQueueSubmit",
        "vkAllocateCommandBuffers",
        "vkFreeCommandBuffers",
        "vkBeginCommandBuffer",
        "vkEndCommandBuffer",
        "vkCmdSetViewport",
        "vkCmdBeginRenderPass",
        "vkCmdEndRenderPass",
        "vkCmdBindPipeline",
        "vkCmdDraw",
    ];

    static foreach (func; command_pool_functions)
        mixin("PFN_" ~ func ~ " " ~ func ~ ";");

    this(VulkanDevice host, VkCommandPool handle) {
        _device = host;
        _handle = handle;
        load_functions();
    }

    void load_functions() {
        static foreach (func; command_pool_functions)
            mixin(func ~ " = cast(PFN_" ~ func ~ ") vkGetDeviceProcAddr(_device.handle, \"" ~ func ~ "\");");
    }
}

CommandPool create_graphics_command_pool(VulkanDevice device) nothrow {
    VkCommandPool handle;
    {
        VkCommandPoolCreateInfo ci = {
            queueFamilyIndex: device.graphics_family,
            flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
        };

        device.d_create_command_pool(ci, handle);
    }

    return new CommandPool(device, handle);
}
