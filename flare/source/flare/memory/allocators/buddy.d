module flare.memory.allocators.buddy;

import flare.math.util : ilog2, is_power_of_two;
import flare.memory.allocators.allocator : Allocator;
import flare.memory.allocators.common;
import flare.util.bit_array;

enum min_chunk_size = 128;
enum min_allocator_size = 2 * min_chunk_size;

// TODO: Allow for variable min_chunk_sizes depending on size of managed region
// TODO: Allow for extra large virtual allocations with progressive page commit

struct BuddyAllocator {
public nothrow:
    this(Allocator base_allocator, size_t size) {
        _base_allocator = base_allocator;
        this(_base_allocator.allocate(size));
    }

    this(void[] memory) {
        assert(is_power_of_two(memory.length) && memory.length >= min_allocator_size);
        assert((cast(size_t) memory.ptr) % alignment == 0);

        _memory_start = memory.ptr;
        _memory_end = memory.ptr + memory.length;

        _max_order = Order.of(memory.length);

        _bitmap = BitArray(cast(ubyte[]) memory[0 .. BitArray.required_size_for(_max_order.tree_size / 2)]);

        foreach (ref list; _free_lists[0 .. _max_order + 1])
            list.next = list.prev = &list;

        mark_region(_memory_start + _bitmap.array.length);
    }

    @disable this(this);

    ~this() {
        if (_base_allocator) {
            auto mem = _memory_start[0 .. _memory_end - _memory_start];
            _base_allocator.deallocate(mem);
        }
    }

    size_t alignment() const {
        return default_alignment;
    }

    Ternary owns(void[] memory) const {
        if (memory == null || (_memory_start <= memory.ptr && memory.ptr + memory.length <= _memory_end))
            return Ternary.yes;
        return Ternary.no;
    }

    size_t get_optimal_alloc_size(size_t size) const {
        return size == 0 ? 0 : Order.of(size).chunk_size;
    }

    void[] allocate(size_t size) {
        assert(_max_order.chunk_size > size);

        if (size == 0)
            return [];

        if (auto chunk = get_chunk(Order.of(size)))
            return chunk[0 .. size];

        return [];
    }

    bool deallocate(ref void[] bytes) {
        auto value = _deallocate(bytes);
        bytes = null;
        return value;
    }

    bool resize(ref void[] memory, size_t new_size) {
        if (memory == null || new_size == 0)
            return false;

        assert(owns(memory) == Ternary.yes);

        const order = Order.of(memory.length);
        assert(order.is_aligned(memory.ptr - _memory_start));

        if (new_size <= order.chunk_size) {
            const new_order = Order.of(new_size);

            auto chunk = memory.ptr[0 .. order.chunk_size];

            if (new_order < order) {
                /*
                From:
                2 [       x       ]
                1 [   _   |   _   ]
                0 [ _ | _ | _ | _ ]

                To:
                2 [       x       ]
                1 [   x   |   _   ]
                0 [ x | _ | _ | _ ]
                */

                for (auto o = Order(order - 1); o >= new_order; o = Order(o - 1)) {
                    auto left = chunk[0 .. o.chunk_size];
                    auto right = chunk[o.chunk_size .. $];

                    toggle_bit(o, chunk.ptr);
                    add_chunk(o, right.ptr);
                    chunk = left;
                }
            }

            memory = memory.ptr[0 .. new_size];
            return true;
        }

        return false;
    }

