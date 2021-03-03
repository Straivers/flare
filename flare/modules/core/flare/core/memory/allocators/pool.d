module flare.core.memory.allocators.pool;

import flare.core.memory.measures;
import flare.core.memory.allocators.common;
import flare.core.memory.allocators.allocator;

import core.stdc.string : memset;

struct MemoryPool {
public nothrow:
    /**
    Initializes a memory pool of `memory.length / block_size` blocks. Block size
    must be at least `size_t.sizeof` and does not require any particular
    alignment. However, actual memory will always be aligned to at least 8-byte
    boundaries.

    Blocks must be at least 4 bytes in size, and aligned to 4- or 8-byte
    boundaries. This size is used as an approximation for alignment, so sizes
    divisible by 8 are aligned to 8 bytes, and blocks divisible by 4 but not 8
    are aligned to 4-byte boundaries.

    Params:
        memory =        The backing memory to be used for object allocations.
                        Its size must be a multiple of `block_size`.
        block_size =    The minumum size of each block in the pool. 
    */
    this(void[] memory, size_t block_size) {
        _start = memory.ptr;

        if (block_size % 8 == 0)
            _alignment = 8;
        else if (block_size % 4 == 0)
            _alignment = 4;
        else
            assert(0, "Memory pool block sizes must be divisible by 4!");

        assert((cast(size_t) _start) % _alignment == 0, "Memory pool memory must be aligned to the block's alignment");

        _block_size = block_size;
        _num_blocks = memory.length / _block_size;

        foreach (i; 0 .. memory.length / _block_size) {
            assert(i < uint.max);

            auto b = cast(_Block*) (_start + i * _block_size);
            b.next_index = (cast(uint) i) + 1;
        }
    }

    this(Allocator allocator, size_t block_size, size_t num_blocks) {
        _base_allocator = allocator;
        this(_base_allocator.allocate(block_size * num_blocks), block_size);
    }

    @disable this(this);

    ~this() {
        if (_base_allocator) {
            auto mem = _start[0 .. _block_size * _num_blocks];
            _base_allocator.deallocate(mem);
        }
    }

    void[] managed_memory() nothrow {
        return _start[0 .. _num_blocks * _block_size];
    }

    size_t alignment() const {
        return _alignment;
    }

    Ternary owns(void[] memory) const {
        return Ternary(memory == null || (_start <= memory.ptr && memory.ptr + memory.length <= (_start + _num_blocks * _block_size)));
    }

    size_t get_optimal_alloc_size(size_t size) const {
        if ((size > 0) & (size <= _block_size))
            return _block_size;
        return 0;
    }

    void[] allocate(size_t size) {
        if (size > _block_size || _freelist_index >= _num_blocks)
            return null;
        
        auto block = cast(_Block*) (_start + _freelist_index * _block_size);
        _freelist_index = block.next_index;

        return memset(cast(void*) block, 0, size)[0 .. size];
    }

    bool deallocate(ref void[] memory) {
        assert(owns(memory) == Ternary.yes);

        if (memory is null)
            return true;

        auto block = cast(_Block*) memory.ptr;
        const index = cast(uint) (memory.ptr - _start) / _block_size;

        debug {
            for (auto i = _freelist_index; i < _num_blocks;) {
                assert(index != i, "Double-deallocation detected in memory pool!");

                auto free_block = cast(_Block*) (_start + i * _block_size);
                i = free_block.next_index;
            }
        }

        block.next_index = _freelist_index;
        _freelist_index = index;

        memory = null;
        return true;
    }

private:
    struct _Block {
        uint next_index;
    }

    Allocator _base_allocator;

    size_t _alignment;
    size_t _block_size;
    size_t _num_blocks;

    void* _start;

    // _Block* _freelist;
    uint _freelist_index;
}

