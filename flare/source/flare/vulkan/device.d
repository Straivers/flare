module flare.vulkan.device;

import flare.core.memory.api;
import flare.vulkan.instance;
import flare.vulkan.surface;
import flare.vulkan.h;

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