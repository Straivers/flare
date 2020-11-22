module flare.vulkan.physical_device;

import flare.core.array;
import flare.core.hash;
import flare.core.memory.temp;
import flare.vulkan.h;
import flare.vulkan.instance;
import flare.vulkan.surface;

enum num_presentation_queues_per_device = 1;

struct VulkanDeviceCriteria {
    /**
     The number of compute queues that a device must support. A
     compute-specialized queue will be selected preferentially.

     Note: According to the spec, a compute-specialized queue is implicitly
     capable of transfer as well.
     */
    uint num_compute_queues;

    /**
     The number of graphics queues that a device must support.

     Note: According to the spec, a graphics-specialized queue is implicitly
     capable of transfer as well.
     */
    uint num_graphics_queues;

    /**
     The number of transfer-only queues that a device must support.
     */
    uint num_transfer_queues;

    /**
     A surface that the device must be able to draw to, or null. When
     identifying presentation queues, a queue that also supports graphics
     operations will be selected preferentially.
     */
    RenderSurface display_target;

    /**
     Extensions that the device must support.
     */
    const(string)[] required_extensions;

    /**
     Device features that must be supported, null for no additional features.
     Set feature flags only for features that you want.
     */
    VkPhysicalDeviceFeatures* required_features;
}

struct VulkanSelectedDevice {
    /**
     The index of an identified compute queue family.
     */
    uint compute_queue_family_index = 0;

    /**
     The number of compute queues that were requested, or the number of queues
     that are supported. Whichever is smaller. If 0, the value of
     compute_queue_family_index should be ignored.
     */
    uint num_compute_queues;

    /**
     The index of an identified graphics queue family.
     */
    uint graphics_queue_family_index = 0;

    /**
     The number of graphics queues that were requested, or the number of queues
     that are supported. Whichever is smaller. If 0, the value of
     graphics_queue_family_index should be ignored.
     */
    uint num_graphics_queues;

    /**
     The index of an identified transfer queue family.
     */
    uint transfer_queue_family_index = 0;

    /**
     The number of transfer queues that were requested, or the number of queues
     that are supported. Whichever is smaller. If 0, the value of
     transfer_queue_family_index should be ignored.
     */
    uint num_transfer_queues;

    /**
     The index of a queue family that can present to a display.
     */
    uint present_queue_family_index = 0;

    /**
     The number of presentation queues to create. Must be either 0 or 1.
     */
    uint num_present_queues;

    /**
     The handle of the selected device.
     */
    VkPhysicalDevice device;

    /**
     An array of extension names to be passed on to logical device creation.
     */
    const(string)[] extensions;

    /**
     A pointer to a VkPhysicalDeviceFeatures structure with features to be
     enabled during logical device creation.
     */
    VkPhysicalDeviceFeatures* enabled_features;
}

VulkanSelectedDevice[] filter_physical_devices(ref Vulkan instance, in VulkanDeviceCriteria criteria, Allocator mem) {
    /// Loop independent temp memory
    auto tmp = scoped!TempAllocator(4.kib);
    /// Per-loop temp memory
    auto device_tmp = scoped!TempAllocator(64.kib);
    /// Growing array of accepted devices, allocated from tmp
    auto interim_result = Array!VulkanSelectedDevice(0, tmp);

    auto devices = instance.get_physical_devices(tmp);
    foreach (device; devices) {
        // dfmt off
        VulkanSelectedDevice selected_device = {
            device: device,
            extensions: criteria.required_extensions
        };
        // dfmt on

        const queues_satisfied = select_queue_families(criteria, instance.get_queue_families(device, device_tmp), selected_device);

        const extensions_satisfied = has_required_extensions(criteria.required_extensions, instance.get_supported_extensions(device, device_tmp));

        const features_satisfied = () { return true; }();

        // If all satisfied, add device to list
        if (queues_satisfied && extensions_satisfied && features_satisfied)
            interim_result ~= selected_device;

        device_tmp.reset();
    }

    auto result = mem.alloc_arr!VulkanSelectedDevice(interim_result.length);
    result[] = interim_result.array;
    return result;
}

VkPhysicalDevice[] get_physical_devices(ref Vulkan instance, Allocator mem) {
    uint count;
    const r1 = vkEnumeratePhysicalDevices(instance.handle, &count, null);
    if (r1 != VK_SUCCESS) {
        instance.log.fatal("Call to vkEnumeratePhysicalDevices failed: %s", r1);
        return [];
    }

    auto devices = mem.alloc_arr!VkPhysicalDevice(count);
    if (!devices) {
        instance.log.fatal("Out of Temporary Memory!");
        return [];
    }

    const r2 = vkEnumeratePhysicalDevices(instance.handle, &count, devices.ptr);
    if (r2 != VK_SUCCESS) {
        instance.log.fatal("Call to vkEnumeratePhysicalDevices failed: %s", r2);
        return [];
    }

    return devices;
}

