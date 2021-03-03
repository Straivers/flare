module mem.device;

import flare.core.math.util : max, round_to_next;
import flare.core.memory : Allocator, make, dispose, mib;
import flare.core.list : intrusive_list;
import flare.vulkan;

import std.bitmanip : bitfields;

enum Transferability : ubyte {
    None,
    Send    = 1 << 0,
    Receive = 1 << 1,
    Both    = Send | Receive,
}

static assert(Transferability.Both == 3);

enum DeviceHeap : ubyte {
    Unknown = 0,

    /// Device-local memory for data that is read often and written rarely. Use
    /// this for meshes, persistent textures, etc.
    Static = 1,

    /// Device-local memory for data that is written often and read a few times.
    /// Use this for uniforms.
    Dynamic = 2,

    /// Host-local memory for data for transferring data to the device.
    Transfer = 3,

    /// Host-local memory that is cached for reading dynamic data from the
    /// device.
    Readback = 4,
}

VkMemoryPropertyFlags get_required_flags(DeviceHeap heap) {
    static immutable conv = [
        /* Unknown  */ 0,
        /* Static   */ VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        /* Dynamic  */ VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        /* Transfer */ VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        /* Readback */ VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT
    ];
    return conv[heap];
}

VkMemoryPropertyFlags get_optional_flags(DeviceHeap heap) {
    static immutable conv = [
        /* Unknown  */ 0,
        /* Static   */ 0,
        /* Dynamic  */ VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        /* Transfer */ 0,
        /* Readback */ 0,
    ];
    return conv[heap];
}

int get_memory_type_index(VulkanDevice device, DeviceHeap heap, uint required_memory_type_bits) {
    auto memory_types = device.gpu.memory_properties.memoryTypes[0 .. device.gpu.memory_properties.memoryTypeCount];

    int find_index(VkMemoryPropertyFlags flags) {
        foreach (i, type; memory_types) {
            const type_bits = (1 << i);
            const is_correct_type = (required_memory_type_bits & type_bits) != 0;
            const has_properties = (type.propertyFlags & flags) == flags;

            // Vulkan spec guarantees that types are sorted fewest-bits first.
            // We will always get the best match.
            if (is_correct_type & has_properties)
                return cast(int) i;
        }

        return -1;
    }

    const required_flags = get_required_flags(heap);
    const optional_flags = get_optional_flags(heap);
    const type = find_index(required_flags | optional_flags);
    return type < 0 ? find_index(required_flags) : type;
}

struct DeviceMemory {
    static assert(DeviceMemory.sizeof == 24);
    static assert(DeviceMemory.alignof == 8);

public:
    VkDeviceMemory handle;
    uint offset;

    mixin(bitfields!(
        uint, "size", 29,
        DeviceHeap, "heap", 3,
    ));

    align (8) void[8] impl_data;

    this(VkDeviceMemory handle, uint offset, uint size, DeviceHeap heap, void[8] impl_data) {
        this.handle = handle;
        this.offset = offset;
        this.size = size;
        this.heap = heap;
        this.impl_data = impl_data;
    }

    // dfmt off
    DeviceMemory opIndex() { return this; }
    uint opDollar() { return size; }
    // dfmt on

    DeviceMemory opSlice(uint lo, uint hi) {
        assert(handle && lo < hi && offset + hi <= size);
        return DeviceMemory(handle, offset + lo, hi - lo, heap, impl_data);
    }
}

/// Arbitrates memory allocations for different types
final class RawDeviceMemoryAllocator {
    this(VulkanDevice device) {
        _device = device;
    }

    VulkanDevice device() { return _device; }

    size_t buffer_image_granularity() {
        return device.properties.limits.bufferImageGranularity;
    }

    bool allocate_raw(uint type_index, size_t size, out VkDeviceMemory memory) {
        VkMemoryAllocateInfo alloc_i = {
            allocationSize: size,
            memoryTypeIndex: type_index
        };

        return _device.dispatch_table.AllocateMemory(alloc_i, memory) == VK_SUCCESS;
    }

    void deallocate_raw(VkDeviceMemory memory) {
        _device.dispatch_table.FreeMemory(memory);
    }

private:
    VulkanDevice _device;
}

