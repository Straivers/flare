module flare.memory.allocators.pool;

import flare.memory.allocators.allocator;
import flare.memory.allocators.common;
import flare.memory.measures;

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
        assert(_num_blocks <= _Block.next_index.max);

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

        return memset(block, 0, size)[0 .. size];
    }

    bool deallocate(void[] memory) {
        return deallocate(memory);
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

    uint _freelist_index;
}

unittest {
    import flare.memory.allocators.allocator: test_allocate_api;
    
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
