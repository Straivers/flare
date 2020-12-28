module flare.vulkan.memory;

import flare.vulkan.h;
import flare.vulkan.device;

struct Buffer {
    VkBuffer handle;

    VkMemoryRequirements requirements;
    alias requirements this;

    VkDeviceMemory backing_store;
    size_t offset;
}

Buffer create_buffer(VulkanDevice device, size_t size, VkBufferUsageFlags usage) {
    VkBufferCreateInfo bi = {
        size: size,
        usage: usage,
        sharingMode: VK_SHARING_MODE_EXCLUSIVE
    };

    Buffer buf;
    device.dispatch_table.CreateBuffer(bi, buf.handle);
    device.dispatch_table.GetBufferMemoryRequirements(buf.handle, buf.requirements);

    return buf;
}

void copy_host_visible_buffer(T)(VulkanDevice device, ref Buffer buffer, T[] data) {
    import std.traits: Unqual;
    assert(T.sizeof * data.length <= buffer.size);

    void* map_start;
    device.dispatch_table.MapMemory(buffer.backing_store, buffer.offset, buffer.size, 0, map_start);
    (cast(Unqual!T*) map_start)[0 .. data.length] = data;
    // device.dispatch_table.UnmapMemory(buffer.backing_store);

    VkMappedMemoryRange flush_range = {
        memory: buffer.backing_store,
        offset: buffer.offset,
        size: buffer.size
    };

    device.dispatch_table.FlushMappedMemoryRanges(flush_range);
}

void alloc_buffer(VulkanDevice device, ref Buffer buffer) {
    auto mem = device_alloc(device, VkMemoryRequirements(buffer.size, buffer.alignment, buffer.memoryTypeBits));
    device.dispatch_table.BindBufferMemory(buffer.handle, mem, 0);
    buffer.backing_store = mem;
    buffer.offset = 0;
}

VkDeviceMemory device_alloc(VulkanDevice device, VkMemoryRequirements requirements) {
    VkPhysicalDeviceMemoryProperties properties;
    vkGetPhysicalDeviceMemoryProperties(device.gpu.handle, &properties);

    foreach (i, type; properties.memoryTypes[0 .. properties.memoryTypeCount]) {
        if (requirements.memoryTypeBits & ( 1 << i) && (type.propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)) {
            VkMemoryAllocateInfo mai = {
                allocationSize: requirements.size,
                memoryTypeIndex: cast(uint) i
            };

            VkDeviceMemory memory;
            device.dispatch_table.AllocateMemory(mai, memory);
            return memory;
        }
    }

    assert(0, "Unable to allocate device memory");
}

void device_free(VulkanDevice device, VkDeviceMemory memory) {
    device.dispatch_table.FreeMemory(memory);
}