interface DeviceMemoryAllocator {
    VulkanDevice device();

    bool allocate(const ref VkMemoryRequirements reqs, bool is_linear, out DeviceMemory allocation);

    bool deallocate(DeviceMemory allocation);

    void clear();
}

final class LinearPool : DeviceMemoryAllocator {
    enum default_block_size = cast(uint) 64.mib;

public:
    this(RawDeviceMemoryAllocator* device_memory, Allocator management_allocator, uint type_index, DeviceHeap heap) {
        _device_memory = device_memory;
        _management_memory = management_allocator;
        _type_index = type_index;
        _heap = heap;

        _add_block(0);
    }

    ~this() {
        while (!_blocks.is_empty())
            _remove_last_block();
    }

    override VulkanDevice device() {
        return _device_memory.device;
    }

    override bool allocate(const ref VkMemoryRequirements reqs, bool is_linear, out DeviceMemory allocation) {
        assert(reqs.size < uint.max);

        auto block = _blocks[0];

        const needs_big_alignment = block.was_last_alloc_linear == is_linear;
        const real_alignment = max(reqs.alignment, needs_big_alignment ? reqs.alignment : _device_memory.buffer_image_granularity);
        const aligned_top = round_to_next(block.top, real_alignment);
        assert(aligned_top < uint.max);

        if (block.size - aligned_top >= reqs.size) {
            // Allocation can be serviced from current block.

            allocation.handle = block.handle;
            allocation.offset = cast(uint) aligned_top;
            allocation.size = cast(uint) reqs.size;
            allocation.heap = _heap;

            block.top = cast(uint) (aligned_top + reqs.size);
            block.was_last_alloc_linear = is_linear;
            return true;
        }
        else if (auto new_block = _add_block(cast(uint) reqs.size)) {
            // Allocation will not fit in current block, so make a new one.

            allocation.handle = new_block.handle;
            allocation.offset = new_block.top;
            allocation.size = cast(uint) reqs.size;
            allocation.heap = _heap;

            new_block.top = cast(uint) reqs.size;
            assert(reqs.size < default_block_size || new_block.size == reqs.size);

            block.was_last_alloc_linear = is_linear;
            return true;
        }

        return false;
    }

    override bool deallocate(DeviceMemory allocation) {
        return true;
    }

    override void clear() {
        while (_blocks.length > 1)
            _remove_last_block();

        assert(_blocks.length == 1);
    }

private:
    struct _LinearBlock {
        VkDeviceMemory handle;

        uint top;
        uint size;

        bool was_last_alloc_linear;

        mixin intrusive_list!_LinearBlock;
    }

    _LinearBlock* _add_block(uint size) {
        if (size < default_block_size) {
            // Use larger blocks, can subdivide later.
            auto new_block = _management_memory.make!_LinearBlock();

            // If we can't fit a full block, try half that size, repeatedly.
            auto block_size = default_block_size;
            while (!_device_memory.allocate_raw(_type_index, block_size, new_block.handle)) {
                block_size /= 2;

                if (block_size < size)
                    return null;
            }

            new_block.size = block_size;

            // Push it to the front so that future allocations may be able to
            // make use of any remaining space.
            _blocks.push_front(new_block);
            return new_block;
        }
        else {
            // Use dedicated block because of its large size.
            auto new_block = _management_memory.make!_LinearBlock();

            if (_device_memory.allocate_raw(_type_index, size, new_block.handle)) {
                new_block.size = size;

                // Push it to the back because the entire block is going to be
                // used. Since we check the first block for space when we
                // allocate, we might end up wasting a lot of memory otherwise.
                _blocks.push_back(new_block);
                return new_block;
            }

            return null;
        }
    }

    void _remove_last_block() {
        assert(_blocks.length > 0);

        auto block = _blocks.pop_front();
        _device_memory.deallocate_raw(block.handle);
        _management_memory.dispose(block);
    }

    RawDeviceMemoryAllocator* _device_memory;
    Allocator _management_memory;

    uint _type_index;
    DeviceHeap _heap;
    _LinearBlock.ListHead _blocks;
}

private:

union DeviceMemoryImplData {
    align (8) void[8] impl_data;

    struct {
        uint block_offset;
        bool is_dedicated;
        void[3] _padding;
    }
}
