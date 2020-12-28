module flare.vulkan.device;

import flare.core.memory.temp;
import flare.vulkan.context;
import flare.vulkan.gpu;
import flare.vulkan.h;
import flare.vulkan.dispatch;

nothrow:

final class VulkanDevice {
    enum max_queues_per_family = 16;

nothrow public:
    VulkanGpuInfo gpu;
    alias gpu this;

    ~this() {
        _dispatch.DestroyDevice();
    }

    VkDevice handle() const {
        return cast(VkDevice) _dispatch.device;
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

    DispatchTable* dispatch_table() {
        return &_dispatch;
    }

    VkSemaphore create_semaphore() {
        VkSemaphoreCreateInfo ci;
        VkSemaphore semaphore;

        _dispatch.CreateSemaphore(ci, semaphore);
        return semaphore;
    }

    void destroy_semaphore(VkSemaphore semaphore) {
        _dispatch.DestroySemaphore(semaphore);
    }

    VkFence create_fence(bool start_signalled = false) {
        VkFenceCreateInfo ci;

        if (start_signalled)
            ci.flags = VK_FENCE_CREATE_SIGNALED_BIT;

        VkFence fence;
        _dispatch.CreateFence(ci, fence);
        return fence;
    }

    void destroy_fence(VkFence fence) {
        _dispatch.DestroyFence(fence);
    }

    void reset_fences(VkFence[] fences...) {
        _dispatch.ResetFences(fences);
    }

    void wait_fences(bool wait_all, VkFence[] fences...) {
        _dispatch.WaitForFences(fences, wait_all, ulong.max);
    }

    void wait_idle() {
        _dispatch.DeviceWaitIdle();
    }

    void wait_idle(VkQueue queue) {
        _dispatch.QueueWaitIdle(queue);
    }

    void d_create_swapchain(in VkSwapchainCreateInfoKHR sci, out VkSwapchainKHR result) {
        _dispatch.CreateSwapchainKHR(sci, result);
    }

    void d_destroy_swapchain(VkSwapchainKHR swapchain) {
        _dispatch.DestroySwapchainKHR(swapchain);
    }

    VkResult d_acquire_next_image(VkSwapchainKHR swapchain, ulong timeout, VkSemaphore semaphore, VkFence fence, ref uint image_index) {
        return _dispatch.AcquireNextImageKHR(swapchain, timeout, semaphore, fence, image_index);
    }

    void d_get_swapchain_images(VkSwapchainKHR swapchain, ref uint count, VkImage* images) {
        _dispatch.GetSwapchainImagesKHR(swapchain, count, images);
    }

    VkResult d_queue_present(VkQueue queue, in VkPresentInfoKHR pi) {
        return _dispatch.QueuePresentKHR(queue, pi);
    }

    void d_create_image_view(in VkImageViewCreateInfo vci, out VkImageView result) {
       _dispatch.CreateImageView(vci, result);
    }

    void d_destroy_image_view(VkImageView view) {
        _dispatch.DestroyImageView(view);
    }

    void d_create_shader_module(in VkShaderModuleCreateInfo ci, out VkShaderModule result) {
       _dispatch.CreateShaderModule(ci, result);
    }

    void d_destroy_shader_module(VkShaderModule shader) {
        _dispatch.DestroyShaderModule(shader);
    }

    void d_create_pipeline_layout(in VkPipelineLayoutCreateInfo ci, out VkPipelineLayout result) {
        _dispatch.CreatePipelineLayout(ci, result);
    }

    void d_destroy_pipeline_layout(VkPipelineLayout pipeline) {
        _dispatch.DestroyPipelineLayout(pipeline);
    }

    void d_create_render_pass(in VkRenderPassCreateInfo ci, out VkRenderPass result) {
        _dispatch.CreateRenderPass(ci, result);
    }

    void d_destroy_render_pass(VkRenderPass pass) {
        _dispatch.DestroyRenderPass(pass);
    }

    void d_create_graphics_pipelines(VkPipelineCache cache, VkGraphicsPipelineCreateInfo[] infos, VkPipeline[] result) {
        assert(infos.length == result.length);
        _dispatch.CreateGraphicsPipelines(cache, infos, result);
    }

    void d_destroy_pipeline(VkPipeline pipeline) {
        _dispatch.DestroyPipeline(pipeline);
    }

    void d_create_framebuffer(in VkFramebufferCreateInfo ci, out VkFramebuffer result) {
        _dispatch.CreateFramebuffer(ci, result);
    }

    void d_destroy_framebuffer(VkFramebuffer buffer) {
        _dispatch.DestroyFramebuffer(buffer);
    }

    void d_create_command_pool(in VkCommandPoolCreateInfo ci, out VkCommandPool result) {
        _dispatch.CreateCommandPool(ci, result);
    }

    void d_destroy_command_pool(VkCommandPool pool) {
        _dispatch.DestroyCommandPool(pool);
    }

    void d_allocate_command_buffers(in VkCommandBufferAllocateInfo ai, VkCommandBuffer[] buffers) {
        _dispatch.AllocateCommandBuffers(ai, buffers);
    }

nothrow private:
    const VkDevice _handle;
    VulkanContext _context;
    DispatchTable _dispatch;

    this(VulkanContext ctx, VkDevice device, ref VulkanGpuInfo device_info) {
        _context = ctx;
        _handle = device;
        this.gpu = device_info;
        _dispatch = DispatchTable(device, null);
    }

    VkQueue get_queue(string name)() {
        VkQueue queue;
        mixin("assert(gpu." ~ name ~ "_family != uint.max);");
        mixin("_dispatch.GetDeviceQueue(gpu." ~ name ~ "_family, 0, queue);");
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
