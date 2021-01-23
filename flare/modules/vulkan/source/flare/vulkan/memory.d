module flare.vulkan.memory;

import flare.vulkan.h;
import flare.vulkan.dispatch;

enum ResourceUsage : ubyte {
    invalid = 0,
    write_static = 2,
    write_dynamic = 1,
    transfer = 3,
    readback = 4,
}

struct DeviceAllocation {
    VkDeviceMemory memory;
    VkDeviceSize size;

    MemorySlice opIndex() {
        return MemorySlice(memory, 0, size);
    }

    MemorySlice opSlice(size_t lo, size_t hi) {
        assert(lo <= hi);
        return MemorySlice(memory, lo, hi - lo); 
    }

    VkDeviceSize opDollar() {
        return size;
    }
}

/**
A non-owning reference to a portion of a memory allocation.
*/
struct MemorySlice {
    VkDeviceMemory memory;
    VkDeviceSize offset;
    VkDeviceSize size;

    MemorySlice opIndex() {
        return MemorySlice(memory, offset, size);
    }

    MemorySlice opSlice(size_t lo, size_t hi) {
        assert(memory && lo <= hi && offset + hi <= size);
        return MemorySlice(memory, offset + lo, hi - lo); 
    }

    VkDeviceSize opDollar() {
        return size;
    }
}

struct Buffer {
    VkBuffer handle;
    MemorySlice backing_memory;

    alias backing_memory this;
    
    Buffer opIndex() {
        return Buffer(handle, backing_memory);
    }

    Buffer opSlice(size_t lo, size_t hi) {
        return Buffer(handle, backing_memory[lo .. hi]); 
    }

    VkDeviceSize opDollar() {
        return backing_memory.size;
    }
}

/**
Per-device memory manager. Allocates in chunks of multiples of 32 MiB (max 32
chunks per GiB).
*/
struct DeviceMemory {
    import flare.core.memory.api: mib;

    enum minimum_allocation_size = 32.mib;

public:
    this(DispatchTable* dispatch_table, VkPhysicalDevice gpu) nothrow {
        _vk = dispatch_table;

        VkPhysicalDeviceProperties properties;
        vkGetPhysicalDeviceProperties(gpu, &properties);
        _page_size = properties.limits.bufferImageGranularity;

        vkGetPhysicalDeviceMemoryProperties(gpu, &_memory_properties);
    }

    VkDeviceSize page_size() const {
        return _page_size;
    }

    ref const(VkPhysicalDeviceMemoryProperties) memory_properties() const return {
        return _memory_properties;
    }

    DeviceAllocation allocate(uint type_index, size_t size) {
        assert(size % minimum_allocation_size == 0);

        VkMemoryAllocateInfo alloc_i = {
            allocationSize: size,
            memoryTypeIndex: type_index
        };

        DeviceAllocation allocation;
        _vk.AllocateMemory(alloc_i, allocation.memory);
        allocation.size = size;

        return allocation;
    }

    void deallocate(ref DeviceAllocation memory) {
        _vk.FreeMemory(memory.memory);
        memory = DeviceAllocation();
    }

    uint get_memory_type_index(ResourceUsage usage, uint memory_type_bits) {
        int find(VkMemoryPropertyFlags required_properties) {
            foreach (i, memory_type; memory_properties.memoryTypes[0 .. memory_properties.memoryTypeCount]) {
                const type_bits = (1 << i);
                const is_correct_type = (memory_type_bits & type_bits) != 0;
                const has_properties = (memory_type.propertyFlags & required_properties) == required_properties;

                if (is_correct_type & has_properties)
                    return cast(int) i;
            }

            return -1;
        }

        VkMemoryPropertyFlags required, optional;
        switch (usage) with (ResourceUsage) {
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

        if (index < 0 && (required | optional) != required)
            index = find(required);

        assert(index >= 0);
        return cast(uint) index;
    }

private:
    DispatchTable* _vk;
    VkDeviceSize _page_size;
    VkPhysicalDeviceMemoryProperties _memory_properties;
}

struct MappedMemory {
    this(DeviceMemory* device_memory, Buffer buffer) {
        _device_memory = device_memory;
        _memory = buffer;

        void* ptr;
        _device_memory._vk.MapMemory(_memory.memory, _memory.offset, _memory.size, 0, ptr);
        _mapping = ptr[0 .. _memory.size];
    }

    ~this() {
        if (_mapping) {
            _device_memory._vk.UnmapMemory(_memory.memory);
            _mapping = [];
        }
    }

