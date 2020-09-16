module flare.core.memory.static_allocator;

import flare.core.memory.measures;
import flare.core.memory.base;

struct StaticAllocator(size_t size) {
    @disable this(this);

    void[] alloc(size_t bytes, size_t alignment) {
        const padding = bytes % alignment;
        const total_size = padding + bytes;

        if (total_size + next_byte_position > memory.length)
            assert(false, "Static Allocator Out of Memory");

        const start = next_byte_position + padding;
        const end = start + bytes;

        auto mem = memory[start .. end];
        next_byte_position = end;
        return mem;
    }

    PtrType!T alloc(T, Args...)(Args args) {
        auto mem = alloc(object_size!T, object_alignment!T);
        return emplace_obj!T(mem, args);
    }

    T[] alloc_array(T)(size_t length) {
        auto mem = alloc(length * T.sizeof, object_alignment!T);
        return cast(T[]) mem;
    }

    size_t next_byte_position;
    void[size] memory;
}

StaticAllocator!size scoped_mem(size_t size)() {
    return StaticAllocator!size();
}
