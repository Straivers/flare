module flare.core.memory.allocators.arena;

struct Arena {
    import flare.core.math.util : round_to_next;
    import flare.core.memory.common : align_pointer, default_alignment, is_sub_slice_of, Ternary;

public nothrow:
    this(void[] memory, size_t alignment = default_alignment) {
        _start = align_pointer(memory.ptr, alignment);
        _alignment = alignment;

        _top = _start;
        _end = _start + memory.length;
    }

    @disable this(this);

    size_t alignment() const {
        return _alignment;
    }

    Ternary owns(void[] memory) const {
        if (memory == [] || memory.is_sub_slice_of(_start[0 .. _top - _start]))
            return Ternary.yes;
        return Ternary.no;
    }

    void[] managed_memory() {
        return _start[0 .. _end - _start];
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

    bool deallocate(ref void[] memory) in (owns(memory) == Ternary.yes) {
        if (memory is null)
            return true;

        const alloc_size = get_optimal_alloc_size(memory.length);

        if (memory.ptr + alloc_size == _top) {
            _top -= alloc_size;
            memory = null;
            return true;
        }

        return false;
    }

    bool resize(ref void[] memory, size_t size) in (owns(memory) == Ternary.yes) {
        if (memory == null || size == 0)
            return false;

        // If the new size fits in the old allocation
        if (get_optimal_alloc_size(size) <= get_optimal_alloc_size(memory.length)) {
            memory = memory.ptr[0 .. size];
            return true;
        }

        return false;
    }

    bool reallocate(ref void[] memory, size_t new_size) in (owns(memory) == Ternary.yes) {
        if (new_size == 0 && deallocate(memory)) {
            memory = null;
            return true;
        }

        if (resize(memory, new_size))
            return true;

        if (auto new_memory = allocate(new_size)) {
            new_memory[0 .. memory.length] = memory;
            memory = new_memory;
            return true;
        }

        return false;
    }

private:
    size_t _alignment;
    void* _top, _start, _end;
}

unittest {
    import flare.core.memory.allocators.allocator: test_allocate_api, test_reallocate_api, test_resize_api;

    auto arena = Arena(new void[](4 * 1024));

    test_allocate_api(arena);
    test_reallocate_api(arena);
    test_resize_api(arena);

    {
        // Fixed-order deallocation
        auto m1 = arena.allocate(10);
        auto m2 = arena.allocate(20);
        auto m3 = arena.allocate(30);

        assert(!arena.deallocate(m1));
        assert(!arena.deallocate(m2));

        assert(arena.deallocate(m3));
        assert(!arena.deallocate(m1));
        
        assert(arena.deallocate(m2));
        assert(arena.deallocate(m1));
    }
}
