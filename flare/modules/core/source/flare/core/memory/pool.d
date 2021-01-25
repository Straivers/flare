module flare.core.memory.pool;

import flare.core.memory.common;
import flare.core.memory.allocator;

struct MemoryPool {
public:
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

    @disable this(this);

    void[] managed_memory() {
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

        return (cast(void*) block)[0 .. size];
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

    size_t _alignment;
    size_t _block_size;
    size_t _num_blocks;

    void* _start;

    // _Block* _freelist;
    uint _freelist_index;
}

unittest {
    import flare.core.memory.allocator: test_allocate_api;
    
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
        _base_allocator = base_allocator;

        auto memory = _base_allocator.allocate(pool_size * object_size!T);
        assert(memory);

        _pool = MemoryPool(memory, object_size!T);
    }

    @disable this(this);

    ~this() {
        if (_base_allocator)
            _base_allocator.deallocate(_pool.managed_memory);
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
    PtrType!T allocate(Args...)(auto scope ref Args args) {
        auto object_pointer = cast(PtrType!T) _pool.allocate(object_size!T);
        return emplace_obj(object_pointer, args);
    }

    /**
    Deallocates the object returns it to the pool.

    Note: It is an error to call this function with an object not owned by the
    pool.

    Params:
        object = The object of the object to deallocate.

    Returns: `true` if the object was successfully returned to the allocator,
             `false` otherwise.
    */
    bool deallocate(ref PtrType!T object) {
        assert(owns(object));

        auto mem = (cast(void*) object)[0 .. object_size!T];
        return _pool.deallocate(mem);
    }

private:
    Allocator _base_allocator;
    MemoryPool _pool;
}

/**
A `WeakObjectPool` stores a fixed pool of objects from which allocations are
serviced. Each allocation is represented by a handle which is unique for every
allocation throughout the lifetime of the program. This provides the benefit
that all handles to a specific allocation become invalid once the memory has
been deallocated.
*/
struct WeakObjectPool(T) {
    align (8) struct Handle {
        uint index;
        uint generation;

        bool opCast(T : bool)() const {
            return this != Handle();
        }

        H to(H)() {
            static assert(H.sizeof == Handle.sizeof);
            static assert(H.alignof == Handle.alignof);

            union Conv {
                Handle src;
                H dst;
            }

            return Conv(this).dst;
        }

        static Handle from(H)(H h) {
            static assert(H.sizeof == Handle.sizeof);
            static assert(H.alignof == Handle.alignof);

            union Conv {
                H src;
                typeof(return) dst;
            }
            return Conv(h).dst;
        }
    }

public nothrow:
    /**
    Initializes the `WeakObjectPool` with `pool_size` objects. Allocation is
    assumed to succeed, and will panic if it fails.

    Params:
        base_allocator =    The allocator to allocate the pool from.
        pool_size =         The number of objects in the pool.
    */
    this(Allocator base_allocator, size_t pool_size) {
        _base_allocator = base_allocator;
        _num_blocks = pool_size;

        _pool = _base_allocator.make_array!_Block(pool_size);
        assert(_pool);

        foreach (i; 0 .. _num_blocks) {
            assert(_num_blocks < uint.max);
            _pool[i].next_index = (cast(uint) i) + 1;
        }

        // We set this so that Handle(0, 0) is reserved for invalid handles
        _pool[0].generation = 1;
    }

    @disable this(this);

    ~this() {
        if (_pool)
            _base_allocator.dispose(_pool);
    }

    /**
    Retrives the object referred to by `handle`.
    
    Note: It is an error to retrieve an object using an invalid handle.

    Params:
        handle = The handle to the object to retrieve.
    
    Returns: A pointer or reference to the object identified by `handle`.
    */
    PtrType!T get(Handle handle) {
        assert(owns(handle) == Ternary.yes);

        auto block = &_pool[handle.index];

        if (block.generation == handle.generation)
            return cast(PtrType!T) block.memory.ptr;

        return null;
    }

    /**
    Tests if the handle is currently valid.

    Params:
        handle = The handle to test
    
    Returns: `yes` if the handle is valid, `no` otherwise.
    */
    Ternary owns(Handle handle) {
        return Ternary(handle.index < _pool.length && _pool[handle.index].generation == handle.generation);
    }

    /**
    Allocates a new object and initializes it in place.

    Params:
        args = Arguments for the object's constructor. May be empty.
    
    Returns: A handle to the object if allocation was successful, or Handle()
             if it failed.
    */
    Handle allocate(Args...)(auto scope ref Args args) {
        if (_freelist_index >= _num_blocks)
            return Handle();
        
        const index = _freelist_index;
        auto block = &_pool[index];

        _freelist_index = block.next_index;

        static if (args.length > 0)
            emplace_obj(cast(PtrType!T) block.memory.ptr, args);

        return Handle(index, block.generation);
    }

    /**
    Deallocates the object identified by `handle` and returns it to the pool.

    Note: It is an error to call this function with an invalid handle.

    Params:
        handle = The handle of the object to deallocate.

    Returns: `true` if the object was successfully returned to the allocator,
             `false` otherwise.
    */
    bool deallocate(Handle handle) {
        assert(owns(handle) == Ternary.yes);

        if (handle == Handle())
            return true;
        
        auto block = &_pool[handle.index];
        block.generation++;

        block.next_index = _freelist_index;
        _freelist_index = handle.index;

        return true;
    }

private:
    struct _Block {
        uint generation;

        union {
            void[object_size!T] memory;
            uint next_index;
        }

        @disable this(this);
    }

    Allocator _base_allocator;
    size_t _num_blocks;
    _Block[] _pool;
    uint _freelist_index;
}

unittest {
    import flare.core.memory.stack: VirtualStackAllocator;
    import core.exception: AssertError;

    enum num_objects = 8;

    auto allocator = new AllocatorApi!VirtualStackAllocator(4.kib);
    auto pool = WeakObjectPool!ulong(allocator, num_objects);

    pool.Handle[num_objects] handles;
    foreach (ref handle; handles) {
        handle = pool.allocate();
        assert(pool.owns(handle) == Ternary.yes);
        assert(handle);
    }

    assert(pool.get(handles[0]));

    assert(!pool.allocate());

    pool.deallocate(handles[0]);
    assert(pool.owns(handles[0]) == Ternary.no);


    bool had_error;
    try
        pool.get(handles[0]);
    catch (AssertError e)
        had_error = true;
    assert(had_error);


    const h1 = pool.allocate();
    assert(handles[0] != h1);

    assert(!pool.allocate());
}
