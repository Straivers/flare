module flare.vulkan.dispatch;

import flare.vulkan.h;

struct DispatchTable {
@nogc nothrow:
    this(VkDevice device, VkAllocationCallbacks* mem_callbacks) {
        _device = device;
        _allocator = mem_callbacks;

        static foreach (func; func_names) {
            mixin(func ~ " = cast(PFN_" ~ func ~ ") vkGetDeviceProcAddr(device, \"" ~ func ~ "\");");
            mixin("assert(" ~ func ~ ", \"Could not load " ~ func ~ "\");");
        }
    }

    VkDevice device() const { return cast(VkDevice) _device; }

    // dfmt off
    void DestroyDevice() { vkDestroyDevice(_device, _allocator); }
    VkResult DeviceWaitIdle() { return check!vkDeviceWaitIdle(_device); }
    
    VkResult CreateSemaphore(in VkSemaphoreCreateInfo create_info, out VkSemaphore semaphore) { return check!vkCreateSemaphore(_device, &create_info, _allocator, &semaphore); }
    void DestroySemaphore(VkSemaphore semaphore) { vkDestroySemaphore(_device, semaphore, _allocator); }

    VkResult CreateFence(in VkFenceCreateInfo create_info, out VkFence fence) { return check!vkCreateFence(_device, &create_info, _allocator, &fence); }
    void DestroyFence(VkFence fence) { vkDestroyFence(_device, fence, _allocator); }
    VkResult ResetFences(VkFence[] fences...) { return check!vkResetFences(_device, cast(uint) fences.length, fences.ptr); }
    VkResult WaitForFences(VkFence[] fences, bool wait_all, ulong timeout) { return check!vkWaitForFences(_device, cast(uint) fences.length, fences.ptr, wait_all ? VK_TRUE : VK_FALSE, timeout); }

    void GetDeviceQueue(uint queue_family_index, uint queue_index, out VkQueue p_queue) { vkGetDeviceQueue(_device, queue_family_index, queue_index, &p_queue); }
    VkResult QueueSubmit(VkQueue queue, VkFence fence, VkSubmitInfo[] submits...) { return check!vkQueueSubmit(queue, cast(uint) submits.length, submits.ptr, fence); }
    VkResult QueueWaitIdle(VkQueue queue) { return check!vkQueueWaitIdle(queue); }

    VkResult CreateImageView(in VkImageViewCreateInfo create_info, out VkImageView view) { return check!vkCreateImageView(_device, &create_info, _allocator, &view); }
    void DestroyImageView(VkImageView view) { vkDestroyImageView(_device, view, _allocator); }

    VkResult CreateFramebuffer(in VkFramebufferCreateInfo create_info, out VkFramebuffer framebuffer) { return check!vkCreateFramebuffer(_device, &create_info, _allocator, &framebuffer); }
    void DestroyFramebuffer(VkFramebuffer framebuffer) { return vkDestroyFramebuffer(_device, framebuffer, _allocator); }

    VkResult CreateRenderPass(in VkRenderPassCreateInfo create_info, out VkRenderPass renderpass) { return check!vkCreateRenderPass(_device, &create_info, _allocator, &renderpass); }
    void DestroyRenderPass(VkRenderPass renderpass) { vkDestroyRenderPass(_device, renderpass, _allocator); }

    VkResult CreateShaderModule(in VkShaderModuleCreateInfo create_info, out VkShaderModule shader) { return check!vkCreateShaderModule(_device, &create_info, _allocator, &shader); }
    void DestroyShaderModule(VkShaderModule shader) { vkDestroyShaderModule(_device, shader, _allocator); }

    VkResult CreatePipelineLayout(in VkPipelineLayoutCreateInfo create_info, out VkPipelineLayout layout) { return check!vkCreatePipelineLayout(_device, &create_info, _allocator, &layout); }
    void DestroyPipelineLayout(VkPipelineLayout layout) { vkDestroyPipelineLayout(_device, layout, _allocator); }

    VkResult CreateGraphicsPipelines(VkPipelineCache cache, VkGraphicsPipelineCreateInfo[] create_infos, VkPipeline[] pipelines) { return check!vkCreateGraphicsPipelines(_device, cache, cast(uint) create_infos.length, create_infos.ptr, _allocator, pipelines.ptr); }
    void DestroyPipeline(VkPipeline pipeline) { vkDestroyPipeline(_device, pipeline, _allocator); }