    bool reallocate(ref void[] memory, size_t new_size) {
        if (resize(memory, new_size))
            return true;
        
        if (new_size == 0) {
            deallocate(memory);
            memory = null;
            return true;
        }

        if (auto new_memory = allocate(new_size)) {
            new_memory[0 .. memory.length] = memory;
            memory = new_memory;
            return true;
        }

        return false;
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

            // add last chunk to deallocate list for that order if it is not the start of a larger block
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

    Larger orders means larger chunk sizes.
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
    
    bool _deallocate(void[] bytes) {
        assert(bytes == [] || owns(bytes) == Ternary.yes);
        import std.algorithm: min;

        if (bytes == [])
            return true;

        const order = Order.of(bytes.length);

        assert(order.is_aligned(bytes.ptr - _memory_start));
        const index = order.index_of(bytes.ptr - _memory_start);

        if (toggle_bit(order, bytes.ptr)) {
            add_chunk(order, bytes.ptr);
        }
        else {
            auto buddy = bytes.ptr + (index % 2 ? -order.chunk_size : order.chunk_size);
            remove_chunk(order, buddy);
            _deallocate(min(buddy, bytes.ptr)[0 .. Order(order + 1).chunk_size]);
        }

        return true;
    }

    Allocator _base_allocator;

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

    /// The index of the chunk starting at byte_offset as if the entire span of
    /// memory were an array of block of size Order.chunk_size.
    size_t index_of(size_t byte_offset) in (is_aligned(byte_offset)) {
        return byte_offset / chunk_size;
    }

    /// Checks that the byte offset could start a chunk in this order.
    bool is_aligned(size_t byte_offset) {
        return byte_offset % chunk_size == 0;
    }
}

unittest {
    //          1
    //    2           3
    //  4    5     6     7
    // 8 9 10 11 12 13 14 15
    // 8 reserved for bitmap
    auto mem = BuddyAllocator(new void[](1024));

    const a1 = mem.allocate(1);
    assert(a1.length == 1);
    assert(Order.of(a1.length).tree_index(mem._max_order, a1.ptr - mem._memory_start) == 9);

    const a2 = mem.allocate(128);
    assert(a2.length == 128);
    assert(Order.of(a2.length).tree_index(mem._max_order, a2.ptr - mem._memory_start) == 10);

    auto a3 = mem.allocate(16);
    assert(a3.length == 16);
    assert(Order.of(a3.length).tree_index(mem._max_order, a3.ptr - mem._memory_start) == 11);

    auto a4 = mem.allocate(128);
    assert(a4.length == 128);
    assert(Order.of(a4.length).tree_index(mem._max_order, a4.ptr - mem._memory_start) == 12);

    const a5 = mem.allocate(200);
    assert(a5.length == 200);
    assert(Order.of(a5.length).tree_index(mem._max_order, a5.ptr - mem._memory_start) == 7);

    const f1 = mem.allocate(512);
    assert(f1.length == 0);

    auto a6 = mem.allocate(128);
    assert(a6.length == 128);
    assert(Order.of(a6.length).tree_index(mem._max_order, a6.ptr - mem._memory_start) == 13);

    const f2 = mem.allocate(0);
    assert(f2.length == 0);

    mem.deallocate(a3); // 11
    mem.deallocate(a4); // 12
    assert(mem.allocate(256) == []);

    mem.deallocate(a6); // 13
    const a7 = mem.allocate(129);
    assert(a7.length == 129);
    assert(Order.of(a7.length).tree_index(mem._max_order, a7.ptr - mem._memory_start) == 6);
}

unittest {
    import flare.memory.measures: kib, mib;

    auto mem = BuddyAllocator(new void[](256.mib));

    const a1 = mem.allocate(12.kib);
    assert(a1.length == 12.kib);

    const a2 = mem.allocate(300);
    assert(a2.length == 300);

    const a3 = mem.allocate(30.mib);
    assert(a3.length == 30.mib);
}

unittest {
    // Test that chunks are correctly added to free lists when allocator is
    // initialized. If a chunk's start could also start a chunk of the order
    // above it, it should be added to the parent's free list and not this one.
    // Failure to do so will cause a problem when the bitmap requires an even
    // number of chunks (the first free chunk is not of Order(0)) where the free
    // lists for Order(0) has the same values as Order(1).
    auto mem1 = BuddyAllocator(new void[](256 * 1024));
    assert(mem1.allocate(1) !is mem1.allocate(1));

    auto mem2 = BuddyAllocator(new void[](512 * 1024));
    assert(mem2.allocate(1) !is mem2.allocate(1));
    assert(mem2.allocate(300) !is mem2.allocate(300));
}

unittest {
    import flare.memory.allocators.allocator: test_allocate_api, test_reallocate_api, test_resize_api;

    auto allocator = BuddyAllocator(new void[](4 * 1024));

    assert(allocator.alignment == default_alignment);

    test_allocate_api(allocator);
    test_reallocate_api(allocator);
    test_resize_api(allocator);

    {
        // Resize test when new size is less than half of a block

        // Allocate all 512-byte aligned blocks except for a 1024-byte block
        const p1 = allocator.allocate(2048);
        assert(p1);
        const p2 = allocator.allocate(512);
        assert(p2);

        // Allocate testing block
        auto m1 = allocator.allocate(1024);
        assert(m1);

        // Check that no 512-aligned blocks are free
        assert(!allocator.allocate(1024));
        assert(!allocator.allocate(512));

        // Shrink 1024-byte block to 512 bytes
        allocator.resize(m1, m1.length / 2);

        // Ensure that the released 512-bytes are available for allocation
        const m2 = allocator.allocate(512);
        assert(m2);
    }
    {
        // Allocation/deallocation/allocation produces the same block
        auto m1 = allocator.allocate(1);
        const s = m1;
        allocator.deallocate(m1);
        const m2 = allocator.allocate(1);
        assert(s == m2);
    }
}
