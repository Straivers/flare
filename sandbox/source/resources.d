module resources;

import flare.renderer.vulkan.api;

/**
Describes the location of an allocation, and the features that it must support.
*/
enum MemoryType : ubyte {
    Unknown = 0,

    /// Device-local memory for data that is read often and written rarely. Use
    /// this for meshes, persistent textures, etc.
    Static = 1,

    /// Device-local memory for data that is read often and read a few times.
    /// Use this for uniforms.
    Dynamic = 2,

    /// Host-local memory for data for transferring data to the device.
    Transfer = 3,

    /// Host-local memory that is cached for reading dynamic data from the
    /// device.
    Readback = 4,

    /// The number of supported memory types.
    Count
}

/+

/**
Describes the intended use for a memory allocation.
*/
enum MemoryUsage : ubyte {
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

align (8) struct AllocationId {
    void[8] value;

    bool opCast(T: bool)() const {
        return *(cast(ulong*) &value[0]) != 0;
    }
}

class VulkanResourceManager {
    import flare.memory.virtual: vm_alloc, vm_commit, vm_free;
    import flare.memory.allocators.allocator: make_array, dispose;

    /// 2 Million Allocations
    // At 8 bytes per index, 2 ^ 20 slots gives 16 mib for the table
    enum max_allocations = 2 ^^ 20;

public:
    this(VulkanDevice device) {
        _device = device;

        vkGetPhysicalDeviceMemoryProperties(device.gpu.handle, &_memory_info);

        auto mem = vm_alloc(max_allocations * AllocationId_.sizeof)[0 .. max_allocations];
        vm_commit(mem);

        _id_pool = cast(AllocationId_[]) mem;

        // Initialize first ID so that we can use AllocationId(0) as 'null'.
        _first_free_slot_index = 0;
        _num_touched_ids = 1;
        _id_pool[0].index_or_next = AllocationId_.max_u20;
        _id_pool[0].generation = 1;

        _memory_pools = device.context.memory.make_array!VulkanMemoryPool(_memory_info.memoryHeapCount);
    }

    ~this() {
        _device.context.memory.dispose(_memory_pools);
        vm_free(_id_pool);
    }

    DeviceBuffer allocate(ref BufferAllocInfo info) {
        auto id = _allocate_id();
        
        _memory_pools[info.type].allocate(info, id);

        return DeviceBuffer(id.handle, 0, 0);
    }

    void deallocate(DeviceBuffer buffer) {
        const id = AllocationId_(buffer.handle);
        assert(_verify(id));

        _memory_pools[id.pool_type].deallocate(buffer);

        _deallocate_id(id);
    }

private:
    bool _verify(AllocationId_ id) {
        // Chort-circuit so we won't access untouched (and unbacked) memory.
        if (id.index_or_next < _num_touched_ids)
            return false;

        const id_mask = id.mask_value & (~AllocationId_.manager_data_mask);
        const pool_id_mask = _id_pool[id.index_or_next].mask_value & (~AllocationId_.manager_data_mask);

        return id_mask == pool_id_mask;
    }

    AllocationId_ _allocate_id() {
        if (_first_free_slot_index != AllocationId_.max_u20) {
            const index = _first_free_slot_index;
            auto pool_id = &_id_pool[index];

            pool_id.index_or_next = index;
            pool_id.is_live = true;

            _first_free_slot_index = pool_id.index_or_next;

            return *pool_id;
        }

        if (_num_touched_ids == _id_pool.length)
            assert(0, "Ran out of allocation IDs");

        const index = _num_touched_ids;
        _num_touched_ids++;

        auto pool_id = &_id_pool[index];
        pool_id.index_or_next = index;
        pool_id.is_live = true;

        return *pool_id;
    }

    void _deallocate_id(AllocationId_ id) {
        assert(_verify(id));
        
        auto pool_id = &_id_pool[id.index_or_next];
        assert(pool_id.is_live);

        // Clear all bits except index and generation (is_live = false)
        pool_id.mask_value = pool_id.mask_value & AllocationId_.index_generation_mask;

        const index = pool_id.index_or_next;
        pool_id.index_or_next = _first_free_slot_index;

        // If the generation is not saturated, add it back to the pool
        if (pool_id.generation < AllocationId_.max_u20) {
            pool_id.generation = pool_id.generation + 1;
            _first_free_slot_index = index;
        }
    }

    VulkanDevice _device;
    VkPhysicalDeviceMemoryProperties _memory_info;

    uint _first_free_slot_index;
    uint _num_touched_ids;
    AllocationId_[] _id_pool;

    VulkanMemoryPool[] _memory_pools;
}

private:

union AllocationId_ {
    import std.bitmanip : bitfields;

    enum max_u20 = 2 ^^ 20 - 1;

    /// Mask with all bits for index_or_next and generation members set.
    static immutable ulong index_generation_mask;

    /// Mask with all bits for 
    static immutable ulong manager_data_mask;

    shared static this() {
        AllocationId_ id_generation;
        id_generation.index_or_next = AllocationId_.max_u20;
        id_generation.generation = AllocationId_.max_u20;
        AllocationId_.index_generation_mask = id_generation.mask_value;
        
        AllocationId_ manager_data;
        manager_data.impl_u20 = AllocationId_.max_u20;
        AllocationId_.manager_data_mask = manager_data.mask_value;
    }

public:
    AllocationId handle;
    ulong mask_value;

    struct {
        mixin(bitfields!(
            // ResourceManager data
            uint,       "index_or_next",    20,
            uint,       "generation",       20,
            bool,       "is_live",          1,
            MemoryType, "pool_type",        3,

            // MemoryPool data
            uint,       "impl_u20",         20,
        ));
    }
}

struct VulkanMemoryPool {
    import flare.memory.measures: mib, gib;

    enum chunk_size = 256.mib;
    enum max_chunk_size = 4.gib;

public:
    @disable this(this);

    DeviceBuffer allocate(ref BufferAllocInfo info, ref AllocationId_ id) {
        assert(0);
    }

    void deallocate(DeviceBuffer allocation) {

    }

private:
    struct Block {
        VkDeviceMemory memory;

        // occupancy table...? buddy allocator setup?
    }
}
+/