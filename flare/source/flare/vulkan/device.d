module flare.vulkan.device;

import flare.core.memory.api;
import flare.core.memory.temp;
import flare.core.hash;
import flare.vulkan.instance;
import flare.vulkan.surface;
import flare.vulkan.h;

struct VulkanDeviceCriteria {
    /**
     The number of compute queues that a device must support. Preference is
     given to a device's compute-only queues if available.
     */
    uint num_compute_queues;

    /**
     The number of graphics queues that a device must support.
     */
    uint num_graphics_queues;

    /**
     The number of transfer queues that a device must support. Preference is
     given to a device's transfer-only queues if available.
     */
    uint num_transfer_queues;

    /**
     A surface that the device must be able to draw to, or null.
     */
    RenderSurface* display_target;

    /**
     Extensions that the device must support.
     */
    string[] required_extensions;

    /**
     Device features that must be supported, null for no additional features.
     Set feature flags only for features that you want.
     */
    VkPhysicalDeviceFeatures* required_features;
}

struct VulkanSelectedDevice {
    /**
     The index of an identified compute queue family. If this index
     is shared with another queue family, max_compute_queues represents the
     total number of queues supported by that queue family.
     */
    uint compute_queue_family_index = 0;

    /**
     The number of queues supported by the identified compute queue family. If
     this value is 0, the value of compute_queue_family_index should be ignored.
     Additionally, if compute_queue_family_index is the same as any other queue
     family, this value represents the total number of queues supported by that
     queue family.
     */
    uint max_compute_queues;

    /**
     The index of an identified graphics queue family. If this index
     is shared with another queue family, max_graphics_queues represents the
     total number of queues supported by that queue family.
     */
    uint graphics_queue_family_index = 0;

    /**
     The number of queues supported by the identified graphics queue family. If
     this value is 0, the value of graphics_queue_family_index should be
     ignored. Additionally, if graphics_queue_family_index is the same as any
     other queue family, this value represents the total number of queues
     supported by that queue family.
     */
    uint max_graphics_queues;

    /**
     The index of an identified transfer queue family. If this index
     is shared with another queue family, max_transfer_queues represents the
     total number of queues supported by that queue family.
     */
    uint transfer_queue_family_index = 0;

    /**
     The number of queues supported by the identified transfer queue family. If
     this value is 0, the value of transfer_queue_family_index should be
     ignored. Additionally, if transfer_queue_family_index is the same as any
     other queue family, this value represents the total number of queues
     supported by that queue family.
     */
    uint max_transfer_queues;

    /// The handle of the selected device.
    VkPhysicalDevice device;

    /// An array of extension names to be passed on to logical device creation.
    string[] extensions;

    /// A pointer to a VkPhysicalDeviceFeatures structure with features to be
    /// enabled during logical device creation.
    VkPhysicalDeviceFeatures* enabled_features;
}

VulkanSelectedDevice[] filter_physical_devices(ref Vulkan instance, ref VulkanDeviceCriteria criteria, Allocator mem) {
    bool check_queue(string name, VkQueueFlags flag)(ref VkQueueFamilyProperties queue) {
        import std.format: format;

        mixin("if (criteria.num_%1$s_queues) {
            if (queue.queueFlags == %2$s)
                return true;
            else if ((queue.queueFlags & %2$s) != 0)
                return true;
            return false;
        }

        return true;".format(name, flag));
    }

    /// Loop independent temp memory
    auto tmp = scoped!TempAllocator(4.kib);
    /// Per-loop temp memory
    auto device_tmp = scoped!TempAllocator(64.kib);
    /// Growing array of accepted devices, allocated from tmp
    VulkanSelectedDevice[] interim_result;

    auto devices = instance.get_physical_devices(tmp);
    foreach (device; devices) {
        VulkanSelectedDevice selected_device = {
            device: device,
            extensions: criteria.required_extensions
        };

        const queues_satisfied = () {
            auto queues = instance.get_queue_families(device, device_tmp);
            foreach (queue_index, ref queue; queues) {
                const compute_satisfied = check_queue!("compute", VK_QUEUE_COMPUTE_BIT)(queue);
                if (criteria.num_compute_queues && !selected_device.max_compute_queues && compute_satisfied) {
                    selected_device.compute_queue_family_index = cast(uint) queue_index;
                    selected_device.max_compute_queues = queue.queueCount;
                }

                const graphics_satisfied = check_queue!("graphics", VK_QUEUE_GRAPHICS_BIT)(queue);
                if (criteria.num_graphics_queues && !selected_device.max_graphics_queues && graphics_satisfied) {
                    selected_device.graphics_queue_family_index = cast(uint) queue_index;
                    selected_device.max_graphics_queues = queue.queueCount;
                }

                const transfer_satisfied = check_queue!("transfer", VK_QUEUE_TRANSFER_BIT)(queue);
                if (criteria.num_transfer_queues && !selected_device.max_transfer_queues && transfer_satisfied) {
                    selected_device.transfer_queue_family_index = cast(uint) queue_index;
                    selected_device.max_transfer_queues = queue.queueCount;
                }

                // const display_satisfied...

                if (compute_satisfied && graphics_satisfied && transfer_satisfied)
                    return true;
            }
            return false;
        } ();

        const extensions_satisfied = () {
            // Quick & dirty string to hash to reduce lookup time. A hash-table
            // would be better, but effort to implement a TempAllocator compatible
            // one is too complex right now.

            auto available_ext_hashes = () {
                auto extensions = instance.get_supported_extensions(device, device_tmp);
                auto array = device_tmp.alloc_arr!Hash(extensions.length);
                foreach (i, ref slot; array) {
                    import core.stdc.string: strlen;

                    const length = strlen(&extensions[i].extensionName[0]);
                    slot = hash_of(extensions[i].extensionName[0 .. length]);
                }
                return array;
            } ();

            auto required_ext_hashes = () {
                auto array = device_tmp.alloc_arr!Hash(criteria.required_extensions.length);
                foreach (i, ref slot; array)
                    slot = hash_of(criteria.required_extensions[i]);
                return array;
            } ();

            auto num_matched = 0;
            foreach (required; required_ext_hashes) {
                check: foreach (available; available_ext_hashes) {
                    if (available == required) {
                        num_matched++;
                        break check;
                    }
                }
            }

            return criteria.required_extensions.length == num_matched;
        } ();

        const features_satisfied = () {
            return true;
        } ();

        // If all satisfied, add device to list
        if (queues_satisfied && extensions_satisfied && features_satisfied) {
            auto arr = tmp.alloc_arr!VulkanSelectedDevice(interim_result.length + 1);
            assert(arr);

            arr[0 .. interim_result.length] = interim_result;
            arr[$ - 1] = selected_device;
            interim_result = arr;
        }

        device_tmp.reset();
    }

    auto result = mem.alloc_arr!VulkanSelectedDevice(interim_result.length);
    result[] = interim_result;
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

VkDevice create_logical_device(ref Vulkan instance, VkPhysicalDevice physical_device, VkDeviceQueueCreateInfo[] queues, ref VkPhysicalDeviceFeatures features) {
    VkDeviceCreateInfo dci = {
        pQueueCreateInfos: queues.ptr,
        queueCreateInfoCount: cast(uint) queues.length,
        pEnabledFeatures: &features
    };

    VkDevice device;
    const err = vkCreateDevice(physical_device, &dci, null, &device);
    if (err == VK_SUCCESS)
        return device;

    instance.log.fatal("Could not create Vulkan device: %s", err);
    assert(0, "Coult not create Vulkan device.");
}
