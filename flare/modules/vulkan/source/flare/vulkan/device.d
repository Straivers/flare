module flare.vulkan.device;

import flare.core.memory.temp;
import flare.vulkan.context;
import flare.vulkan.gpu;
import flare.vulkan.h;

nothrow:

struct VulkanDeviceDispatchTable {
nothrow:
    this(VulkanDevice device) {
        static foreach (func; func_names) {
            mixin(func ~ " = cast(PFN_" ~ func ~ ") vkGetDeviceProcAddr(device.handle, \"" ~ func ~ "\");");
            mixin("assert(" ~ func ~ ", \"Could not load " ~ func ~ "\");");
        }
    }

    auto opDispatch(string op, Args...)(Args args) {
        mixin("return vk" ~ op ~ "(args);");
    }

private:
    static immutable func_names = [
        "vkDestroyDevice",
        "vkGetDeviceQueue",
        "vkQueueWaitIdle",
        "vkDeviceWaitIdle",
        "vkCreateSemaphore",
        "vkDestroySemaphore",
        "vkCreateFence",
        "vkDestroyFence",
        "vkResetFences",
        "vkWaitForFences",
        "vkCreateSwapchainKHR",
        "vkDestroySwapchainKHR",
        "vkGetSwapchainImagesKHR",
        "vkAcquireNextImageKHR",
        "vkQueuePresentKHR",
        "vkCreateImageView",
        "vkDestroyImageView",
        "vkCreateShaderModule",
        "vkDestroyShaderModule",
        "vkCreatePipelineLayout",
        "vkDestroyPipelineLayout",
        "vkCreateRenderPass",
        "vkDestroyRenderPass",
        "vkCreateGraphicsPipelines",
        "vkDestroyPipeline",
        "vkCreateFramebuffer",
        "vkDestroyFramebuffer",
        "vkCreateCommandPool",
        "vkDestroyCommandPool",
        "vkAllocateCommandBuffers",
        "vkFreeCommandBuffers"
    ];

    static foreach (func; func_names)
        mixin("PFN_" ~ func ~ " " ~ func ~ ";");
}

final class VulkanDevice {
    enum max_queues_per_family = 16;

nothrow public:
    VulkanGpuInfo gpu;
    alias gpu this;

    ~this() {
        _dispatch.DestroyDevice(handle, null);
    }

    VkDevice handle() const {
        return cast(VkDevice) _handle;
    }

    inout(VulkanContext) context() inout {
        return _context;
    }

    VkQueue compute() {
        return get_queue!"compute"();
    }

    VkQueue present() {
        return get_queue!"present"();
    }

    VkQueue graphics() {
        return get_queue!"graphics"();
    }

    VkQueue transfer() {
        return get_queue!"transfer"();
    }

    VulkanDeviceDispatchTable* dispatch_table() {
        return &_dispatch;
    }

    VkSemaphore create_semaphore() {
        VkSemaphoreCreateInfo ci;
        VkSemaphore semaphore;

        const err = _dispatch.CreateSemaphore(handle, &ci, null, &semaphore);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkCreateSemaphore failed: %s", err);
            assert(0, "Call to vkCreateSemaphore failed");
        }

