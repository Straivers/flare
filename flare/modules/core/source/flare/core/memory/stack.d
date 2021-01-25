module flare.core.memory.stack;

import flare.core.memory.common;

struct StackAllocator {

public nothrow:
    this(void[] memory, size_t alignment = default_alignment) {
        _start = align_pointer(memory.ptr, alignment);
        _end = _start + memory.length;

        _top = _start;
        _alignment = alignment;
    }

    @disable this(this);

    ~this() {
        _start = _end = _top = null;
        _alignment = 0;
    }

    void[] managed_memory() {
        return _start[0 .. _end - _start];
    }

    size_t alignment() const {
        return _alignment;
    }

    Ternary owns(void[] memory) const {
        if (memory == null || _start <= memory.ptr && memory.ptr + memory.length <= _end)
            return Ternary.yes;
        return Ternary.no;
    }

    size_t get_optimal_alloc_size(size_t size) const {
        return round_to_next(size, alignment);
    }

    void[] allocate(size_t size) {
        const alloc_size = get_optimal_alloc_size(size);

        if (alloc_size > 0 && _top + alloc_size <= _end) {
            auto mem = _top[0 .. size];
            _top += alloc_size;

            return mem;
        }

        return [];
    }

    bool deallocate(ref void[] memory) {
        assert(memory == [] || owns(memory) == Ternary.yes);

        if (memory is null)
            return true;

        const alloc_size = get_optimal_alloc_size(memory.length);

        if (_is_last_alloc(memory.ptr, alloc_size)) {
            _top -= alloc_size;
            memory = null;
            return true;
        }

        return false;
    }

    bool resize(ref void[] memory, size_t size) {
        if (memory == null || size == 0)
            return false;

        assert(owns(memory) == Ternary.yes);

        const alloc_size = get_optimal_alloc_size(memory.length);
        const new_alloc_size = get_optimal_alloc_size(size);

        // If we can use the alignment slack
        if (alloc_size == new_alloc_size) {
            memory = memory.ptr[0 .. size];
            return true;
        }

        // If we are shrimking the allocation
        if (new_alloc_size < alloc_size) {
            memory = memory.ptr[0 .. size];
            return true;
        }

        return false;
    }

    bool reallocate(ref void[] memory, size_t new_size) {
        if (resize(memory, new_size))
            return true;

        if (new_size == 0 && deallocate(memory)) {
            memory = null;
            return true;
        }

        assert(new_size > memory.length);
        if (auto new_memory = allocate(new_size)) {
            new_memory[0 .. memory.length] = memory;
            memory = new_memory;
            return true;
        }

        return false;
    }

private:
    bool _is_last_alloc(void* base, size_t size) {
        return base + size == _top;
    }

    void* _top;

    void* _start;
    void* _end;

    size_t _alignment;
}

unittest {
    import flare.core.memory.allocator;

    auto allocator = StackAllocator(new void[](4.kib));

    test_allocate_api(allocator);
    test_reallocate_api(allocator);
    test_resize_api(allocator);

    {
        // Fixed-order deallocation
        auto m1 = allocator.allocate(10);
        auto m2 = allocator.allocate(20);
        auto m3 = allocator.allocate(30);

        assert(!allocator.deallocate(m1));
        assert(!allocator.deallocate(m2));

        assert(allocator.deallocate(m3));
        assert(!allocator.deallocate(m1));
        
        assert(allocator.deallocate(m2));
        assert(allocator.deallocate(m1));
    }
}

/**
Fixed-size slab-style allocator backed by virtual memory. The allocator does not
currently return memory to the OS except upon destruction, but it is on the TODO
list.

For simplicity, all allocations are 8-byte aligned. Special, multiple-of-8-byte
alignments may be supported in the future (eg. for SIMD vectors).
*/
struct VirtualStackAllocator {
    import flare.core.memory.virtual : vm_alloc, vm_commit, vm_free, page_size;
    import std.algorithm : min;