unittest {
    import flare.core.memory.allocators.allocator: test_allocate_api;
    
    auto allocator = MemoryPool(new void[](36), 12);
    assert(allocator.alignment == 4);

    test_allocate_api(allocator);

    {
        // Test allocate-free-allocate
        auto m1 = allocator.allocate(1);
        const s1 = m1.ptr;
        allocator.deallocate(m1);
        auto m2 = allocator.allocate(allocator.get_optimal_alloc_size(1));
        assert(m2.ptr == s1);
        allocator.deallocate(m2);
    }
    {
        // Test alignment semantics
        auto m1 = allocator.allocate(1);
        auto m2 = allocator.allocate(1);
        assert((m2.ptr - m1.ptr) % 4 == 0);
        allocator.deallocate(m1);
        allocator.deallocate(m2);
    }
    {
        // Test memory exhaustion
        void[][3] m;
        foreach (ref alloc; m)
            alloc = allocator.allocate(1);

        assert(!allocator.allocate(1));

        foreach (ref alloc; m)
            allocator.deallocate(alloc);
        
        foreach (alloc; m)
            assert(!alloc);
    }
}

unittest {
    auto allocator = MemoryPool(new void[](48), 16);
    assert(allocator.alignment == 8);

    test_allocate_api(allocator);

    {
        // Test allocate-free-allocate
        auto m1 = allocator.allocate(1);
        const s1 = m1.ptr;
        allocator.deallocate(m1);
        auto m2 = allocator.allocate(allocator.get_optimal_alloc_size(1));
        assert(m2.ptr == s1);
        allocator.deallocate(m2);
    }
    {
        // Test alignment semantics
        auto m1 = allocator.allocate(1);
        auto m2 = allocator.allocate(1);
        assert((m2.ptr - m1.ptr) % 8== 0);
        allocator.deallocate(m1);
        allocator.deallocate(m2);
    }
    {
        // Test memory exhaustion
        void[][3] m;
        foreach (ref alloc; m)
            alloc = allocator.allocate(1);

        assert(!allocator.allocate(1));

        foreach (ref alloc; m)
            allocator.deallocate(alloc);
        
        foreach (alloc; m)
            assert(!alloc);
    }
}

unittest {
    // Test double-deallocation detection
    import core.exception: AssertError;

    auto allocator = MemoryPool(new void[](64), 8);
    assert(allocator.alignment == 8);

    auto m = allocator.allocate(1);
    auto s = m;

    allocator.deallocate(m);

    bool had_error;
    try
        allocator.deallocate(s);
    catch (AssertError e)
        had_error = true;
    assert(had_error);
}

/**
An object pool stores a fixed pool of objects, which may be allocated and freed
quickly.
*/
struct ObjectPool(T) {
public nothrow:
    /**
    Initializes the object pool using a preallocated block of memory. Ownership
    of the memory remains with the caller, but the caller must guarantee that
    the memory will not be modified except through the pool while the pool
    exists.

    Params:
        memory = The block of memory from which object allocations will be
                 served. It must be a multiple of `object_size!T`.
    */
    this(void[] memory) {
        _pool = MemoryPool(memory, object_size!T);

        // Class alignment = 8 (pointers)
        assert(_pool.alignment == T.alignof);
    }

    /**
    Initializes the object pool by allocating a block of memory from the base
    allocator. This block will be automatically cleaned up when the pool is
    destroyed.

    Params:
        base_allocator =    The allocator that provides the pool's memory.
        pool_size =         The number of elements to have in the pool.
    */
    this(Allocator base_allocator, size_t pool_size) {
        _pool = MemoryPool(base_allocator, object_size!T, pool_size);
    }

    /// The alignment of every allocation from this pool, in bytes.
    size_t alignment() const {
        return _pool.alignment;
    }

    /**
    Tests if the object was allocated from this pool.

    Params:
        object = The pointer to test
    
    Returns: `yes` if the object belongs, `no` otherwise.
    */
    Ternary owns(PtrType!T object) const {
        return _pool.owns((cast(void*) object)[0 .. object_size!T]);
    }

    /**
    Allocates a new object and initializes it in place.

    Params:
        args = Arguments for the object's constructor. May be empty.
    
    Returns: A pointer to the object if allocation was successful, or null if it
             failed.
    */
    PtrType!T make(Args...)(auto scope ref Args args) {
        return flare.core.memory.allocators.allocator.make!T(_pool, args);
    }

    /**
    Deallocates the object returns it to the pool.

    Note: It is an error to call this function with an object not owned by the
    pool.

    Params:
        object = The object of the object to deallocate.
    */
    void dispose(ref PtrType!T object) {
        return flare.core.memory.allocators.allocator.dispose(_pool, object);
    }

private:
    MemoryPool _pool;
}