        return semaphore;
    }

    void destroy_semaphore(VkSemaphore semaphore) {
        _dispatch.DestroySemaphore(handle, semaphore, null);
    }

    VkFence create_fence(bool start_signalled = false) {
        VkFenceCreateInfo ci;

        if (start_signalled)
            ci.flags = VK_FENCE_CREATE_SIGNALED_BIT;

        VkFence fence;
        const err = _dispatch.CreateFence(handle, &ci, null, &fence);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkCreateFence failed: %s", err);
            assert(0, "Call to vkCreateFence failed");
        }

        return fence;
    }

    void destroy_fence(VkFence fence) {
        _dispatch.DestroyFence(handle, fence, null);
    }

    void reset_fences(VkFence[] fences...) {
        const err = _dispatch.ResetFences(handle, cast(uint) fences.length, fences.ptr);
        assert(err == VK_SUCCESS);
    }

    void wait_fences(bool wait_all, VkFence[] fences...) {
        const err = _dispatch.WaitForFences(handle, cast(uint) fences.length, fences.ptr, wait_all ? VK_TRUE : VK_FALSE, ulong.max);
        assert(err == VK_SUCCESS);
    }

    void wait_idle() {
        _dispatch.DeviceWaitIdle(handle);
    }

    void wait_idle(VkQueue queue) {
        _dispatch.QueueWaitIdle(queue);
    }

    void d_create_swapchain(VkSwapchainCreateInfoKHR* sci, VkSwapchainKHR* result) {
        const err = _dispatch.CreateSwapchainKHR(handle, sci, null, result);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkCreateSwapchainKHR failed: %s", err);
            assert(0, "Call to vkCreateSwapchainKHR failed");
        }
    }

    void d_destroy_swapchain(VkSwapchainKHR swapchain) {
        _dispatch.DestroySwapchainKHR(handle, swapchain, null);
    }

    void d_acquire_next_image(VkSwapchainKHR swapchain, ulong timeout, VkSemaphore semaphore, VkFence fence, uint* image_index) {
        const err = _dispatch.AcquireNextImageKHR(handle, swapchain, timeout, semaphore, fence, image_index);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkAcquireNextImageKHR failed: %s", err);
            assert(0, "Call to vkAcquireNextImageKHR failed");
        }
    }

    void d_get_swapchain_images(VkSwapchainKHR swapchain, uint* count, VkImage* images) {
        const err = _dispatch.GetSwapchainImagesKHR(handle, swapchain, count, images);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkGetSwapchainImagesKHR failed: %s", err);
            assert(0, "Call to vkGetSwapchainImagesKHR failed");
        }
    }

    void d_queue_present(VkQueue queue, VkPresentInfoKHR* pi) {
        const err = _dispatch.QueuePresentKHR(queue, pi);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkQueuePresent failed: %s", err);
            assert(0, "Call to vkQueuePresent failed");
        }
    }

    void d_create_image_view(VkImageViewCreateInfo* vci, VkImageView* result) {
        const err = _dispatch.CreateImageView(handle, vci, null, result);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkCreateImageView failed: %s", err);
            assert(0, "Call to vkCreateImageView failed");
        }
    }

    void d_destroy_image_view(VkImageView view) {
        _dispatch.DestroyImageView(handle, view, null);
    }

    void d_create_shader_module(VkShaderModuleCreateInfo* ci, VkShaderModule* result) {
        const err = _dispatch.CreateShaderModule(handle, ci, null, result);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkCreateShaderModule failed: %s", err);
            assert(0, "Call to vkCreateShaderModule failed");
        }
    }

    void d_destroy_shader_module(VkShaderModule shader) {
        _dispatch.DestroyShaderModule(handle, shader, null);
    }

    void d_create_pipeline_layout(VkPipelineLayoutCreateInfo* ci, VkPipelineLayout* result) {
        const err = _dispatch.CreatePipelineLayout(handle, ci, null, result);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkCreatePipelineLayout failed: %s", err);
            assert(0, "Call to vkCreatePipelineLayout failed");
        }
    }

    void d_destroy_pipeline_layout(VkPipelineLayout pipeline) {
        _dispatch.DestroyPipelineLayout(handle, pipeline, null);
    }

    void d_create_render_pass(VkRenderPassCreateInfo* ci, VkRenderPass* result) {
        const err = _dispatch.CreateRenderPass(handle, ci, null, result);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkCreateRenderPass failed: %s", err);
            assert(0, "Call to vkCreateRenderPass failed");
        }
    }

    void d_destroy_render_pass(VkRenderPass pass) {
        _dispatch.DestroyRenderPass(handle, pass, null);
    }

    void d_create_graphics_pipelines(VkPipelineCache cache, VkGraphicsPipelineCreateInfo[] infos, VkPipeline[] result) {
        assert(infos.length == result.length);
        const err = _dispatch.CreateGraphicsPipelines(handle, cache, cast(uint) infos.length, infos.ptr, null, result.ptr);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkCreateGraphicsPipelines failed: %s", err);
            assert(0, "Call to vkCreateGraphicsPipelines failed");
        }
    }

    void d_destroy_pipeline(VkPipeline pipeline) {
        _dispatch.DestroyPipeline(handle, pipeline, null);
    }

    void d_create_framebuffer(VkFramebufferCreateInfo* ci, VkFramebuffer* result) {
        const err = _dispatch.CreateFramebuffer(handle, ci, null, result);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkCreateFramebuffer failed: %s", err);
            assert(0, "Call to vkCreateFramebuffer failed");
        }
    }

    void d_destroy_framebuffer(VkFramebuffer buffer) {
        _dispatch.DestroyFramebuffer(handle, buffer, null);
    }

    void d_create_command_pool(VkCommandPoolCreateInfo* ci, VkCommandPool* result) {
        const err = _dispatch.CreateCommandPool(handle, ci, null, result);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkCreateCommandPool failed: %s", err);
            assert(0, "Call to vkCreateCommandPool failed");
        }
    }

    void d_destroy_command_pool(VkCommandPool pool) {
        _dispatch.DestroyCommandPool(handle, pool, null);
    }

    void d_allocate_command_buffers(VkCommandBufferAllocateInfo* ai, VkCommandBuffer[] buffers) {
        const err = _dispatch.AllocateCommandBuffers(handle, ai, buffers.ptr);
        if (err != VK_SUCCESS) {
            context.logger.fatal("Call to vkAllocateCommandBuffers failed: %s", err);
            assert(0, "Call to vkAllocateCommandBuffers failed");
        }
    }

