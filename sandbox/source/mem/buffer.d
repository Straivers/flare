module mem.buffer;

import flare.core.handle: Handle32, HandlePool;
import flare.core.memory: Allocator;
import flare.vulkan;

enum buffer_handle_name = "vulkan_buffer_handle_name";
alias BufferHandle = Handle32!buffer_handle_name;

enum BufferType : ubyte {
    Unknown,
    Index,
    Vertex,
    Uniform,
    Mesh,
}

VkBufferUsageFlags get_usage_flags(BufferType type, Transferability transferable) {
    static immutable type_conv = [
        /* Unknown  */ 0,
        /* Index    */ VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        /* Vertex   */ VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        /* Uniform  */ VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        /* Mesh     */ VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
    ];

    static immutable transferability_conv = [
        /* None     */ 0,
        /* Send     */ VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        /* Receive  */ VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        /* Both     */ VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
    ];

    return type_conv[type] | transferability_conv[transferable];
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

struct BufferInfo {
    VkBuffer handle;
    uint offset;
    uint size;
}

uint get_type_index(RawDeviceMemoryAllocator* allocator, DeviceHeap heap, BufferAllocInfo alloc_i) {
    VkBufferCreateInfo buffer_ci;
    alloc_i.to_vk_create_info(buffer_ci);

    VkBuffer sample_buffer;
    allocator.device.dispatch_table.CreateBuffer(buffer_ci, sample_buffer);
    scope (exit) allocator.device.dispatch_table.DestroyBuffer(sample_buffer);

    VkMemoryRequirements reqs;
    allocator.device.dispatch_table.GetBufferMemoryRequirements(sample_buffer, reqs);

    return get_memory_type_index(allocator.device, heap, reqs.memoryTypeBits);
}

struct BufferManager {
    import flare.core.math.util : round_to_next;
    import flare.core.memory.allocators.pool: ObjectPool;

    enum max_live_buffers = ushort.max + 1;

public:
    this(DeviceMemoryAllocator allocator) {
        _allocator = allocator;
        _allocations = ObjectPool!_AllocInfo(_allocator.device.context.memory, max_live_buffers);
        _handles = _BufferPool(_allocator.device.context.memory);
    }

    @disable this(this);

    BufferHandle create_buffer(ref BufferAllocInfo alloc_i) {
        VkBufferCreateInfo buffer_ci;
        alloc_i.to_vk_create_info(buffer_ci);
        return create_buffer(buffer_ci);
    }

    BufferHandle create_buffer(ref VkBufferCreateInfo buffer_ci) {
        VkBuffer buffer;
        _vk.CreateBuffer(buffer_ci, buffer);
        auto alloc = _alloc_mem(buffer);

        return _handles.make(alloc, 0, cast(uint) buffer_ci.size);
    }

    void create_buffers(BufferAllocInfo[] infos, BufferHandle[] handles) {
        assert(handles.length >= infos.length);

        auto alloc = () {
            VkDeviceSize total_size;
            VkBufferUsageFlags shared_flags;

            foreach (i, ref a; infos) {
                // TODO: Is using nonCoherentAtomSize for alignment correct?
                total_size += round_to_next(a.size, _allocator.device.gpu.properties.limits.nonCoherentAtomSize);
                shared_flags |= get_usage_flags(a.type, a.transferable);
            }

            assert(total_size <= uint.max);
            VkBufferCreateInfo big_buffer_ci = {
                size: total_size,
                usage: shared_flags,
                sharingMode: VK_SHARING_MODE_EXCLUSIVE
            };

            VkBuffer buffer;
            _vk.CreateBuffer(big_buffer_ci, buffer);
            return _alloc_mem(buffer, infos.length);
        } ();

        uint counting_size;
        foreach (i, ref a; infos) {
            handles[i] = _handles.make(alloc, counting_size, a.size);

            counting_size += round_to_next(a.size, _allocator.device.gpu.properties.limits.nonCoherentAtomSize);
        }
    }

    void destroy_buffer(BufferHandle handle) {
        if (auto info = _handles.get(handle)) {
            info.alloc.count--;

            if (info.alloc.count == 0) {
                if (info.alloc.times_mapped > 0)
                    _vk.UnmapMemory(info.alloc.handle);

                _vk.DestroyBuffer(info.alloc.buffer);
                _allocator.deallocate(info.alloc.memory);
                _allocations.dispose(info.alloc);
            }

            _handles.dispose(handle);
        }
        else {
            assert(0, "Attempted to destroy invalid buffer handle!");
        }
    }

    BufferInfo get(BufferHandle handle) {
        if (auto info = _handles.get(handle)) {
            return BufferInfo(info.alloc.buffer, info.offset, info.size);
        }
        else {
            assert(0, "Attempted to retrieve buffer with invalid handle!");
        }
    }

    void[] map(BufferHandle handle) {
        if (auto buf = _handles.get(handle)) {
            if (buf.alloc.times_mapped == 0) {
                _vk.MapMemory(buf.alloc.handle, buf.alloc.offset, buf.alloc.size, 0, buf.alloc.mapped_ptr);
                buf.alloc.times_mapped = 1;
            }
            else {
                buf.alloc.times_mapped++;
            }

            return buf.alloc.mapped_ptr[buf.offset .. buf.offset + buf.size];
        }
        else {
            assert(0, "Attempted to map buffer with invalid handle!");
        }
    }

    void unmap(BufferHandle handle) {
        if (auto info = _handles.get(handle)) {
            if (info.alloc.times_mapped == 0)
                assert(0, "Cannot unmap buffer that has not been mapped!");

            info.alloc.times_mapped--;

            if (info.alloc.times_mapped == 0)
                _vk.UnmapMemory(info.alloc.handle);
        }
        else {
            assert(0, "Attempted to map buffer with invalid handle!");
        }
    }

private:
    struct _AllocInfo {
        VkBuffer buffer;
        ushort count;
        ushort times_mapped;

        void* mapped_ptr;

        alias memory this;
        DeviceMemory memory;
    }

    struct _BufferInfo {
        _AllocInfo* alloc;
        uint offset;
        uint size;
    }

    DispatchTable* _vk() { return _allocator.device.dispatch_table; }

    _AllocInfo* _alloc_mem(VkBuffer buffer, size_t num_subdivisions = 1) {
        assert(num_subdivisions < ushort.max);
        auto alloc = _allocations.make(buffer, cast(ushort) num_subdivisions);

        VkMemoryRequirements reqs;
        _vk.GetBufferMemoryRequirements(buffer, reqs);
        _allocator.allocate(reqs, true, alloc.memory);
        _vk.BindBufferMemory(alloc.buffer, alloc.memory.handle, alloc.memory.offset);

        return alloc;
    }

    alias _BufferPool = HandlePool!(_BufferInfo, buffer_handle_name, max_live_buffers);

    DeviceMemoryAllocator _allocator;

    // WAAAH SO MUCH PREALLOCATION
    ObjectPool!_AllocInfo _allocations;
    _BufferPool _handles;
}