VkQueueFamilyProperties[] get_queue_families(ref Vulkan instance, VkPhysicalDevice device, Allocator mem) {
    uint count;
    vkGetPhysicalDeviceQueueFamilyProperties(device, &count, null);

    auto array = mem.alloc_arr!VkQueueFamilyProperties(count);
    if (!array) {
        instance.log.fatal("Out of Temporary Memory!");
        return [];
    }

    vkGetPhysicalDeviceQueueFamilyProperties(device, &count, array.ptr);
    return array;
}

VkExtensionProperties[] get_supported_extensions(ref Vulkan instance, VkPhysicalDevice physical_device, Allocator mem) {
    uint count;
    const r1 = vkEnumerateDeviceExtensionProperties(physical_device, null, &count, null);
    if (r1 != VK_SUCCESS) {
        instance.log.fatal("Call to vkEnumerateDeviceExtensionProperties failed: %s", r1);
        return [];
    }

    auto extensions = mem.alloc_arr!VkExtensionProperties(count);
    if (!extensions) {
        instance.log.fatal("Out of Temporary Memory!");
        return [];
    }

    const r2 = vkEnumerateDeviceExtensionProperties(physical_device, null, &count, extensions.ptr);
    if (r2 != VK_SUCCESS) {
        instance.log.fatal("Call to vkEnumerateDeviceExtensionProperties failed: %s", r2);
        return [];
    }

    return extensions;
}

private:

bool select_queue_families(in VulkanDeviceCriteria criteria, in VkQueueFamilyProperties[] queues, ref VulkanSelectedDevice device) {
    import std.algorithm : min;

    bool found_compute_only_queue;
    bool found_graphics_present_queue;

    // This algorithm starts from the end and works its way to the front. I.e.
    // if there are multiple graphics queues, the first one will be selected.

    foreach_reverse (index, ref queue; queues) {
        // If we require graphics queues and have yet to find one
        if (criteria.num_graphics_queues && !device.num_graphics_queues) {
            if ((queue.queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0) {
                device.graphics_queue_family_index = cast(uint) index;
                device.num_graphics_queues = min(queue.queueCount, criteria.num_graphics_queues);
            }
        }

        // If we require compute queues and haven't found a compute-only queue
        if (criteria.num_compute_queues && !(device.num_compute_queues && found_compute_only_queue)) {
            if ((queue.queueFlags & VK_QUEUE_COMPUTE_BIT) != 0) {
                device.compute_queue_family_index = cast(uint) index;
                device.num_compute_queues = min(queue.queueCount, criteria.num_compute_queues);

                found_compute_only_queue = queue.queueFlags == VK_QUEUE_COMPUTE_BIT
                    || queue.queueFlags == (VK_QUEUE_COMPUTE_BIT | VK_QUEUE_TRANSFER_BIT);
            }
        }

        // If we require transfer-only queues and haven't found any
        if (criteria.num_transfer_queues && !device.num_transfer_queues) {
            if (queue.queueFlags == VK_QUEUE_TRANSFER_BIT) {
                device.transfer_queue_family_index = cast(uint) index;
                device.num_transfer_queues = min(queue.queueCount, criteria.num_transfer_queues);
            }
        }

        if (criteria.display_target && !(device.num_present_queues && found_graphics_present_queue)) {
            const is_also_graphics = (queue.queueFlags && VK_QUEUE_GRAPHICS_BIT) != 0;
            VkBool32 can_present;
            vkGetPhysicalDeviceSurfaceSupportKHR(device.device, cast(uint) index, criteria.display_target.handle, &can_present);

            device.num_present_queues = num_presentation_queues_per_device;
            found_graphics_present_queue = device.num_present_queues && is_also_graphics;
        }
    }

    const compute_ok = criteria.num_compute_queues == 0 || device.num_compute_queues;
    const graphics_ok = criteria.num_graphics_queues == 0 || device.num_graphics_queues;
    const transfer_ok = criteria.num_transfer_queues == 0 || device.num_transfer_queues;
    return compute_ok && graphics_ok && transfer_ok;
}

bool has_required_extensions(const(string)[] required_extensions, VkExtensionProperties[] available_extensions) {
    auto tmp = scoped!TempAllocator(4.kib);

    const available_ext_hashes = () {
        auto array = tmp.alloc_arr!Hash(available_extensions.length);
        foreach (i, ref slot; array) {
            import core.stdc.string : strlen;

            const length = strlen(&available_extensions[i].extensionName[0]);
            slot = hash_of(available_extensions[i].extensionName[0 .. length]);
        }
        return array;
    }();

    const required_ext_hashes = () {
        auto array = tmp.alloc_arr!Hash(required_extensions.length);
        foreach (i, ref slot; array)
            slot = hash_of(required_extensions[i]);
        return array;
    }();

    auto num_matched = 0;
    foreach (req; required_ext_hashes) {
    check:
        foreach (available; available_ext_hashes) {
            if (available == req) {
                num_matched++;
                break check;
            }
        }
    }

    return required_extensions.length == num_matched;
}
