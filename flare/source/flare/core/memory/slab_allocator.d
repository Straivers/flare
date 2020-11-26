module flare.core.memory.slab_allocator;

import flare.core.memory.api: Allocator;

struct SlabAllocator {
    import flare.core.memory.base: align_pointer;

nothrow public:
    this(void[] memory) {
        _start = _top = memory.ptr;
        _end = _start + memory.length;
    }

    void[] range() {
        return cast(void[]) _start[0 .. _end - _start];
    }

    size_t bytes_free() {
        return _end - _top;
    }

    void[] alloc(size_t size, size_t alignment) {
        if (_top + size >= _end)
            return [];
        
        _top = align_pointer(_top, alignment);
        scope (exit) _top += size;
        return _top[0 .. size];
    }

    void free(void[] memory) {
        // no-op
    }

private:
    const void* _start, _end;
    void* _top;
}
