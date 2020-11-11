module flare.core.memory.buddy_allocator;

import flare.core.memory.base : is_power_of_two, ilog2, emplace_obj;
import flare.core.bitarray : BitArray;

enum min_chunk_size = 128;
enum min_allocator_size = 2 * min_chunk_size;

struct BuddyAllocator {
    import flare.core.memory.virtual: vm_alloc, vm_free;

nothrow:
    this(size_t size) {
        assert(is_power_of_two(size) && size >= min_allocator_size);

        auto memory = vm_alloc(size);
        _memory_start = memory.ptr;
        _memory_end = memory.ptr + memory.length;

        _max_order = Order.of(size);

        _bitmap = BitArray(cast(ubyte[]) memory[0 .. BitArray.required_size_for(_max_order.tree_size / 2)]);

        foreach (ref list; _free_lists[0 .. _max_order + 1])
            list.next = list.prev = &list;

        mark_region(_memory_start + _bitmap.array.length);
    }

    @disable this(this);

    ~this() {
        vm_free(_memory_start[0 .. _memory_end - _memory_start]);
    }

    void[] alloc(size_t size) {
        assert(_max_order.chunk_size > size);

        if (size == 0) {
            return [];
        }

        if (auto chunk = get_chunk(Order.of(size))) {
            return chunk[0 .. size];
        }

        return [];
    }

    void free(void[] bytes) {
        assert(_memory_start <= bytes.ptr && bytes.ptr + bytes.length <= _memory_end);
        import std.algorithm: min;

        const order = Order.of(bytes.length);
        assert(order.is_aligned(bytes.ptr - _memory_start));
        const index = order.index_of(bytes.ptr - _memory_start);

        if (toggle_bit(order, bytes.ptr)) {
            add_chunk(order, bytes.ptr);
        }
        else {
            auto buddy = bytes.ptr + (index % 2 ? -order.chunk_size : order.chunk_size);
            free(min(buddy, bytes.ptr)[0 .. Order(order + 1).chunk_size]);
        }
    }

private:
    void mark_region(void* first_free_byte) {
        assert(_memory_start <= first_free_byte && first_free_byte <= _memory_end);

        foreach (i; 0 .. _max_order + 1) {
            auto order = Order(i);
            auto p = _memory_start;

            // mark every used chunk
            for (; p < first_free_byte; p += order.chunk_size)
                toggle_bit(order, p);

            // add last chunk to free list for that order if it is not the start of a larger block
            if (p < _memory_end && !Order(order + 1).is_aligned(p - _memory_start))
                add_chunk(order, p);
        }
    }

    void add_chunk(Order order, void* chunk_ptr) {
        auto chunk = cast(Chunk*) chunk_ptr;
        assert(order.is_aligned(chunk_ptr - _memory_start));
        assert(!_free_lists[order].owns_chunk(chunk));

        chunk.insert_after(&_free_lists[order]);
    }

    /**
     Retrieves a chunk of `order` size, splitting larger chunks if necessary. If
     no larger chunks are available, returns the empty array.
     */
    void[] get_chunk(Order order) {
        // Add 1 to the order during the test to avoid checking the root. It is
        // always in use because we store the bitmap in the same place.
        if (_free_lists[order].is_empty && order + 1 < _max_order) {
            const next_order = Order(order + 1);
            if (auto chunk = get_chunk(next_order)) {
                add_chunk(Order(order), &chunk[order.chunk_size]);
                add_chunk(Order(order), &chunk[0]);
            }
        }

        if (_free_lists[order].is_empty) {
            return [];
        }

        auto chunk = remove_chunk(order, _free_lists[order].next);
        toggle_bit(order, chunk.ptr);
        return chunk;
    }

    /**
     Removes the chunk pointed to by `chunk_ptr` from the the order `order`.
     This function assumes that the chunk is part of the order, and will panic
     if it is not.
     */
    void[] remove_chunk(Order order, void* chunk_ptr) {
        auto chunk = cast(Chunk*) chunk_ptr;
        assert(order.is_aligned(chunk_ptr - _memory_start));
        assert(_free_lists[order].owns_chunk(chunk));

        return (cast(void*) chunk.remove_self())[0 .. order.chunk_size];
    }

    bool toggle_bit(Order order, void* chunk_ptr) {
        assert(order.is_aligned(chunk_ptr - _memory_start));
        return ~_bitmap[order.tree_index(_max_order, chunk_ptr - _memory_start) / 2];
    }

    void* _memory_start, _memory_end;
    BitArray _bitmap;

    Chunk[max_orders] _free_lists;
    Order _max_order;
}

private:

enum max_orders = 32;

struct Chunk {
    Chunk* prev, next;

nothrow:
    /// Returns `true` if the chunk's prev and next pointers point to itself.
    bool is_empty() { return prev == &this && next == &this; }

