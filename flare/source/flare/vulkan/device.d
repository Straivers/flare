module flare.vulkan.device;

import flare.core.hash;
import flare.core.memory.api;
import flare.core.memory.temp;
import flare.vulkan.compat;
import flare.vulkan.h;
import flare.vulkan.instance;
import flare.vulkan.physical_device;
import flare.vulkan.surface;

immutable device_funcs = [
    "vkDestroyDevice",
    "vkGetDeviceQueue"
];

static foreach (func; device_funcs)
    mixin("auto " ~ func ~ "(Args...)(ref VulkanDevice device, Args args) { " ~ func ~ "(device.handle, args); }");

final class VulkanDevice {

    enum max_queues_per_family = 16;

public:
    const uint compute_family;
    const uint n_compute_queues;

    const uint graphics_family;
    const uint n_graphics_queues;

    const uint transfer_family;
    const uint n_transfer_queues;

    const uint present_family;
    const uint n_present_queues;

    ~this() {
        vkDestroyDevice(handle, null);
    }

    VkDevice handle() const {
        return cast(VkDevice) _handle;
    }

    VkQueue compute(uint index)
    in (index <= n_compute_queues) {
        return get_queue!"compute"(index);
    }

    VkQueue present(uint index)
    in (index <= n_present_queues) {
        return get_queue!"present"(index);
    }

    VkQueue graphics(uint index)
    in (index <= n_graphics_queues) {
        return get_queue!"graphics"(index);
    }

    VkQueue transfer(uint index)
    in (index <= n_transfer_queues) {
        return get_queue!"transfer"(index);
    }

private:
    const VkDevice _handle;

    static foreach (func; device_funcs)
        mixin("PFN_" ~ func ~ " " ~ func ~ ";");

    this(VkDevice dev, ref VulkanSelectedDevice device_info) {
        _handle = dev;

        n_compute_queues = device_info.num_compute_queues;
        compute_family = device_info.compute_queue_family_index;

        n_graphics_queues = device_info.num_graphics_queues;
        graphics_family = device_info.graphics_queue_family_index;

        n_transfer_queues = device_info.num_transfer_queues;
        transfer_family = device_info.transfer_queue_family_index;

        n_present_queues = device_info.num_present_queues;
        present_family = device_info.present_queue_family_index;

        load_device_functions();
    }

    void load_device_functions() {
        static foreach (func; device_funcs)
            mixin(func ~ " = cast(PFN_" ~ func ~ ") vkGetDeviceProcAddr(handle, \"" ~ func ~ "\");");
    }

    VkQueue get_queue(string name)(uint index) {
        VkQueue queue;
        mixin("vkGetDeviceQueue(handle, " ~ name ~ "_family, index, &queue);");
        return queue;
    }
}

VulkanDevice create_device(ref Vulkan instance, ref VulkanSelectedDevice physical_device) {
    auto tmp = scoped!TempAllocator(4.kib);
    auto queues = create_queue_create_infos(physical_device, tmp);

    VkPhysicalDeviceFeatures default_features;
    if (physical_device.enabled_features is null)
        physical_device.enabled_features = &default_features;

    auto extensions = to_cstr_array(physical_device.extensions, tmp);

    // dfmt off
    VkDeviceCreateInfo dci = {
        pQueueCreateInfos: queues.ptr,
        queueCreateInfoCount: cast(uint) queues.length,
        ppEnabledExtensionNames: extensions.ptr,
        enabledExtensionCount: cast(uint) extensions.length,
        pEnabledFeatures: physical_device.enabled_features,
    };
    // dfmt on

    VkDevice device;
    auto err = vkCreateDevice(physical_device.device, &dci, null, &device);

    if (err != VK_SUCCESS) {
        instance.log.fatal("Could not create Vulkan device: %s", err);
        assert(0, "Could not create Vulkan device");
    }

    instance.log.info("Vulkan device created with:\n\tExtensions:%-( %s%)\n\t%s compute queues  (id: %s)\n\t%s present queues  (id: %s)\n\t%s graphics queues (id: %s)\n\t%s transfer queues (id: %s)",
            physical_device.extensions,
            physical_device.num_compute_queues,
            physical_device.compute_queue_family_index,
            physical_device.num_graphics_queues,
            physical_device.present_queue_family_index,
            physical_device.num_transfer_queues,
            physical_device.graphics_queue_family_index,
            physical_device.num_present_queues,
            physical_device.transfer_queue_family_index,
    );

    return new VulkanDevice(device, physical_device);
}

private:

auto create_queue_create_infos(ref VulkanSelectedDevice device, TempAllocator mem) {
    import flare.core.array : Array;
    import std.algorithm : max;

    static get_queue(ref Array!VkDeviceQueueCreateInfo queues, uint new_index) {
        foreach (i, ref q; queues)
            if (q.queueFamilyIndex == new_index)
                return i;
        return size_t.max;
    }

    static insert(ref Array!VkDeviceQueueCreateInfo queues, uint q_index, uint q_count) {
        auto location = get_queue(queues, q_index);
        if (location == size_t.max) {
            VkDeviceQueueCreateInfo queue = {
                queueFamilyIndex: q_index,
                queueCount: q_count
            };

            queues ~= queue;
        }
        else {
            queues[location].queueCount = max(q_count, queues[location].queueCount);
        }
    }

    // Graphics + Compute + Transfer
    auto queues = Array!VkDeviceQueueCreateInfo(0, mem);

    with (device) {
        if (num_transfer_queues)
            insert(queues, transfer_queue_family_index, num_transfer_queues);

        if (num_graphics_queues)
            insert(queues, graphics_queue_family_index, num_graphics_queues);

        if (num_compute_queues)
            insert(queues, compute_queue_family_index, num_compute_queues);

        if (num_present_queues)
            insert(queues, present_queue_family_index, num_present_queues);
    }

    foreach (ref q; queues)
        q.pQueuePriorities = mem.alloc_arr!float(q.queueCount, 1.0).ptr;

    return queues;
}
