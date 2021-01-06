module flare.vulkan.memory;

import flare.core.memory.api: Allocator;
import flare.core.logger: Logger;
import flare.core.memory.object_pool;
import flare.vulkan.h;
import flare.vulkan.dispatch: DispatchTable;

enum MemUsage {
    invalid = 0,
    write_static = 2,
    write_dynamic = 1,
    transfer = 3,
    readback = 4,
}

enum ResourceType {
    StagingSource,
    VertexBuffer,
}

alias DeviceAlloc = Handle;

struct DeviceMemory {
    this(DispatchTable* device, VkPhysicalDevice gpu, Allocator allocator, ref Logger logger) {
        _mem = allocator;
        _vk = device;
        _log = Logger(logger.log_level, &logger);
        _allocations = ObjectPool!(Allocation, 64)(Allocation.init);

        vkGetPhysicalDeviceMemoryProperties(gpu, &_memory_properties);
    }

    @disable this(this);

    VkBuffer get_buffer(DeviceAlloc alloc) {
        if (auto allocation = _allocations.get(alloc)) {
            if (allocation.type == Allocation.Type.Buffer)
                return allocation.buffer_handle;
        }

        return VK_NULL_HANDLE;
    }

    DeviceAlloc alloc(size_t size, ResourceType resource_type, MemUsage usage) {
        Allocation.Type object_type;

        const usage_flags = () {
            switch (resource_type) with (ResourceType) {
            case StagingSource:
                object_type = Allocation.Type.Buffer;
                return VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
            
            case VertexBuffer:
                object_type = Allocation.Type.Buffer;
                return VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
            
            default:
                assert(0, "Not implemented");
            }
        } ();

        if (object_type == Allocation.Type.Buffer) {
            VkBufferCreateInfo buffer_ci = {
                size: size,
                usage: usage_flags,
                sharingMode: VK_SHARING_MODE_EXCLUSIVE,
            };

            VkBuffer buffer;
            _vk.CreateBuffer(buffer_ci, buffer);

            _log.trace("Created %s-byte %s buffer (handle %s) with %b flags.", size, usage, buffer, usage_flags);

            if (auto handle = alloc_buffer_memory(buffer, size, usage))
                return handle;

            _vk.DestroyBuffer(buffer);
            return Handle();
        }
        assert(0, "Alternate memory types not implemented yet.");
    }

    DeviceAlloc alloc_buffer_memory(VkBuffer buffer, size_t size, MemUsage usage) {
        VkMemoryRequirements requirements;
        _vk.GetBufferMemoryRequirements(buffer, requirements);

        const memory_type = _get_memory_type_idx(usage, requirements.memoryTypeBits);

        if (memory_type >= 0) {
            VkMemoryAllocateInfo alloc_i = {
                allocationSize: requirements.size,
                memoryTypeIndex: cast(uint) memory_type
            };

            VkDeviceMemory memory;
            _vk.AllocateMemory(alloc_i, memory);
            _vk.BindBufferMemory(buffer, memory, 0);

            auto slot = _allocations.alloc();
            *slot.content = Allocation(memory, 0, size, requirements.size, buffer);

            _log.trace("%s bytes allocated from memory pool %s for %s byte buffer.", requirements.size, memory_type, size);

            return slot.handle;
        }

        return Handle();
    }

    void destroy(DeviceAlloc handle) {
        if (auto allocation = _allocations.get(handle)) {
            switch (allocation.type) with (Allocation.Type) {
            case Buffer:
                _log.trace("Destroying buffer %s", allocation.buffer_handle);
                _vk.DestroyBuffer(allocation.buffer_handle);
                break;

            case Image:
                // _vk.DestroyImage(allocation.image_handle);
                // break;

            default:
                assert(0, "Unrecognized memory resource type.");
            }

            _vk.FreeMemory(allocation.handle);
        }
    }

    T[] map(T)(DeviceAlloc alloc) {
        import std.traits: Unqual;

        if (auto slot = _allocations.get(alloc)) {
            void* ptr;
            _vk.MapMemory(slot.handle, 0, slot.size, 0, ptr);
            return cast(T[]) ptr[0 .. slot.size - (slot.size % T.sizeof)];
        }
        return [];
    }

