module flare.vulkan.gpu;

import flare.core.memory.temp;
import flare.vulkan.context;
import flare.vulkan.h;

nothrow:

struct VulkanGpuInfo {
    // device properties
    VkPhysicalDevice handle;
    VkPhysicalDeviceProperties properties;
    VkPhysicalDeviceMemoryProperties memory_properties;
    VkExtensionProperties[] available_extensions;
    VkQueueFamilyProperties[] queue_families;

    // post-filter members
    const(string)[] enabled_extensions;

    // selected queue families
    /// Left empty until device selection
    uint compute_family = uint.max;
    /// ditto
    uint graphics_family = uint.max;
    /// ditto
    uint transfer_family = uint.max;
    /// ditto
    uint present_family = uint.max;
}

struct VulkanDeviceCriteria {
    bool compute_queue;
    bool graphics_queue;
    bool transfer_queue;

    VkSurfaceKHR display_target;

    const(string)[] required_extensions;
}

void load_gpu_info(
    VkPhysicalDevice device,
    ref TempAllocator mem,
    out VulkanGpuInfo result
) {
    result.handle = device;
    vkGetPhysicalDeviceProperties(device, &result.properties);
    vkGetPhysicalDeviceMemoryProperties(device, &result.memory_properties);

    uint n_queues;
    vkGetPhysicalDeviceQueueFamilyProperties(device, &n_queues, null);
    result.queue_families = mem.alloc_array!VkQueueFamilyProperties(n_queues);
    vkGetPhysicalDeviceQueueFamilyProperties(device, &n_queues, result.queue_families.ptr);

    uint n_extensions;
    vkEnumerateDeviceExtensionProperties(device, null, &n_extensions, null);
    result.available_extensions = mem.alloc_array!VkExtensionProperties(n_extensions);
    vkEnumerateDeviceExtensionProperties(device, null, &n_extensions, result.available_extensions.ptr);
}

bool select_gpu(VulkanContext ctx, ref VulkanDeviceCriteria criteria, out VulkanGpuInfo result) {
    uint n_devices;
    vkEnumeratePhysicalDevices(ctx.instance, &n_devices, null);
    auto devices = ctx.memory.alloc_array!VkPhysicalDevice(n_devices);
    scope (exit) ctx.memory.free(devices);
    vkEnumeratePhysicalDevices(ctx.instance, &n_devices, devices.ptr);

    foreach (device; devices) {
        auto mem = TempAllocator(ctx.memory, 64.kib);

        VulkanGpuInfo gpu;
        load_gpu_info(device, mem, gpu);
        gpu.enabled_extensions = criteria.required_extensions;

        const queues_ok = select_queue_families(gpu, criteria);
        const extensions_ok = has_extensions(gpu, criteria, mem);

        if (queues_ok && extensions_ok) {
            result = gpu;
            return true;
        }
    }

    return false;
}

private:

bool select_queue_families(ref VulkanGpuInfo gpu, in VulkanDeviceCriteria criteria) {
    import std.algorithm : min;

    bool found_compute_only_queue;
    bool found_graphics_present_queue;
    bool found_transfer_only_queue;

    // This algorithm starts from the end and works its way to the front. I.e.
    // if there are multiple graphics queues, the first one will be selected.

    foreach_reverse (index, ref queue; gpu.queue_families) {
        // If we require graphics queues and have yet to find one
        if (criteria.graphics_queue && gpu.graphics_family == uint.max) {
            if ((queue.queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0)
                gpu.graphics_family = cast(uint) index;
        }

        // If we require compute queues and haven't found a compute-only queue
        if (criteria.compute_queue && !(gpu.graphics_family != uint.max || found_compute_only_queue)) {
            if ((queue.queueFlags & VK_QUEUE_COMPUTE_BIT) != 0) {
                gpu.compute_family = cast(uint) index;

                found_compute_only_queue = queue.queueFlags == VK_QUEUE_COMPUTE_BIT
                    || queue.queueFlags == (VK_QUEUE_COMPUTE_BIT | VK_QUEUE_TRANSFER_BIT);
            }
        }

        // If we require transfer-only queues and haven't found any
        if (criteria.transfer_queue && !(gpu.transfer_family != uint.max || found_transfer_only_queue)) {
            if ((queue.queueFlags & VK_QUEUE_TRANSFER_BIT) != 0) {
                gpu.transfer_family = cast(uint) index;

                found_transfer_only_queue = (queue.queueFlags & (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT)) == 0;
            }
        }

        // If we require a display queue that is also a graphics queue
        if (criteria.display_target && !(gpu.present_family != uint.max && found_graphics_present_queue)) {
            VkBool32 can_present;
            vkGetPhysicalDeviceSurfaceSupportKHR(gpu.handle, cast(uint) index, cast(VkSurfaceKHR) criteria.display_target, &can_present);
            if (can_present == VK_TRUE) {
                gpu.present_family = cast(uint) index;
                found_graphics_present_queue = (queue.queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0;
            }
        }
    }

    if (criteria.transfer_queue && gpu.transfer_family == uint.max) {
        if (gpu.graphics_family != uint.max)
            gpu.transfer_family = gpu.graphics_family;
        else if (gpu.compute_family != uint.max)
            gpu.transfer_family = gpu.compute_family;
    } 

    const compute_ok = criteria.compute_queue == 0 || gpu.compute_family != uint.max;
    const graphics_ok = criteria.graphics_queue == 0 || gpu.graphics_family != uint.max;
    const transfer_ok = criteria.transfer_queue == 0 || gpu.transfer_family != uint.max;
    const present_ok = criteria.display_target is null || gpu.present_family != uint.max;
    return compute_ok && graphics_ok && transfer_ok && present_ok;
}

bool has_extensions(ref VulkanGpuInfo gpu, in VulkanDeviceCriteria criteria, ref TempAllocator mem) {
    import flare.core.hash: hash_of, Hash;

    const available_hashes = () nothrow {
        auto array = mem.alloc_array!Hash(gpu.available_extensions.length);
        foreach (i, ref slot; array) {
            import core.stdc.string : strlen;

            const length = strlen(&gpu.available_extensions[i].extensionName[0]);
            slot = hash_of(gpu.available_extensions[i].extensionName[0 .. length]);
        }
        return array;
    } ();

    const required_hashes = () nothrow {
        auto array = mem.alloc_array!Hash(criteria.required_extensions.length);
        foreach (i, ref slot; array)
            slot = hash_of(criteria.required_extensions[i]);
        return array;
    } ();

    auto num_matched = 0;
    foreach (req; required_hashes) {
    check:
        foreach (available; available_hashes) {
            if (available == req) {
                num_matched++;
                break check;
            }
        }
    }

    return criteria.required_extensions.length == num_matched;
}
