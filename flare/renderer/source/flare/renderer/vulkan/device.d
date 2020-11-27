module flare.renderer.vulkan.device;

import flare.core.memory.temp;
import flare.renderer.vulkan.context;
import flare.renderer.vulkan.gpu;
import flare.renderer.vulkan.h;

immutable device_funcs = [
    "vkDestroyDevice",
    "vkGetDeviceQueue",
    "vkCreateSwapchainKHR",
    "vkDestroySwapchainKHR",
    "vkGetSwapchainImagesKHR",
    "vkCreateImageView",
    "vkDestroyImageView",
];

final class VulkanDevice {

    enum max_queues_per_family = 16;

public:
    VulkanGpuInfo gpu;
    alias gpu this;

    ~this() {
        vkDestroyDevice(handle, null);
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

    VkResult d_create_swapchain(VkSwapchainCreateInfoKHR* sci, VkSwapchainKHR* result) {
        return vkCreateSwapchainKHR(handle, sci, null, result);
    }

    void d_destroy_swapchain(VkSwapchainKHR swapchain) {
        vkDestroySwapchainKHR(handle, swapchain, null);
    }

    VkResult d_get_swapchain_images(VkSwapchainKHR swapchain, uint* count, VkImage* images) {
        return vkGetSwapchainImagesKHR(handle, swapchain, count, images);
    }

    VkResult d_create_image_view(VkImageViewCreateInfo* vci, VkImageView* result) {
        return vkCreateImageView(handle, vci, null, result);
    }

    void d_destroy_image_view(VkImageView view) {
        vkDestroyImageView(handle, view, null);
    }

private:
    const VkDevice _handle;
    VulkanContext _context;

    static foreach (func; device_funcs)
        mixin("PFN_" ~ func ~ " " ~ func ~ ";");

    this(VulkanContext ctx, VkDevice dev, ref VulkanGpuInfo device_info) {
        _context = ctx;
        _handle = dev;
        this.gpu = device_info;
        load_device_functions();
    }

    void load_device_functions() {
        static foreach (func; device_funcs)
            mixin(func ~ " = cast(PFN_" ~ func ~ ") vkGetDeviceProcAddr(handle, \"" ~ func ~ "\");");
    }

    VkQueue get_queue(string name)() {
        VkQueue queue;
        mixin("assert(gpu." ~ name ~ "_family != uint.max);");
        mixin("vkGetDeviceQueue(handle, gpu." ~ name ~ "_family, 0, &queue);");
        return queue;
    }
}

VulkanDevice create_device(ref VulkanContext ctx, ref VulkanGpuInfo gpu) {
    import flare.renderer.vulkan.compat: to_cstr_array;

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
    auto err = vkCreateDevice(gpu.device, &dci, null, &device);

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
