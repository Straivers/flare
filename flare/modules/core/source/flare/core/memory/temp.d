module flare.core.memory.temp;

import flare.core.memory.allocator;
import flare.core.memory.common;

enum default_temp_arena_size = 16.kib;

auto temp_arena(Allocator allocator, size_t size = default_temp_arena_size) nothrow {
    return ScopedArena(allocator, size);
}

struct ScopedArena {
    import flare.core.memory.stack : StackAllocator;
    import std.typecons : scoped;

    final class Impl : Allocator {
        StackAllocator stack;

        this(void[] memory) nothrow {
            stack = StackAllocator(memory);
        }

        ~this() nothrow {
            destroy(stack);
        }

        override size_t alignment() const {
            return stack.alignment();
        }

        override Ternary owns(void[] memory) const {
            return stack.owns(memory);
        }

        override size_t get_optimal_alloc_size(size_t size) const {
            return stack.get_optimal_alloc_size(size);
        }

        override void[] allocate(size_t size) {
            return stack.allocate(size);
        }

        override bool deallocate(ref void[] memory) {
            return stack.deallocate(memory);
        }

        override bool reallocate(ref void[] memory, size_t new_size) {
            return stack.reallocate(memory, new_size);
        }

        override bool resize(ref void[] memory, size_t new_size) {
            return stack.resize(memory, new_size);
        }

    }

nothrow public:
    Allocator source;
    typeof(scoped!Impl([])) base;
    alias base this;

    this(Allocator source, size_t size) {
        this.source = source;
        base = scoped!Impl(source.allocate(size));
    }

    @disable this(this);

    ~this() {
        auto mem = stack.managed_memory;
        source.deallocate(mem);
    }
}

unittest {
    import flare.core.memory.stack: VirtualStackAllocator;

    auto base = new AllocatorApi!VirtualStackAllocator(32.kib);
    auto temp = temp_arena(base);

    test_allocate_api(temp);
    test_reallocate_api(temp);
    test_resize_api(temp);
}
