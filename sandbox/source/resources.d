module resources;

import flare.core.math.util : round_to_next;
import flare.vulkan;

/**
Describes the location of an allocation, and the features that it must support.
*/
enum MemoryType {
    /// Device-local memory for data that is read often and written rarely. Use
    /// this for meshes, persistent textures, etc.
    Static,

    /// Device-local memory for data that is read often and read a few times.
    /// Use this for uniforms.
    Dynamic,

    /// Host-local memory for data for transferring data to the device.
    Transfer,

    /// Host-local memory that is cached for reading dynamic data from the
    /// device.
    Readback
}

/**
Describes the intended use for a memory allocation.
*/
enum MemoryUsage {
    Unknown         = 0,
    VertexBuffer    = 1 << 0,
    IndexBuffer     = 1 << 1,
    TransferDst     = 1 << 2,
    MeshBuffer      = VertexBuffer | IndexBuffer
}

struct BufferAllocInfo {
    MemoryType type;
    MemoryUsage usage;
    uint size;
}

align (4) struct AllocHandle {
    void[4] value;

    bool opCast(T: bool)() {
        return *(cast(ulong*) &value[0]) != 0;
    }
}

struct DeviceBuffer {
    struct Partition {
        uint size;
        uint alignment;
    }

    AllocHandle handle;
    uint offset;
    uint size;

    DeviceBuffer opIndex() {
        return this;
    }

    DeviceBuffer opSlice(uint lo, uint hi) {
        assert(handle && lo < hi && offset + hi <= size);
        return DeviceBuffer(handle, offset + lo, hi - lo);
    }

    uint opDollar() {
        return size;
    }

    bool partition(Partition[] part_specs, DeviceBuffer[] parts) {
        assert(part_specs.length == parts.length);

        size_t start = offset;
        foreach (i, ref spec; part_specs) {
            start = round_to_next(start, spec.alignment);

            if (start + spec.size >= size)
                return false;
            
            parts[i] = DeviceBuffer(handle, cast(uint) offset, spec.size);
            start += spec.size;
        }

        assert(0, "Not Implemented");
    }
}

class VulkanResourceManager {
    import std.algorithm : filter, map, sum, min;
    import std.bitmanip : bitfields;
    import flare.core.memory : kib, vm_alloc, vm_commit, vm_free;

    /// The smallest allocation size that can fully tile the device's memory.
    /// This size governs the number of user-facing allocations that are
    /// supported. For example, a device with 6 gib of VRAM will permit 393216
    /// allocations total.
    enum min_average_alloc_size = 16.kib;

    // 2 million allocations. Should be plenty, right?
    enum max_allocations = 2 ^^ 20;

    enum init_log_message_template = 
"Initializing Vulkan memory manager.
\tTotal Device Memory:              %s bytes
\tMax user allocations:             %s bytes
\tUnaddressable memory size:        %s bytes
\tAllocation table size (virtual):  %s bytes";

public:
    this(VulkanDevice device) {
        _device = device;

        vkGetPhysicalDeviceMemoryProperties(device.gpu.handle, &_memory_info);
        
        const device_memory_size = _memory_info.memoryHeaps[0 .. _memory_info.memoryHeapCount]
            .filter!(h => (h.flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) != 0)
            .map!(h => h.size)
            .sum();

        assert(min_average_alloc_size < device_memory_size, "Device memory less than tiling size?? This GPU is not supported");

        const num_tiles = min(device_memory_size / min_average_alloc_size, max_allocations);
        const unusable_space = device_memory_size % min_average_alloc_size;

        const table_size = num_tiles * BufferAllocSlot.sizeof;
        _buffers = cast(BufferAllocSlot[]) vm_alloc(table_size)[0 .. table_size];
        assert(_buffers.length == num_tiles);

        vm_commit(_buffers);

        device.context.logger.info(init_log_message_template, device_memory_size, num_tiles, unusable_space, table_size);
    }

    ~this() {
        vm_free(_buffers);
    }

    DeviceBuffer allocate(ref BufferAllocInfo info) {
        auto slot = allocate_slot();

        // do allocation

        return DeviceBuffer();
    }

    void deallocate(DeviceBuffer buffer) {
        auto index = Index(buffer.handle);

        deallocate_slot(index);
    }

private:
    union BufferAllocSlot {
        Index index;
        struct {
            uint size;
            VkBuffer buffer;
        }
    }

    union Index {
        AllocHandle handle;

        struct {
            mixin(bitfields!(
                uint,"offset", 20,
                uint,"generation", 12
            ));
        }
    }

    BufferAllocSlot* allocate_slot() {
        return null;
    }

    void deallocate_slot(Index index) {

    }

    VulkanDevice _device;
    VkPhysicalDeviceMemoryProperties _memory_info;

    BufferAllocSlot* _buffer_freelist;
    BufferAllocSlot[] _buffers;
    size_t _active_buffer_slots;
}

class VulkanStagingManager {
    this(VulkanResourceManager resources) {

    }
}