    bool owns_chunk(Chunk* ptr) {
        for (auto p = next; p != &this; p = p.next)
            if (p == ptr)
                return true;
        return false;
    }

    /// Inserts this chunk after `chunk`.
    void insert_after(Chunk* prev) {
        this.prev = prev;       // [ ] <- [ ]    [ ]
        this.next = prev.next;  // [ ]    [ ] -> [ ]
        prev.next = &this;      // [ ] -> [ ]    [ ]
        next.prev = &this;      // [ ]    [ ] <- [ ]
    }

    /// Removes this chunk from the list.
    Chunk* remove_self() return {
        assert(next !is &this && prev !is &this);
        prev.next = next;      // [ ] -- [ ] -> [ ]
        next.prev = prev;      // [ ] <- [ ] -- [ ]
        return &this;
    }
}

struct Order {
    uint value;
    alias value this;

const nothrow:
    static of(size_t size) {
        // log₂⌈size/min_size⌉
        const div = size / min_chunk_size;
        const rem = size % min_chunk_size;
        return Order(cast(uint) ilog2(div + (rem != 0)));
    }

    /// The size of the tree with a node of this order as the root.
    size_t tree_size() { return 2 * (2 ^^ value) - 1; }

    size_t tree_index(Order max, size_t offset) {
        return 2 ^^ (max - this) + index_of(offset);
    }

    /// The size of a single chunk in bytes.
    size_t chunk_size() { return 2 ^^ value * min_chunk_size; }

    /// The index of the chunk starting at offset.
    size_t index_of(size_t offset) in (is_aligned(offset)) {
        return offset / chunk_size;
    }

    bool is_aligned(size_t offset) {
        return offset % chunk_size == 0;
    }
}

unittest {
    //          1
    //    2           3
    //  4    5     6     7
    // 8 9 10 11 12 13 14 15
    // 8 reserved for bitmap
    auto mem = BuddyAllocator(1024);

    const a1 = mem.alloc(1);
    assert(a1.length == 1);
    assert(Order.of(a1.length).tree_index(mem._max_order, a1.ptr - mem._memory_start) == 9);

    const a2 = mem.alloc(128);
    assert(a2.length == 128);
    assert(Order.of(a2.length).tree_index(mem._max_order, a2.ptr - mem._memory_start) == 10);

    const a3 = mem.alloc(16);
    assert(a3.length == 16);
    assert(Order.of(a3.length).tree_index(mem._max_order, a3.ptr - mem._memory_start) == 11);

    const a4 = mem.alloc(128);
    assert(a4.length == 128);
    assert(Order.of(a4.length).tree_index(mem._max_order, a4.ptr - mem._memory_start) == 12);

    const a5 = mem.alloc(200);
    assert(a5.length == 200);
    assert(Order.of(a5.length).tree_index(mem._max_order, a5.ptr - mem._memory_start) == 7);

    const f1 = mem.alloc(512);
    assert(f1.length == 0);

    const a6 = mem.alloc(128);
    assert(a6.length == 128);
    assert(Order.of(a6.length).tree_index(mem._max_order, a6.ptr - mem._memory_start) == 13);

    const f2 = mem.alloc(0);
    assert(f2.length == 0);

    mem.free(cast(void[]) a3); // 11
    mem.free(cast(void[]) a4); // 12
    assert(mem.alloc(256) == []);

    mem.free(cast(void[]) a6); // 13
    const a7 = mem.alloc(129);
    assert(a7.length == 129);
    assert(Order.of(a7.length).tree_index(mem._max_order, a7.ptr - mem._memory_start) == 6);
}

unittest {
    import flare.core.memory.measures: kib, mib;

    auto mem = BuddyAllocator(256.mib);

    const a1 = mem.alloc(12.kib);
    assert(a1.length == 12.kib);

    const a2 = mem.alloc(300);
    assert(a2.length == 300);

    const a3 = mem.alloc(30.mib);
    assert(a3.length == 30.mib);
}

unittest {
    import flare.core.memory.measures: kib;

    //    Test that chunks are correctly added to free lists when allocator is
    // initialized. If a chunk's start could also start a chunk of the order
    // above it, it should be added to the parent's free list and not this one.
    // Failure to do so will cause a problem when the bitmap requires an even
    // number of chunks (the first free chunk is not of Order(0)) where the free
    // lists for Order(0) has the same values as Order(1).
    auto mem1 = BuddyAllocator(256.kib);
    assert(mem1.alloc(1) !is mem1.alloc(1));

    auto mem2 = BuddyAllocator(512.kib);
    assert(mem2.alloc(1) !is mem2.alloc(1));
    assert(mem2.alloc(300) !is mem2.alloc(300));
}
