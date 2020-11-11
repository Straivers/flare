module flare.vulkan.devices;

import flare.vulkan.api;

/*
@trusted PhysicalDevice[] load_physical_devices(ref Vulkan vk) {
    uint count;
    auto err = vkEnumeratePhysicalDevices(vk.handle, &count, null);
    if (err >= VK_SUCCESS) {
        auto result = vk.tmp_array!PhysicalDevice(count);

        auto array = vk.tmp_array!VkPhysicalDevice(count);
        err = vkEnumeratePhysicalDevices(vk.handle, &count, cast(VkPhysicalDevice*) &array[0]);

        if (err >= VK_SUCCESS) {
            foreach (i, dev; array[0 .. count])
                result[i] = PhysicalDevice(vk, array[i]);

            vk.tmp_free(array);
            vk.log.trace("Identified %s Graphics Device%s", count, count > 1 ? "s" : "");
            return result;
        }
    }

    vk.log.fatal("Unable to enumerate physical devices.");
    assert(0, "Unable to enumerate physical devices.");
}
*/
// struct QueueFamilyProperties {
//     uint index;
//     VkQueueFamilyProperties properties;
//     alias properties this;
// }
/*
@safe @nogc bool has_flags(VkQueueFlagBits bits)(in VkQueueFamilyProperties props) pure nothrow {
    return (props.queueFlags & bits) != 0;
}
*/
// struct PhysicalDevice {
//     VkPhysicalDevice handle() {
//         return _device;
//     }

//     @trusted @nogc bool can_render_to(RenderSurface* surface, uint with_queue_family) {
//         VkBool32 out_;
//         if (!vkGetPhysicalDeviceSurfaceSupportKHR(_device, with_queue_family, surface.handle, &out_))
//             return out_ != 0;

//         assert(false);
//     }

//     auto filter_renderable_queues_to(RenderSurface* surface, in QueueFamilyProperties[] families) {
//         struct Range {
//             @safe @nogc nothrow:
//             uint index() const { return _index; }

//             bool empty() const { return _index == _families.length; }

//             ref const(QueueFamilyProperties) front() const {
//                 return _families[_index];
//             }

//             void popFront() nothrow {
//                 _index++;
//                 advance();
//             }

//         private:
//             void advance() nothrow {
//                 while (!empty && !_device.can_render_to(_surface, _index))
//                     _index++;
//             }

//             RenderSurface* _surface;
//             PhysicalDevice* _device;
//             const QueueFamilyProperties[] _families;
//             uint _index;
//         }

//         auto ret = Range(surface, &this, families, 0);
//         ret.advance();
//         return ret;
//     }

    // @trusted const(QueueFamilyProperties[]) load_queue_families(QueueFamilyProperties[] buffer) {
    //     uint count;
    //     _vk.GetPhysicalDeviceQueueFamilyProperties(_device, &count, null);

        // auto array = _vk.tmp_array();
        // _vk.GetPhysicalDeviceQueueFamilyProperties(_device, &count, &tmp[0]);

        // foreach (i, ref t; tmp[0 .. count])
        //     buffer[i] = QueueFamilyProperties(cast(uint) i, t);

    //     return buffer[0 .. count];
    // }

//     bool supports_listed_extensions(in string[] names) {
//         // load supported extensions
//         // for each extension, put it in a 1-way bloom filter, and store its hash
//         // for each desired extension, check its hash against the bloom filter
//             // mark each extension that may be in the set
//             // return false if any extension is found to not be in the set
//             // for each marked extension, go over the hashes and compare them, if one cannot be found, return false
//         // return true, having passed all the tests

//         assert(0, "Not implemented");
//     }

//     @trusted LogicalDevice init_logical_device(VkDeviceQueueCreateInfo[] queues, ref VkPhysicalDeviceFeatures features) {
//         VkDeviceCreateInfo dci = {
//             pQueueCreateInfos: queues.ptr,
//             queueCreateInfoCount: cast(uint) queues.length,
//             pEnabledFeatures : &features
//         };

//         VkDevice device;
//         auto err = vkCreateDevice(_device, &dci, null, &device);
//         if (err != VK_SUCCESS) {
//             _vulkan.log.fatal("Failed to initialize graphics device. Error: %s", err);
//             assert(false, "Failed to initialize graphics device.");
//         }

//         return LogicalDevice(_vulkan, device);
//     }

// package:
//     this(ref Vulkan vulkan, VkPhysicalDevice device) {
//         _vk = &vulkan;
//         _device = device;
//     }

// private:
//     Vulkan* _vk;
//     VkPhysicalDevice _device;
// }

// struct LogicalDevice {
//     @safe nothrow:

//     @disable this(this);

//     @trusted ~this() {
//         vkDestroyDevice(_device, null);
//     }

//     VkDevice handle() {
//         return _device;
//     }

//     @trusted VkQueue get_queue(uint index, uint family) {
//         VkQueue queue;
//         vkGetDeviceQueue(_device, family, index, &queue);
//         return queue;
//     }

// private:
//     Vulkan* _vulkan;
//     VkDevice _device;
// }
