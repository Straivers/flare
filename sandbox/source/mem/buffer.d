module mem.buffer;

import flare.vulkan;
import mem.device;

enum BufferType : ubyte {
    Unknown,
    Index,
    Vertex,
    Uniform,
}

VkBufferUsageFlags get_usage_flags(BufferType type, Transferability transferable) {
    static immutable type_conv = [
        /* Unknown  */ 0,
        /* Index    */ VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        /* Vertex   */ VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        /* Uniform  */ VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
    ];

    static immutable transferability_conv = [
        /* None     */ 0,
        /* Send     */ VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        /* Receive  */ VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        /* Both     */ VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
    ];

    return type_conv[type] | transferability_conv[transferable];
}

struct DeviceBufferSlice {
    mem.device.DeviceMemory allocation;
    VkBuffer handle;
    uint offset;
    uint size;

    // dfmt off
    DeviceBufferSlice opIndex() { return this; }
    uint opDollar() { return size; }
    // dfmt on

    DeviceBufferSlice opSlice(uint lo, uint hi) {
        assert(handle && lo < hi && offset + hi <= size);
        return DeviceBufferSlice(allocation, handle, offset + lo, hi - lo);
    }
}

struct BufferAllocInfo {
    uint size;
    BufferType type;
    Transferability transferable;

    void to_vk_create_info(out VkBufferCreateInfo ci) {
        ci.size = size;
        ci.usage = get_usage_flags(type, transferable);
        ci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    }
}

uint get_type_index_for_buffer_create_info(DeviceMemoryAllocator allocator, DeviceHeap heap, BufferAllocInfo alloc_i) {
    VkBufferCreateInfo buffer_ci;
    alloc_i.to_vk_create_info(buffer_ci);

    VkBuffer sample_buffer;
    allocator.device.dispatch_table.CreateBuffer(buffer_ci, sample_buffer);
    scope (exit) allocator.device.dispatch_table.DestroyBuffer(sample_buffer);

    VkMemoryRequirements reqs;
    allocator.device.dispatch_table.GetBufferMemoryRequirements(sample_buffer, reqs);

    return get_memory_type_index(allocator.device, heap, reqs.memoryTypeBits);
}

DeviceBufferSlice allocate_buffer(DeviceMemoryAllocator allocator, BufferAllocInfo alloc_i) {
    VkBufferCreateInfo buffer_ci;
    alloc_i.to_vk_create_info(buffer_ci);

    return allocate_buffer(allocator, buffer_ci);
}

DeviceBufferSlice allocate_buffer(DeviceMemoryAllocator allocator, ref VkBufferCreateInfo buffer_ci) {
    DeviceBufferSlice buffer;
    allocator.device.dispatch_table.CreateBuffer(buffer_ci, buffer.handle);

    VkMemoryRequirements reqs;
    allocator.device.dispatch_table.GetBufferMemoryRequirements(buffer.handle, reqs);
    allocator.allocate(reqs, true, buffer.allocation);

    allocator.device.dispatch_table.BindBufferMemory(buffer.handle, buffer.allocation.handle, buffer.allocation.offset);

    return buffer;
}

bool allocate_buffers(DeviceMemoryAllocator allocator, BufferAllocInfo[] allocs, out DeviceBufferSlice buffer, DeviceBufferSlice[] result) {
    import flare.core.math.util : round_to_next;

    assert(result.length >= allocs.length);

    VkDeviceSize total_size;
    VkBufferUsageFlags shared_flags;

    foreach (i, ref a; allocs) {
        result.size = a.size;
        result.offset = total_size;

        total_size += a.size;
        // TODO: Is using nonCoherentAtomSize for alignment correct?
        round_to_next(total_size, allocator.device.gpu.properties.limits.nonCoherentAtomSize);

        shared_flags |= get_usage_flags(a.type, a.transferable);
    }

    VkBufferCreateInfo big_buffer_ci = {
        size: total_size,
        usage: shared_flags,
        sharingMode: VK_SHARING_MODE_EXCLUSIVE
    };

    buffer = allocate_buffer(allocator, big_buffer_ci);

    // ROBUSTNESS: Should the allocation be retried with smaller allocations on
    // failure?

    return true;
}
