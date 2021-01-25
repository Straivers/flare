module flare.vulkan.device;

import flare.core.memory;
import flare.vulkan.context;
import flare.vulkan.dispatch;
import flare.vulkan.gpu;
import flare.vulkan.h;
import flare.vulkan.memory;

nothrow:

final class VulkanDevice {
    enum max_queues_per_family = 16;

nothrow public:
    VulkanGpuInfo gpu;
    alias gpu this;

    ~this() {
        _dispatch.DestroyDevice();
        destroy(_memory);
    }

    // dfmt off
    VkQueue compute() { return _compute_queue; }

    VkQueue present() { return _present_queue; }

    VkQueue graphics() { return _graphics_queue; }

    VkQueue transfer() { return _transfer_queue; }
    // dfmt on

    VkDevice handle() const {
        return cast(VkDevice) _dispatch.device;
    }

    inout(VulkanContext) context() inout {
        return _context;
    }

    DispatchTable* dispatch_table() {
        return &_dispatch;
    }

    DeviceMemory* memory() {
        return &_memory;
    }

    void wait_idle() {
        _dispatch.DeviceWaitIdle();
    }

    void wait_idle(VkQueue queue) {
        _dispatch.QueueWaitIdle(queue);
    }

nothrow private:
    VulkanContext _context;
    DispatchTable _dispatch;
    DeviceMemory _memory;

    VkQueue _compute_queue;
    VkQueue _present_queue;
    VkQueue _graphics_queue;
    VkQueue _transfer_queue;

    this(VulkanContext ctx, VkDevice device, ref VulkanGpuInfo device_info) {
        _context = ctx;
        this.gpu = device_info;
        _dispatch = DispatchTable(device, null);
        _memory = DeviceMemory(&_dispatch, gpu.handle);

        if (gpu.compute_family != uint.max)
            _dispatch.GetDeviceQueue(gpu.compute_family, 0, _compute_queue);
        
        if (gpu.present_family != uint.max)
            _dispatch.GetDeviceQueue(gpu.present_family, 0, _present_queue);

        if (gpu.graphics_family != uint.max)
            _dispatch.GetDeviceQueue(gpu.graphics_family, 0, _graphics_queue);

        if (gpu.transfer_family != uint.max)
            _dispatch.GetDeviceQueue(gpu.transfer_family, 0, _transfer_queue);
    }
}

VulkanDevice create_device(ref VulkanContext ctx, ref VulkanGpuInfo gpu) {
    import flare.vulkan.compat: to_cstr_array;

    auto mem = temp_arena(ctx.memory);
    const queues = create_queue_create_infos(gpu, mem);

    VkPhysicalDeviceFeatures default_features;

    auto extensions = to_cstr_array(gpu.extensions, mem);

    // dfmt off
    VkDeviceCreateInfo dci = {
        pQueueCreateInfos: queues.length ? queues.ptr : null,
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
            gpu.extensions,
            gpu.compute_family,
            gpu.present_family,
            gpu.graphics_family,
            gpu.transfer_family,
    );

    return new VulkanDevice(ctx, device, gpu);
}

private:

VkDeviceQueueCreateInfo[] create_queue_create_infos(in VulkanGpuInfo device_info, ref ScopedArena mem) {
    import std.algorithm: swap, uniq, count, filter;

    uint[4] all_families = [
        device_info.compute_family,
        device_info.graphics_family,
        device_info.transfer_family,
        device_info.present_family,
    ];

    bool sorted;
    while (!sorted) {
        sorted = true;
        for (int i = 0; i + 1 < all_families.length; i++) {
            if (all_families[i] > all_families[i + 1]) {
                swap(all_families[i], all_families[i + 1]);
                sorted = false;
            }
        }
    }

    auto families = all_families[].filter!(i => i != uint.max).uniq();
    auto dwcis = mem.make_array!VkDeviceQueueCreateInfo(families.save().count());
    auto priority = mem.make_array!float(1);
    priority[0] = 1;

    foreach (i, ref ci; dwcis) {
        ci.queueFamilyIndex = families.front;
        ci.queueCount = 1;
        ci.pQueuePriorities = priority.ptr;
        families.popFront();
    }

    return dwcis;
}
