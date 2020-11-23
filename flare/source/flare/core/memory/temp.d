module flare.core.memory.temp;

public import flare.core.memory.api: kib, mib, gib;

struct TempAllocator {
    import flare.core.memory.slab_allocator : SlabAllocator;
    import flare.core.memory.api: Allocator;
    import std.typecons : scoped;

    enum default_size = 16.kib;

nothrow public:
    typeof(scoped!SlabAllocator([])) base;
    alias base this;

    Allocator source;

    this(Allocator source, size_t size = default_size) {
        this.source = source;
        this(source.alloc_raw(size, 8));
    }

    this(void[] memory) {
        try
            base = scoped!SlabAllocator(memory);
        catch (Exception e)
            assert(0, "Nothrow violation");
    }

    @disable this(this);

    ~this() {
        if (source)
            source.free_raw(base.range);
    }
}