    VkResult CreateCommandPool(in VkCommandPoolCreateInfo create_info, out VkCommandPool pool) { return check!vkCreateCommandPool(_device, &create_info, _allocator, &pool); }
    void DestroyCommandPool(VkCommandPool pool) { vkDestroyCommandPool(_device, pool, _allocator); }
    VkResult ResetCommandPool(VkCommandPool pool, VkCommandPoolResetFlags flags) { return check!vkResetCommandPool(_device, pool, flags); }

    VkResult AllocateCommandBuffers(in VkCommandBufferAllocateInfo alloc_info, VkCommandBuffer[] buffers) { return check!vkAllocateCommandBuffers(_device, &alloc_info, buffers.ptr); }
    void FreeCommandBuffers(VkCommandPool pool, VkCommandBuffer[] buffers...) { vkFreeCommandBuffers(_device, pool, cast(uint) buffers.length, buffers.ptr); }
    VkResult BeginCommandBuffer(VkCommandBuffer cmds, in VkCommandBufferBeginInfo begin_info) { return check!vkBeginCommandBuffer(cmds, &begin_info); }
    VkResult EndCommandBuffer(VkCommandBuffer cmds) { return check!vkEndCommandBuffer(cmds); } 

    void CmdSetViewport(VkCommandBuffer cmds, in VkViewport[] viewports...) { vkCmdSetViewport(cmds, 0, cast(uint) viewports.length, viewports.ptr); }
    void CmdSetScissor(VkCommandBuffer cmds, in VkRect2D[] scissor_rects...) { vkCmdSetScissor(cmds, 0, cast(uint) scissor_rects.length, scissor_rects.ptr); }
    void CmdBeginRenderPass(VkCommandBuffer cmds, in VkRenderPassBeginInfo begin_info, VkSubpassContents contents) { vkCmdBeginRenderPass(cmds, &begin_info, contents); }
    void CmdEndRenderPass(VkCommandBuffer cmds) { vkCmdEndRenderPass(cmds); }
    void CmdPipelineBarrier(VkCommandBuffer cmds, VkPipelineStageFlags src_flags, VkPipelineStageFlags dst_flags, VkDependencyFlags dependencies, VkMemoryBarrier[] memory_barriers, VkBufferMemoryBarrier[] buffer_barriers, VkImageMemoryBarrier[] image_barriers) { vkCmdPipelineBarrier(cmds, src_flags, dst_flags, dependencies, cast(uint) memory_barriers.length, memory_barriers.ptr, cast(uint) buffer_barriers.length, buffer_barriers.ptr, cast(uint) image_barriers.length, image_barriers.ptr); }
    void CmdBindPipeline(VkCommandBuffer cmds, VkPipelineBindPoint bind_point, VkPipeline pipeline) { vkCmdBindPipeline(cmds, bind_point, pipeline); }
    void CmdBindVertexBuffers(VkCommandBuffer cmds, in VkBuffer[] buffers, in VkDeviceSize[] offsets) { vkCmdBindVertexBuffers(cmds, 0, cast(uint) buffers.length, buffers.ptr, offsets.ptr); }
    void CmdBindIndexBuffer(VkCommandBuffer cmds, VkBuffer buffer, VkDeviceSize offset, VkIndexType index_type) { vkCmdBindIndexBuffer(cmds, buffer, offset, index_type); }
    void CmdDraw(VkCommandBuffer cmds, uint n_vertices, uint n_instances, uint first_vertex, uint first_instance) { vkCmdDraw(cmds, n_vertices, n_instances, first_vertex, first_instance); }
    void CmdDrawIndexed(VkCommandBuffer cmds, uint n_indices, uint n_instances, uint first_index, uint vertex_offset, uint first_instance) { vkCmdDrawIndexed(cmds, n_indices, n_instances, first_index, vertex_offset, first_instance); }
    void CmdCopyBuffer(VkCommandBuffer cmds, VkBuffer src, VkBuffer dst, VkBufferCopy[] regions...) { vkCmdCopyBuffer(cmds, src, dst, cast(uint) regions.length, regions.ptr); }