    void unmap(DeviceAlloc alloc) {
        if (auto slot = _allocations.get(alloc)) {
            VkMappedMemoryRange flush_range = {
                memory: slot.handle,
                offset: 0,
                size: slot.size
            };

            _vk.FlushMappedMemoryRanges(flush_range);
            _vk.UnmapMemory(slot.handle);
        }
    }

private:
    size_t _get_memory_type_idx(MemUsage type, uint memory_type_bits) {
        int find(VkMemoryPropertyFlags required_properties) {
            foreach (i, memory_type; _memory_properties.memoryTypes[0 .. _memory_properties.memoryTypeCount]) {
                const type_bits = (1 << i);
                const is_correct_type = (memory_type_bits & type_bits) != 0;
                const has_properties = (memory_type.propertyFlags & required_properties) == required_properties;

                if (is_correct_type & has_properties)
                    return cast(int) i;
            }
            return -1;
        }

        VkMemoryPropertyFlags required, optional;
        switch (type) with (MemUsage) {
        case write_static:
            required |= VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
            break;
        
        case write_dynamic:
            required |= VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
            optional |= VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
            break;
        
        case transfer:
            required |= (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
            break;
        
        case readback:
            required |= VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
            optional |= VK_MEMORY_PROPERTY_HOST_CACHED_BIT;
            break;

        default:
            assert(0);
        }

        auto index = find(required | optional);
        return cast(size_t) (index >= 0 ? index : find(required));
    }

    Allocation* get_alloc(DeviceAlloc alloc) {
        if (auto slot = _allocations.get(alloc))
            return slot;
        return null;
    }

    Allocator _mem;
    DispatchTable* _vk;
    Logger _log;

    VkPhysicalDeviceMemoryProperties _memory_properties;
    ObjectPool!(Allocation, 64 /* TODO: increate ObjectPool size limits */ ) _allocations;
}

struct BufferTransferOp {
    // Note: a VkBufferSlice { VkDeviceMemory, VkBuffer, VkDeviceSize offset, VkDeviceSize size } would be nice here
    DeviceAlloc src;
    DeviceAlloc dst;
    uint src_queue_family;
    uint dst_queue_family;
    VkAccessFlags src_flags;
    VkAccessFlags dst_flags;
}

void begin_transfer(DispatchTable* _vk, VkCommandBuffer commands) {
    VkCommandBufferBeginInfo begin_i = {
        flags: 0,
        pInheritanceInfo: null
    };

    _vk.BeginCommandBuffer(commands, begin_i);
}

void record_transfer(DispatchTable* _vk, ref DeviceMemory memory, VkCommandBuffer commands, ref BufferTransferOp op) {
    auto src = memory.get_alloc(op.src);
    auto dst = memory.get_alloc(op.dst);
    assert(src.type == Allocation.Type.Buffer && dst.type == Allocation.Type.Buffer);

    assert(src.offset + dst.size <= src.size, "Source buffer size must be greater or equal to its offset plus copy size.");

    VkBufferCopy copy_i = {
        srcOffset: src.offset,
        dstOffset: dst.offset,
        size: dst.size,
    };

    _vk.CmdCopyBuffer(commands, src.buffer_handle, dst.buffer_handle, copy_i);

    VkBufferMemoryBarrier[1] barrier = [{
        srcAccessMask: op.src_flags,
        dstAccessMask: op.dst_flags,
        srcQueueFamilyIndex: op.src_queue_family,
        dstQueueFamilyIndex: op.dst_queue_family,
        buffer: dst.buffer_handle,
        offset: dst.offset,
        size: dst.size
    }];

    _vk.CmdPipelineBarrier(commands, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_VERTEX_INPUT_BIT, 0, [], barrier, []);
}

void submit_transfer(DispatchTable* _vk, VkCommandBuffer commands, VkQueue transfer_queue, VkFence complete_fence = VK_NULL_HANDLE) {
    _vk.EndCommandBuffer(commands);

    VkSubmitInfo submit_i = {
        commandBufferCount: 1,
        pCommandBuffers: &commands
    };

    _vk.QueueSubmit(transfer_queue, complete_fence, submit_i);
}

private:

struct Allocation {
    enum Type: ubyte {
        Image,
        Buffer
    }

    VkDeviceMemory handle;
    VkDeviceSize offset;
    VkDeviceSize size;
    VkDeviceSize block_size;
    Type type;
    private ubyte[1] _padding;
    ushort num_mapped;

    union {
        VkImage image_handle;
        VkBuffer buffer_handle;
    }

    this(VkDeviceMemory memory, VkDeviceSize mem_offset, VkDeviceSize alloc_size, VkDeviceSize block_size, VkImage image) {
        handle = memory;
        offset = mem_offset;
        size = alloc_size;
        block_size = block_size;
        type = Type.Image;
        image_handle = image;
    }

    this(VkDeviceMemory memory, VkDeviceSize mem_offset, VkDeviceSize alloc_size, VkDeviceSize block_size, VkBuffer buffer) {
        handle = memory;
        offset = mem_offset;
        size = alloc_size;
        block_size = block_size;
        type = Type.Buffer;
        buffer_handle = buffer;
    }
}
