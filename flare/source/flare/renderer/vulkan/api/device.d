module flare.renderer.vulkan.api.device;

import flare.logger: Logger;
import flare.memory;
import flare.renderer.vulkan.api.context;
import flare.renderer.vulkan.api.dispatch;
import flare.renderer.vulkan.api.gpu;
import flare.renderer.vulkan.api.h;
import flare.renderer.vulkan.api.memory;
import flare.renderer.vulkan.api.sync: FencePool, SemaphorePool;

nothrow:

struct Queue {
    VkQueue queue;
    alias queue this;
    uint family;
}

final class VulkanDevice {
    enum max_queues_per_family = 16;

nothrow public:
    ~this() {
        destroy(fence_pool);
        destroy(semaphore_pool);
        destroy(_dispatch);
    }

    VulkanGpuInfo gpu;
    alias gpu this;

    FencePool fence_pool;
    SemaphorePool semaphore_pool;

    // dfmt off
    Queue compute()  in (gpu.queue_families[QueueType.Compute] != uint.max)  { return _queues[QueueType.Compute]; }
    Queue present()  in (gpu.queue_families[QueueType.Present] != uint.max)  { return _queues[QueueType.Present]; }
    Queue graphics() in (gpu.queue_families[QueueType.Graphics] != uint.max) { return _queues[QueueType.Graphics]; }
    Queue transfer() in (gpu.queue_families[QueueType.Transfer] != uint.max) { return _queues[QueueType.Transfer]; }
    // dfmt on

    VkDevice handle() {
        return _dispatch.device;
    }

    inout(VulkanContext) context() inout {
        return _context;
    }

    inout(Logger*) log() inout {
        return &_context.logger;
    }

    DispatchTable* dispatch_table() {
        return &_dispatch;
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

    Queue[QueueType.Count] _queues;

    this(VulkanContext ctx, VkDevice device, ref VulkanGpuInfo device_info) {
        _context = ctx;
        this.gpu = device_info;
        _dispatch = DispatchTable(device, null);

        static foreach (i; 0 .. _queues.length)
            if (gpu.queue_families[i] != uint.max) {
                _dispatch.GetDeviceQueue(gpu.queue_families[i], 0, _queues[i].queue);
                _queues[i].family = gpu.queue_families[i];
            }

        fence_pool = FencePool(&_dispatch, _context.memory);
        semaphore_pool = SemaphorePool(&_dispatch, _context.memory);
    }
}

VulkanDevice create_device(ref VulkanContext ctx, ref VulkanGpuInfo gpu) {
    import flare.renderer.vulkan.api.compat: to_cstr_array;

    auto mem = scoped_arena(ctx.memory);
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
            gpu.queue_families[QueueType.Compute],
            gpu.queue_families[QueueType.Present],
            gpu.queue_families[QueueType.Graphics],
            gpu.queue_families[QueueType.Transfer],
    );

    return new VulkanDevice(ctx, device, gpu);
}

private:

VkDeviceQueueCreateInfo[] create_queue_create_infos(in VulkanGpuInfo device_info, ref ScopedArena mem) {
    import std.algorithm : count, filter, sort, uniq;

    QueueFamilies all_families = device_info.queue_families;
    auto families = all_families[].sort().filter!(i => i != uint.max).uniq();
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