    VkResult CreateBuffer(in VkBufferCreateInfo create_info, out VkBuffer buffer) { return check!vkCreateBuffer(_device, &create_info, _allocator, &buffer); }
    void DestroyBuffer(VkBuffer buffer) { vkDestroyBuffer(_device, buffer, _allocator); }
    void GetBufferMemoryRequirements(VkBuffer buffer, out VkMemoryRequirements requirements) { vkGetBufferMemoryRequirements(_device, buffer, &requirements); }
    VkResult AllocateMemory(in VkMemoryAllocateInfo alloc_info, out VkDeviceMemory memory) { return check!vkAllocateMemory(_device, &alloc_info, _allocator, &memory); }
    void FreeMemory(VkDeviceMemory memory) { vkFreeMemory(_device, memory, _allocator); }
    VkResult BindBufferMemory(VkBuffer buffer, VkDeviceMemory memory, VkDeviceSize offset) { return check!vkBindBufferMemory(_device, buffer, memory, offset); }
    VkResult MapMemory(VkDeviceMemory memory, VkDeviceSize offset, VkDeviceSize size, VkMemoryMapFlags flags, out void* data) { return check!vkMapMemory(_device, memory, offset, size, flags, &data); }
    void UnmapMemory(VkDeviceMemory memory) { vkUnmapMemory(_device, memory); }
    VkResult FlushMappedMemoryRanges(in VkMappedMemoryRange[] ranges...) { return check!vkFlushMappedMemoryRanges(_device, cast(uint) ranges.length, ranges.ptr); }

    VkResult CreateSwapchainKHR(in VkSwapchainCreateInfoKHR create_info, out VkSwapchainKHR swapchain) { return check!vkCreateSwapchainKHR(_device, &create_info, _allocator, &swapchain); }
    void DestroySwapchainKHR(VkSwapchainKHR swapchain) { return vkDestroySwapchainKHR(_device, swapchain, _allocator); }
    VkResult GetSwapchainImagesKHR(VkSwapchainKHR swapchain, ref uint count, VkImage* images) { return check!vkGetSwapchainImagesKHR(_device, swapchain, &count, images); }
    VkResult AcquireNextImageKHR(VkSwapchainKHR swapchain, ulong timeout, VkSemaphore semaphore, VkFence fence, ref uint image_index) { return check!vkAcquireNextImageKHR(_device, swapchain, timeout, semaphore, fence, &image_index); }
    VkResult QueuePresentKHR(VkQueue queue, in VkPresentInfoKHR present_info) { return check!vkQueuePresentKHR(queue, &present_info); }
    // dfmt on

private:
    static immutable func_names = [
        "vkDestroyDevice",
        "vkDeviceWaitIdle",

        "vkCreateSemaphore",
        "vkDestroySemaphore",
        
        "vkCreateFence",
        "vkDestroyFence",
        "vkResetFences",
        "vkWaitForFences",
        
        "vkGetDeviceQueue",
        "vkQueueSubmit",
        "vkQueueWaitIdle",
        
        "vkCreateImageView",
        "vkDestroyImageView",
        
        "vkCreateFramebuffer",
        "vkDestroyFramebuffer",

        "vkCreateRenderPass",
        "vkDestroyRenderPass",
        
        "vkCreateShaderModule",
        "vkDestroyShaderModule",
        
        "vkCreatePipelineLayout",
        "vkDestroyPipelineLayout",
        
        "vkCreateGraphicsPipelines",
        "vkDestroyPipeline",
        
        "vkCreateCommandPool",
        "vkDestroyCommandPool",
        "vkResetCommandPool",
        
        "vkAllocateCommandBuffers",
        "vkFreeCommandBuffers",
        "vkBeginCommandBuffer",
        "vkEndCommandBuffer",

        "vkCmdSetViewport",
        "vkCmdSetScissor",
        "vkCmdBeginRenderPass",
        "vkCmdEndRenderPass",
        "vkCmdBindPipeline",
        "vkCmdBindVertexBuffers",
        "vkCmdBindIndexBuffer",
        "vkCmdPipelineBarrier",
        "vkCmdDraw",
        "vkCmdDrawIndexed",
        "vkCmdCopyBuffer",
        
        "vkCreateBuffer",
        "vkDestroyBuffer",
        "vkGetBufferMemoryRequirements",
        "vkAllocateMemory",
        "vkFreeMemory",
        "vkBindBufferMemory",
        "vkMapMemory",
        "vkUnmapMemory",
        "vkFlushMappedMemoryRanges",
        
        "vkCreateSwapchainKHR",
        "vkDestroySwapchainKHR",
        "vkGetSwapchainImagesKHR",
        "vkAcquireNextImageKHR",
        "vkQueuePresentKHR",
    ];

    VkResult check(alias Fn, Args...)(Args args) {
        const result = Fn(args);

        if (result < 0) {
            assert(0, "Call to " ~ Fn.stringof ~ " failed");
        }

        return result;
    }

    VkDevice _device;
    VkAllocationCallbacks* _allocator;

    static foreach (func; func_names)
        mixin("PFN_" ~ func ~ " " ~ func ~ ";");
}
