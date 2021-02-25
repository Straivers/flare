module flare.vulkan.gpu;

import flare.core.memory;
import flare.vulkan.context;
import flare.vulkan.h;

nothrow:

struct VulkanGpuInfo {
    VkPhysicalDevice handle;
    const(string)[] extensions;

    QueueFamilies queue_families;
    alias queue_families this;

    VkPhysicalDeviceProperties properties;
}

struct QueueFamilies {
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

bool select_gpu(VulkanContext ctx, ref VulkanDeviceCriteria criteria, out VulkanGpuInfo result) {
    uint n_devices;
    vkEnumeratePhysicalDevices(ctx.instance, &n_devices, null);
    auto devices = ctx.memory.make_array!VkPhysicalDevice(n_devices);
    scope (exit) ctx.memory.dispose(devices);
    vkEnumeratePhysicalDevices(ctx.instance, &n_devices, devices.ptr);

    foreach (device; devices) {
        auto mem = scoped_arena(ctx.memory, 64.kib);

        QueueFamilies selection;
        const queues_ok = select_queue_families(device, mem, criteria, selection);
        const extensions_ok = has_extensions(device, mem, criteria);

        if (queues_ok && extensions_ok) {
            auto extensions = ctx.memory.make_array!string(criteria.required_extensions.length);
            extensions[] = criteria.required_extensions;

            result = VulkanGpuInfo(
                device,
                extensions,
                selection
            );

            vkGetPhysicalDeviceProperties(device, &result.properties);

            return true;
        }
    }

    return false;
}

private:

bool select_queue_families(VkPhysicalDevice device, ref ScopedArena mem, in VulkanDeviceCriteria criteria, out QueueFamilies selection) {
    import std.algorithm : min;

    auto queue_families = () {
        uint count;
        vkGetPhysicalDeviceQueueFamilyProperties(device, &count, null);
        auto array = mem.make_array!VkQueueFamilyProperties(count);
        vkGetPhysicalDeviceQueueFamilyProperties(device, &count, array.ptr);
        return array;
    } ();

    bool found_compute_only_queue;
    bool found_graphics_present_queue;
    bool found_transfer_only_queue;

    // This algorithm starts from the end and works its way to the front. I.e.
    // if there are multiple graphics queues, the first one will be selected.

    foreach_reverse (index, ref queue; queue_families) {
        // If we require graphics queues and have yet to find one
        if (criteria.graphics_queue && selection.graphics_family == uint.max) {
            if ((queue.queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0)
                selection.graphics_family = cast(uint) index;
        }

        // If we require compute queues and haven't found a compute-only queue
        if (criteria.compute_queue && !(selection.graphics_family != uint.max || found_compute_only_queue)) {
            if ((queue.queueFlags & VK_QUEUE_COMPUTE_BIT) != 0) {
                selection.compute_family = cast(uint) index;

                found_compute_only_queue = queue.queueFlags == VK_QUEUE_COMPUTE_BIT
                    || queue.queueFlags == (VK_QUEUE_COMPUTE_BIT | VK_QUEUE_TRANSFER_BIT);
            }
        }

        // If we require transfer-only queues and haven't found any
        if (criteria.transfer_queue && !(selection.transfer_family != uint.max || found_transfer_only_queue)) {
            if ((queue.queueFlags & VK_QUEUE_TRANSFER_BIT) != 0) {
                selection.transfer_family = cast(uint) index;

                found_transfer_only_queue = (queue.queueFlags & (VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT)) == 0;
            }
        }

        // If we require a display queue that is also a graphics queue
        if (criteria.display_target && !(selection.present_family != uint.max && found_graphics_present_queue)) {
            VkBool32 can_present;
            vkGetPhysicalDeviceSurfaceSupportKHR(device, cast(uint) index, cast(VkSurfaceKHR) criteria.display_target, &can_present);
            if (can_present == VK_TRUE) {
                selection.present_family = cast(uint) index;
                found_graphics_present_queue = (queue.queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0;
            }
        }
    }

    if (criteria.transfer_queue && selection.transfer_family == uint.max) {
        if (selection.graphics_family != uint.max)
            selection.transfer_family = selection.graphics_family;
        else if (selection.compute_family != uint.max)
            selection.transfer_family = selection.compute_family;
    }

    const compute_ok = criteria.compute_queue == 0 || selection.compute_family != uint.max;
    const graphics_ok = criteria.graphics_queue == 0 || selection.graphics_family != uint.max;
    const transfer_ok = criteria.transfer_queue == 0 || selection.transfer_family != uint.max;
    const present_ok = criteria.display_target is null || selection.present_family != uint.max;
    return compute_ok && graphics_ok && transfer_ok && present_ok;
}

bool has_extensions(VkPhysicalDevice device, ref ScopedArena mem, in VulkanDeviceCriteria criteria) {
    import flare.core.hash: hash_of, Hash;

    const available_extensions = () {
        uint count;
        vkEnumerateDeviceExtensionProperties(device, null, &count, null);
        auto array = mem.make_array!VkExtensionProperties(count);
        vkEnumerateDeviceExtensionProperties(device, null, &count, array.ptr);
        return array;
    } ();

    const available_hashes = () nothrow {
        auto array = mem.make_array!Hash(available_extensions.length);
        foreach (i, ref slot; array) {
            import core.stdc.string : strlen;

            const length = strlen(&available_extensions[i].extensionName[0]);
            slot = hash_of(available_extensions[i].extensionName[0 .. length]);
        }
        return array;
    } ();

    const required_hashes = () nothrow {
        auto array = mem.make_array!Hash(criteria.required_extensions.length);
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