nothrow private:
    const VkDevice _handle;
    VulkanContext _context;
    VulkanDeviceDispatchTable _dispatch;

    this(VulkanContext ctx, VkDevice dev, ref VulkanGpuInfo device_info) {
        _context = ctx;
        _handle = dev;
        this.gpu = device_info;
        _dispatch = VulkanDeviceDispatchTable(this);
    }

    VkQueue get_queue(string name)() {
        VkQueue queue;
        mixin("assert(gpu." ~ name ~ "_family != uint.max);");
        mixin("_dispatch.GetDeviceQueue(handle, gpu." ~ name ~ "_family, 0, &queue);");
        return queue;
    }
}

VulkanDevice create_device(ref VulkanContext ctx, ref VulkanGpuInfo gpu) {
    import flare.vulkan.compat: to_cstr_array;

    auto mem = TempAllocator(ctx.memory);
    auto queues = create_queue_create_infos(gpu, mem);

    VkPhysicalDeviceFeatures default_features;

    auto extensions = to_cstr_array(gpu.enabled_extensions, mem);

    // dfmt off
    VkDeviceCreateInfo dci = {
        pQueueCreateInfos: queues.ptr,
        queueCreateInfoCount: cast(uint) queues.length,
        ppEnabledExtensionNames: extensions.ptr,
        enabledExtensionCount: cast(uint) extensions.length,
        pEnabledFeatures: &default_features,
    };
    // dfmt on

    VkDevice device;
    const err = vkCreateDevice(gpu.handle, &dci, null, &device);

    if (err != VK_SUCCESS) {
        ctx.logger.fatal("Could not create Vulkan device: %s", err);
        assert(0, "Could not create Vulkan device");
    }

    ctx.logger.info("Vulkan device created with:\n\tExtensions:%-( %s%)\n\tCompute family:  %s\n\tPresent family:  %s\n\tGraphics family: %s\n\tTransfer family: %s",
            gpu.enabled_extensions,
            gpu.compute_family,
            gpu.present_family,
            gpu.graphics_family,
            gpu.transfer_family,
    );

    return new VulkanDevice(ctx, device, gpu);
}

private:

auto create_queue_create_infos(in VulkanGpuInfo device_info, ref TempAllocator mem) {
    import std.algorithm: filter, uniq;

    uint[4] all_families = [
        device_info.compute_family,
        device_info.graphics_family,
        device_info.transfer_family,
        device_info.present_family,
    ];

    auto families = all_families[].filter!(f => f != uint.max).uniq();
    const n_families = () {
        uint count;
        foreach (fam; families.save())
            count++;
        return count;
    } ();

    auto dwcis = mem.alloc_array!VkDeviceQueueCreateInfo(n_families);
    auto priority = mem.alloc_object!float(1.0);

    foreach (i, ref ci; dwcis) {
        ci.queueFamilyIndex = families.front;
        ci.queueCount = 1;
        ci.pQueuePriorities = priority;

        families.popFront();
    }

    return dwcis;
}
