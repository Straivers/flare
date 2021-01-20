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
    IndexBuffer,
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

    VkDeviceSize alignment_requirements(ResourceType resource_type) {
        final switch (resource_type) with (ResourceType) {
        case StagingSource:
        case VertexBuffer:
        case IndexBuffer:
            return 1;
        }
    }

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

            case IndexBuffer:
                object_type = Allocation.Type.Buffer;
                return VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;

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

        bool is_host_visible;
        const memory_type = _get_memory_type_idx(usage, requirements.memoryTypeBits, is_host_visible);

        if (memory_type >= 0) {
            VkMemoryAllocateInfo alloc_i = {
                allocationSize: requirements.size,
                memoryTypeIndex: cast(uint) memory_type
            };

            VkDeviceMemory memory;
            _vk.AllocateMemory(alloc_i, memory);
            _vk.BindBufferMemory(buffer, memory, 0);

            auto slot = _allocations.alloc();
            *slot.content = Allocation(memory, 0, size, requirements.size, is_host_visible, buffer);

            _log.trace("%s bytes allocated from %s memory pool %s for %s byte buffer.", requirements.size, is_host_visible ? "host visible" : "", memory_type, size);

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
            assert(slot.is_host_visible);

            scope (exit)
                slot.num_mapped++;

            if (!slot.num_mapped) {
                void* ptr;
                _vk.MapMemory(slot.handle, 0, slot.size, 0, ptr);
                return cast(T[]) ptr[0 .. slot.size - (slot.size % T.sizeof)];
            }
        }
        return [];
    }

    void unmap(DeviceAlloc alloc) {
        if (auto slot = _allocations.get(alloc)) {
            slot.num_mapped--;

            if (slot.num_mapped == 0) {
                flush(alloc, 0, slot.size);

                _vk.UnmapMemory(slot.handle);
                slot.num_mapped--;
            }
        }
    }

    void flush(DeviceAlloc alloc, VkDeviceSize offset = 0, VkDeviceSize size = VkDeviceSize.max) {
        if (auto slot = _allocations.get(alloc)) {
            VkMappedMemoryRange flush_range = {
                memory: slot.handle,
                offset: offset,
                size: size < VkDeviceSize.max ? size : slot.size
            };

            _vk.FlushMappedMemoryRanges(flush_range);
        }
    }

private:
    size_t _get_memory_type_idx(MemUsage type, uint memory_type_bits, out bool is_host_visible) {
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
            is_host_visible = true;
            break;

        case transfer:
            required |= (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
            is_host_visible = true;
            break;

        case readback:
            required |= VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
            optional |= VK_MEMORY_PROPERTY_HOST_CACHED_BIT;
            is_host_visible = true;
            break;

        default:
            assert(0);
        }

        auto index = find(required | optional);
        
        if (index < 0 && (required | optional) != required)
            index = find(required);

        assert(index >= 0);
        return cast(size_t) index;
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

struct MappedBuffer {
    import flare.core.memory.base: align_offset;

public:
    this(DeviceAlloc allocation, ref DeviceMemory memory) {
        _allocation = allocation;
        _memory = &memory;
        _mapped_memory = _memory.map!void(_allocation);
    }

    ~this() {
        _memory.unmap(_allocation);
    }

    void flush() {
        _memory.flush(_allocation);
    }

    BufferRange put(T)(const auto ref T[] data, ResourceType resource_type) {
        auto alignment = _memory.alignment_requirements(resource_type);
        _size = align_offset(_size, alignment);

        // make sure data fits in memory
        auto data_mem = cast(void[]) data;
        assert(_mapped_memory.length - _size >= data_mem.length);

        _mapped_memory[_size .. _size + data_mem.length] = data_mem;

        scope (exit) _size += data_mem.length;
        return BufferRange(_allocation, _size, data_mem.length);
    }

private:
    DeviceAlloc _allocation;
    DeviceMemory* _memory;

    size_t _size;
    void[] _mapped_memory;
}

struct BufferTransferOp {
    // Note: a VkBufferSlice { VkDeviceMemory, VkBuffer, VkDeviceSize offset, VkDeviceSize size } would be nice here
    BufferRange src_range;
    BufferRange dst_range;
    uint src_queue_family;
    uint dst_queue_family;
    VkAccessFlags src_flags;
    VkAccessFlags dst_flags;
}

struct BufferRange {
    DeviceAlloc allocation;
    VkDeviceSize offset;
    VkDeviceSize size;
}

void begin_transfer(DispatchTable* _vk, VkCommandBuffer commands) {
    VkCommandBufferBeginInfo begin_i = {
        flags: 0,
        pInheritanceInfo: null
    };

    _vk.BeginCommandBuffer(commands, begin_i);
}

void record_transfer(DispatchTable* _vk, ref DeviceMemory memory, VkCommandBuffer commands, ref BufferTransferOp op) {
    auto src = memory.get_alloc(op.src_range.allocation);
    auto dst = memory.get_alloc(op.dst_range.allocation);
    assert(src.type == Allocation.Type.Buffer && dst.type == Allocation.Type.Buffer);
    assert(op.src_range.size == op.dst_range.size);

    assert(src.offset + dst.size <= src.size, "Source buffer size must be greater or equal to its offset plus copy size.");

    VkBufferCopy copy_i = {
        srcOffset: src.offset + op.src_range.offset,
        dstOffset: dst.offset + op.dst_range.offset,
        size: op.dst_range.size,
    };

    _vk.CmdCopyBuffer(commands, src.buffer_handle, dst.buffer_handle, copy_i);

    VkBufferMemoryBarrier[1] barrier = [{
        srcAccessMask: op.src_flags,
        dstAccessMask: op.dst_flags,
        srcQueueFamilyIndex: op.src_queue_family,
        dstQueueFamilyIndex: op.dst_queue_family,
        buffer: dst.buffer_handle,
        offset: dst.offset + op.dst_range.offset,
        size: dst.size
    }];

    // trace: recording transfer op <top> to <commands>

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
    bool is_host_visible;
    Type type;
    ushort num_mapped;

    union {
        VkImage image_handle;
        VkBuffer buffer_handle;
    }

    this(VkDeviceMemory memory, VkDeviceSize mem_offset, VkDeviceSize alloc_size, VkDeviceSize block_size, bool is_host_visible, VkImage image) {
        handle = memory;
        offset = mem_offset;
        size = alloc_size;
        this.block_size = block_size;
        this.is_host_visible = is_host_visible;
        type = Type.Image;
        image_handle = image;
    }

    this(VkDeviceMemory memory, VkDeviceSize mem_offset, VkDeviceSize alloc_size, VkDeviceSize block_size, bool is_host_visible, VkBuffer buffer) {
        handle = memory;
        offset = mem_offset;
        size = alloc_size;
        this.block_size = block_size;
        this.is_host_visible = is_host_visible;
        type = Type.Buffer;
        buffer_handle = buffer;
    }
}
