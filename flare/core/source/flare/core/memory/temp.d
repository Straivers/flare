module flare.core.memory.temp;

public import flare.core.memory.api: kib, mib, gib;

struct TempAllocator {
    import flare.core.memory.slab_allocator : SlabAllocator;
    import flare.core.memory.api: Allocator;
    import std.typecons : scoped;

    enum default_size = 16.kib;

nothrow public:
    typeof(scoped!Impl([])) base;
    alias base this;

    Allocator source;

    this(Allocator source, size_t size = default_size) {
        this.source = source;
        this(source.alloc(size, 8));
    }

    this(void[] memory) {
        try
            base = scoped!Impl(memory);
        catch (Exception e)
            assert(0, "Nothrow violation");
    }

    @disable this(this);

    ~this() {
        if (source)
            source.free(base.slab.range);
    }

    size_t bytes_free() {
        return base.slab.bytes_free();
    }

private:
    final class Impl : Allocator {
        SlabAllocator slab;

        this(void[] memory) {
            slab = SlabAllocator(memory);
        }

        override void[] alloc(size_t size, size_t alignment) {
            auto result = slab.alloc(size, alignment);
            if (result.length != size)
                assert(0, "Temporary memory exhausted.");
            return result;
        }

        override void free(void[] memory) {
            slab.free(memory);
        }
    }
}