    Buffer put(T)(const auto ref T[] data) {
        // make sure data fits in memory
        auto data_mem = cast(void[]) data;
        assert(_mapping.length - _n_bytes >= data_mem.length);

        _mapping[_n_bytes .. _n_bytes + data_mem.length] = data_mem;

        scope (exit) _n_bytes += data_mem.length;
        return _memory[_n_bytes .. _n_bytes + data_mem.length];
    }

private:
    DeviceMemory* _device_memory;
    Buffer _memory;

    size_t _n_bytes;
    void[] _mapping;
}

struct VulkanStackAllocator {
    import flare.core.memory.base: round_to_multiple_of;

    enum default_block_size = DeviceMemory.minimum_allocation_size * 2;

public:
    this(DeviceMemory* device_memory, VkDeviceSize block_size = default_block_size) {
        _device_memory = device_memory;
        _block_size = default_block_size;
    }

    ~this() {
        if (!_last_block)
            return;
        
        for (auto block = _last_block; block !is null; block = block.prev) {
            _device_memory.deallocate(block.allocation);
        }
    }

    Buffer create_buffer(VkBufferUsageFlags usage_flags, ResourceUsage resource_usage, size_t size) {
        VkBufferCreateInfo buffer_ci = {
            size: size,
            usage: usage_flags,
            sharingMode: VK_SHARING_MODE_EXCLUSIVE,
        };

        Buffer buffer;
        _device_memory._vk.CreateBuffer(buffer_ci, buffer.handle);
        buffer.backing_memory = allocate(buffer.handle, resource_usage);

        _device_memory._vk.BindBufferMemory(buffer.handle, buffer.memory, buffer.offset);

        return buffer;
    }

    void destroy_buffer(Buffer buffer) {
        _device_memory._vk.DestroyBuffer(buffer.handle);
        deallocate(buffer.backing_memory);
    }

    MemorySlice allocate(VkBuffer buffer, ResourceUsage usage) {
        VkMemoryRequirements requirements;
        _device_memory._vk.GetBufferMemoryRequirements(buffer, requirements);
        const alloc_size = requirements.size.round_to_multiple_of(_device_memory.page_size);

        assert(alloc_size <= _block_size);

        if (!_last_block) {
            _type_index = _device_memory.get_memory_type_index(usage, requirements.memoryTypeBits);
            _last_block = new _Block(_last_block, _device_memory.allocate(_type_index, _block_size));
        }
        else if (_block_size - _last_block.first_free_byte < alloc_size) {
            _last_block = new _Block(_last_block, _device_memory.allocate(_type_index, _block_size));
        }

        assert(_last_block);
        auto slice = MemorySlice(_last_block.allocation.memory, _last_block.first_free_byte, requirements.size);
        _last_block.first_free_byte += alloc_size;

        return slice;
    }

    void deallocate(MemorySlice memory) {
        assert(_last_block);
        assert(memory.memory == _last_block.allocation.memory);

        const alloc_size = (memory.offset + memory.size).round_to_multiple_of(_device_memory.page_size);
        assert(alloc_size == _last_block.first_free_byte);

        _last_block.first_free_byte -= alloc_size;

        if (_last_block.first_free_byte == 0) {
            auto free_block = _last_block;
            _last_block = free_block.prev;

            _device_memory.deallocate(free_block.allocation);
            destroy(free_block);
        }
    }

private:
    struct _Block {
        _Block* prev;
        DeviceAllocation allocation;
        size_t first_free_byte;
    }

    DeviceMemory* _device_memory;
    _Block* _last_block;
    VkDeviceSize _block_size;
    uint _type_index;
}

struct BufferTransferOp {
    Buffer src;
    Buffer dst;
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

void record_transfer(DispatchTable* _vk, VkCommandBuffer commands, ref BufferTransferOp op) {
    assert(op.src.size <= op.dst.size);

    VkBufferCopy copy_i = {
        srcOffset: op.src.offset,
        dstOffset: op.dst.offset,
        size: op.src.size,
    };

    _vk.CmdCopyBuffer(commands, op.src.handle, op.dst.handle, copy_i);

    VkBufferMemoryBarrier[1] barrier = [{
        srcAccessMask: op.src_flags,
        dstAccessMask: op.dst_flags,
        srcQueueFamilyIndex: op.src_queue_family,
        dstQueueFamilyIndex: op.dst_queue_family,
        buffer: op.dst.handle,
        offset: op.dst.offset,
        size: op.src.size
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