    enum max_free_commited_pages = 4;

public nothrow:
    this(size_t size, size_t alignment = default_alignment) {
        _allocator = StackAllocator(vm_alloc(size), alignment);
        _first_uncomitted_page = _allocator._start;
        _alloc_pages();
    }

    @disable this(this);

    ~this() {
        vm_free(_allocator._start[0 .. _allocator._end - _allocator._start]);
        destroy(_allocator);
    }

    /// The default alignment used by the allocator.
    size_t alignment() const {
        return _allocator.alignment;
    }

    /// Checks if the allocator owns a given block of memory.
    Ternary owns(void[] memory) const {
        return _allocator.owns(memory);
    }

    /// Calculates and returns the optimal allocation size larger or equal to
    /// the given size to minimize internal fragmentation.
    size_t get_optimal_alloc_size(size_t size) const {
        return _allocator.get_optimal_alloc_size(size);
    }

    /// Allocates a block of memory with the default alignment. Returns `[]` if
    /// the allocation failed, or the size was 0.
    void[] allocate(size_t size) {
        auto memory = _allocator.allocate(size);

        if (memory.ptr + get_optimal_alloc_size(size) >= _first_uncomitted_page)
            _alloc_pages();

        return memory;
    }

    /// Deallocates a block of memory if supported by this allocator. Returns
    /// `true` if the deallocation was successful, `false` otherwise.
    bool deallocate(ref void[] memory) {
        // TODO: Free commited pages more than max_free_commited_pages
        return _allocator.deallocate(memory);
    }

    /// Attempts to resize a block of memory in-place. Returns `true` if
    /// successful, `false` otherwise. If size is 0, the block is deallocated
    /// and the memory block is set to null.
    ///
    /// The block of memory will not be modified if resizing fails.
    bool resize(ref void[] memory, size_t size) {
        return _allocator.resize(memory, size);
    }

    /// Reallocates a block of memory. Note that if resize is supported, the
    /// allocator _may_ use it instead internally.
    ///
    /// The block of memory will not be modified if reallocation fails.
    bool reallocate(ref void[] memory, size_t new_size) {
        if (resize(memory, new_size))
            return true;

        if (new_size == 0) {
            deallocate(memory);
            memory = null;
            return true;
        }

        // We need to use the VirtualSlab's allocate() to commit `new_memory` so
        // we can copy the contents of `memory` to it.
        if (auto new_memory = allocate(new_size)) {
            assert(new_memory.ptr + new_memory.length <= _first_uncomitted_page);

            new_memory[0 .. memory.length] = memory;
            memory = new_memory;
            return true;
        }

        return false;
    }

private:
    /// Allocates min(max_free_commited_pages * page_size, n_free_bytes) bytes
    void _alloc_pages() {
        const free_bytes = _allocator._end - _allocator._top;

        if (_first_uncomitted_page == _allocator._end)
            return;

        const n_bytes = min(max_free_commited_pages * page_size, free_bytes);
        vm_commit(_first_uncomitted_page[0 .. n_bytes]);

        _first_uncomitted_page += n_bytes;
    }

    void* _first_uncomitted_page;
    StackAllocator _allocator;
}

unittest {
    import flare.core.memory.allocator;

    auto allocator = VirtualStackAllocator(4.kib);

    test_allocate_api(allocator);
    test_reallocate_api(allocator);
    test_resize_api(allocator);

    {
        // Fixed-order deallocation
        auto m1 = allocator.allocate(10);
        auto m2 = allocator.allocate(20);
        auto m3 = allocator.allocate(30);

        assert(!allocator.deallocate(m1));
        assert(!allocator.deallocate(m2));

        assert(allocator.deallocate(m3));
        assert(!allocator.deallocate(m1));
        
        assert(allocator.deallocate(m2));
        assert(allocator.deallocate(m1));
    }
}
