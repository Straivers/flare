module flare.vulkan.devices;

import flare.vulkan.api;
import flare.core.memory.static_allocator;

@trusted PhysicalDevice[] load_physical_devices(ref Vulkan vk, PhysicalDevice[] buffer) {
    uint count;
    auto err = vkEnumeratePhysicalDevices(vk.handle, &count, null);
    if (err >= VK_SUCCESS) {
        if (count > buffer.length)
            count = cast(uint) buffer.length;

        auto mem = scoped_mem!(PhysicalDevice.sizeof * 32);
        auto tmp_buff = mem.alloc_array!VkPhysicalDevice(count);
        err = vkEnumeratePhysicalDevices(vk.handle, &count, cast(VkPhysicalDevice*) &tmp_buff[0]);
        if (err >= VK_SUCCESS) {
            foreach (i, dev; tmp_buff[0 .. count])
                buffer[i] = PhysicalDevice(vk, tmp_buff[i]);

            auto devices = buffer[0 .. count];
            vk.log.trace("Identified %s Graphics Device%s", count, count > 1 ? "s" : "");
            return devices;
        }
    }

    vk.log.fatal("Unable to enumerate physical devices.");
    assert(0, "Unable to enumerate physical devices.");
}

struct QueueFamilyProperties {
    uint index;
    VkQueueFamilyProperties properties;
    alias properties this;
}

@safe @nogc bool has_flags(VkQueueFlagBits bits)(in VkQueueFamilyProperties props) pure nothrow {
    return (props.queueFlags & bits) != 0;
}

struct PhysicalDevice {
    @safe nothrow:

    VkPhysicalDevice handle() pure {{
        return _device;
    }}

    @trusted @nogc bool can_render_to(RenderSurface* surface, uint with_queue_family) {
        VkBool32 out_;
        if (!vkGetPhysicalDeviceSurfaceSupportKHR(_device, with_queue_family, surface.handle, &out_))
            return out_ != 0;

        assert(false);
    }

    auto filter_renderable_queues_to(RenderSurface* surface, in QueueFamilyProperties[] families) {
        struct Range {
            @safe @nogc nothrow:
            uint index() const { return _index; }

            bool empty() const { return _index == _families.length; }

            ref const(QueueFamilyProperties) front() const {
                return _families[_index];
            }

            void popFront() nothrow {
                _index++;
                advance();
            }

        private:
            void advance() nothrow {
                while (!empty && !_device.can_render_to(_surface, _index))
                    _index++;
            }

            RenderSurface* _surface;
            PhysicalDevice* _device;
            const QueueFamilyProperties[] _families;
            uint _index;
        }

        auto ret = Range(surface, &this, families, 0);
        ret.advance();
        return ret;
    }

    @trusted const(QueueFamilyProperties[]) load_queue_families(QueueFamilyProperties[] buffer) {
        uint count;
        vkGetPhysicalDeviceQueueFamilyProperties(_device, &count, null);

        auto mem = scoped_mem!(VkQueueFamilyProperties.sizeof * 32);
        auto tmp = mem.alloc_array!VkQueueFamilyProperties(count);
        vkGetPhysicalDeviceQueueFamilyProperties(_device, &count, &tmp[0]);

        foreach (i, ref t; tmp[0 .. count])
            buffer[i] = QueueFamilyProperties(cast(uint) i, t);

        return buffer[0 .. count];
    }

    @trusted LogicalDevice init_logical_device(VkDeviceQueueCreateInfo[] queues, ref VkPhysicalDeviceFeatures features) {
        VkDeviceCreateInfo dci = {
            pQueueCreateInfos: queues.ptr,
            queueCreateInfoCount: cast(uint) queues.length,
            pEnabledFeatures : &features
        };

        VkDevice device;
        auto err = vkCreateDevice(_device, &dci, null, &device);
        if (err != VK_SUCCESS) {
            _vulkan.log.fatal("Failed to initialize graphics device. Error: %s", err);
            assert(false, "Failed to initialize graphics device.");
        }

        return LogicalDevice(_vulkan, device);
    }

private:
    @trusted this(ref Vulkan vulkan, VkPhysicalDevice device) {
        _vulkan = &vulkan;
        _device = device;
    }

    Vulkan* _vulkan;
    VkPhysicalDevice _device;
}

struct LogicalDevice {
    Vulkan* _vulkan;
    VkDevice _device;
}
