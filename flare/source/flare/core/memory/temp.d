module flare.core.memory.temp;

import flare.core.memory.buddy_allocator: BuddyAllocator;
import flare.core.memory.base: emplace_obj, align_pointer;

public import std.typecons: scoped;
public import flare.core.memory.api: Allocator, kib, mib, gib;

enum local_temp_allocator_size = 1.mib;

nothrow:

final class TempAllocator : Allocator {
    this(size_t size) {
        auto memory = tmp_allocator.alloc(size);
        assert(memory, "Out of Temporary Memory.");

        _start = _top = memory.ptr;
        _end = _start + size;
    }

    ~this() {
        if (_start && _end)
            tmp_allocator.free(cast(void[]) _start[0 .. _end - _start]);
    }

    size_t bytes_free() {
        return _end - _top;
    }

    override void[] alloc_raw(size_t size, size_t alignment) {
        if (_top + size >= _end)
            return [];

        _top = align_pointer(_top, alignment);
        scope (exit) _top += size;
        return _top[0 .. size];
    }

    override void free_raw(void[] memory) {
        // no-op
    }

private:
    const void* _start, _end;
    void* _top;
}

private:

BuddyAllocator tmp_allocator;

static this() {
    tmp_allocator = BuddyAllocator(local_temp_allocator_size);
}
