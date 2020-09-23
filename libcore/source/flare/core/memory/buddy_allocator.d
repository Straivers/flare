module flare.core.memory.buddy_allocator;

import flare.core.memory.base: is_power_of_two, ilog2;

enum min_chunk_size = 128;
enum min_allocator_size = min_chunk_size * 2;

struct BuddyAllocator {
    import flare.core.memory.virtual: vm_alloc, vm_free;

public:
    this(size_t size) in (is_power_of_two(size) && size >= min_allocator_size) {
        _memory = vm_alloc(size)[0 .. size]; // slice for sizes less than a full page
        _max_order = Order(cast(uint) (ilog2(size) - ilog2(min_chunk_size)));
        _bitmap = BitArray(cast(ubyte[]) _memory[0 .. _max_order.n_total_chunks / 16 + (_max_order.n_total_chunks % 16 > 0)]);
        _free_areas.init_lists();

        mark_region_used(_bitmap.array.ptr + _bitmap.array.length);
    }

    ~this() {
        vm_free(_memory);
    }

    void[] alloc(size_t n_bytes) {
        if (n_bytes == 0)
            return [];

        const alloc_order = Order.of(n_bytes);

        assert(alloc_order <= _max_order);
        assert(alloc_order.chunk_size >= n_bytes);

        if (auto chunk = _free_areas.take(alloc_order)) {
            ~_bitmap[bit_index(alloc_order, _max_order, chunk.ptr - _memory.ptr)];
            return chunk[0 .. n_bytes];
        }

        if (alloc_order < _max_order) {
            auto chunk = split_chunk(Order(alloc_order + 1));
            if (chunk) {
                ~_bitmap[bit_index(alloc_order, _max_order, chunk.ptr - _memory.ptr)];
                return chunk[0 .. n_bytes];
            }
        }

        return [];
    }

    void free(void[] bytes) {
        const free_order = Order.of(bytes.length);
        auto chunk = bytes.ptr[0 .. free_order.chunk_size];
        const chunk_index = free_order.index_of(chunk.ptr - _memory.ptr);
        const block_index = block_index(free_order, _max_order, chunk.ptr - _memory.ptr);
        assert(_memory.ptr + (chunk_index * free_order.chunk_size) == chunk.ptr);

        ~_bitmap[block_index / 2];

        if (!_bitmap[block_index / 2]) {
            auto buddy_offset = chunk_index % 2 != 0 ? -1 : 1;
            auto buddy = _free_areas.remove(free_order, (_memory.ptr + (chunk_index + buddy_offset) * free_order.chunk_size)[0 .. free_order.chunk_size]);
            auto merged_start = buddy.ptr < chunk.ptr ? buddy.ptr : chunk.ptr;
            free(merged_start[0 .. free_order.chunk_size * 2]);
        }
        else {
            _free_areas.append(free_order, bytes);
        }
    }

private:
    void mark_region_used(void* first_free_byte) {
        assert(first_free_byte < _memory.ptr + _memory.length);

        foreach (i; 0 .. _max_order + 1) {
            auto order = Order(i);
            auto p = _memory.ptr;

            for (; p <= first_free_byte && first_free_byte <= p + order.chunk_size; p += order.chunk_size)
                ~_bitmap[bit_index(order, _max_order, p - _memory.ptr)];

            if (p < (_memory.ptr + _memory.length))
                _free_areas.append(order, p[0 .. order.chunk_size]);
        }
    }

    /// Splits a chunk of the order `order` and returns the left half.
    void[] split_chunk(Order order) {
        if (auto chunk = _free_areas.take(order)) {
            ~_bitmap[bit_index(order, _max_order, chunk.ptr - _memory.ptr)];
            _free_areas.append(Order(order - 1), split(chunk).right);
            return split(chunk).left;
        }

        if (order < _max_order) {
            auto chunk = split_chunk(Order(order.value + 1));

            if (chunk) {
                ~_bitmap[bit_index(order, _max_order, chunk.ptr - _memory.ptr)];
                _free_areas.append(Order(order - 1), split(chunk).right);
                return split(chunk).left;
            }
        }

        return [];
    }

    void[] _memory;
    Order _max_order;
    BitArray _bitmap;
    FreeLists _free_areas;
}

unittest {
    // 2 |          512          | 
    // 1 |    256    |    256    |
    // 0 | 128 | 128 | 128 | 128 |

    auto mem = BuddyAllocator(512);
    assert(mem._bitmap.array.length == 1);
    assert(mem._max_order == 2);

    assert(mem._bitmap.array[0] == 0b00000111);

    debug {
        assert(mem._free_areas._lengths[0 .. 3] == [1, 1, 0]);
        foreach (i; 3 .. max_orders)
            assert(mem._free_areas._lengths[i] == 0);
    }
}

unittest {
    // 3 |                      1024                     |
    // 2 |          512          |          512          |
    // 1 |    256    |    256    |    256    |    256    |
    // 0 | 128 | 128 | 128 | 128 | 128 | 128 | 128 | 128 |
    //      -    a1    a2    a3    a4    a5       a6

    auto mem = BuddyAllocator(1024);

    const a1 = mem.alloc(128);
    assert(a1.length == 128);
    assert(mem._free_areas._lengths[0 .. 4] == [0, 1, 1, 0]);
    assert(mem._bitmap.array[0] == 0b00000111);

    const a2 = mem.alloc(128);
    assert(a2.length == 128);
    assert(mem._free_areas._lengths[0 .. 4] == [1, 0, 1, 0]);
    assert(mem._bitmap.array[0] == 0b00100011);

    const a3 = mem.alloc(128);
    assert(a3.length == 128);
    assert(mem._free_areas._lengths[0 .. 4] == [0, 0, 1, 0]);

    const a4 = mem.alloc(128);
    assert(a4.length == 128);
    assert(mem._free_areas._lengths[0 .. 4] == [1, 1, 0, 0]);

    const f1 = mem.alloc(512);
    assert(f1.length == 0);

    const a5 = mem.alloc(128);
    assert(a5.length == 128);
    assert(mem._free_areas._lengths[0 .. 4] == [0, 1, 0, 0]);

    const a6 = mem.alloc(256);
    assert(a6.length == 256);
    assert(mem._free_areas._lengths[0 .. 4] == [0, 0, 0, 0]);

    const f2 = mem.alloc(0);
    assert(f2.length == 0);
}

unittest {
    // 2 |          512          | 
    // 1 |    256    |    256    |
    // 0 | 128 | 128 | 128 | 128 |

    auto mem = BuddyAllocator(512);

    const a1 = mem.alloc(64);
    mem.free(cast(void[]) a1);

    const a2 = mem.alloc(70);
    assert(a1.ptr == a2.ptr);
}

unittest {
    // 2 |          512          | 
    // 1 |    256    |    256    |
    // 0 | 128 | 128 | 128 | 128 |
    //      -    a1    a2

    auto mem = BuddyAllocator(512);

    const a1 = mem.alloc(10);
    const a2 = mem.alloc(10);

    assert(mem.alloc(200).length == 0);
    mem.free(cast(void[]) a2);
    assert(mem.alloc(200).length == 200);
}

unittest {
    auto mem = BuddyAllocator(8192);

    alias Chunk = void[];

    Chunk[63] chunks_63;
    foreach (i, ref void[] chunk; chunks_63)
        chunk = mem.alloc(i + 1);

    assert(mem.alloc(1) == []);

    foreach (i, ref void[] chunk; chunks_63)
        assert(chunk.length == i + 1);

    foreach (i, ref void[] chunk; chunks_63)
        mem.free(chunk);

    const chunk_3072 = mem.alloc(7000);
    assert(chunk_3072.length == 0);

    const chunk_2048 = mem.alloc(2048);
    assert(chunk_2048.length == 2048);

    const chunk_1024 = mem.alloc(1024);
    assert(chunk_1024.length == 1024);

    mem.free(cast(void[]) chunk_2048);

    const chunk_1024_1 = mem.alloc(1024);
    assert(chunk_1024_1.length == 1024);

    const chunk_1024_2 = mem.alloc(1024);
    assert(chunk_1024_2.length == 1024);
}

private:

enum max_orders = 32;

auto split(void[] chunk) {
    struct Split { void[] left, right; }
    return Split(chunk[0 .. chunk.length / 2], chunk[chunk.length / 2 .. $]);
}

struct Order {
    uint value;
    alias value this;

    static Order of(size_t n_bytes) {
        // log₂⌈n⌉, n is number of min_chunk_size chunks, rounded up
        const div = n_bytes / min_chunk_size;
        const rem = n_bytes % min_chunk_size;
        const num_min_chunks = cast(uint) div + (rem != 0);
        // const num_min_chunks = cast(uint) ceil(n_bytes / cast(real) min_chunk_size);
        auto base = Order(ilog2(num_min_chunks));
        assert(base.chunk_size >= min_chunk_size);

        return base;
    }

    /// The total number of chunks in this order, plus every order below it.
    size_t n_total_chunks() const {
        return 2 * n_min_chunks - 1;
    }

    /// Number of chunks of this order in `max_order`.
    size_t n_chunks_in(Order max_order) const in (max_order >= value) {
        return 2 ^^ (max_order.value - value);
    }

    /// The number of bytes per chunk in this order.
    size_t chunk_size() const { return n_min_chunks * min_chunk_size; }

    /// Number of min_chunk_size chunks per chunk in this order.
    size_t n_min_chunks() const { return 2 ^^ value; }

    size_t index_of(size_t offset) const {
        assert(offset % chunk_size == 0);
        return offset / chunk_size;
    }
}

unittest {
    auto o1 = Order(0);
    assert(o1.n_min_chunks == 1);
    assert(o1.chunk_size == 128);
    assert(o1.n_total_chunks == 1);
    assert(o1.n_chunks_in(Order(1)) == 2);
    assert(o1.n_chunks_in(Order(2)) == 4);
    assert(o1.n_chunks_in(Order(3)) == 8);

    auto o2 = Order(1);
    assert(o2.n_min_chunks == 2);
    assert(o2.n_total_chunks == 3);
    assert(o2.n_chunks_in(Order(2)) == 2);

    assert(Order.of(20) == 0);
    assert(Order.of(200) == 1);
}

struct FreeLists {
    void init_lists() {
        foreach (ref list; _free_lists) {
            list.next = &list;
            list.prev = &list;
        }
    }

    void append(Order order, void[] bytes) {
        (cast(Block*) bytes.ptr).insert_after(&_free_lists[order]);
        debug _lengths[order]++;
    }

    void[] take(Order order) {
        if (_free_lists[order].next == &_free_lists[order])
            return [];
        return remove_raw(order, _free_lists[order].next);
    }

    void[] remove(Order order, void[] chunk) {
        assert(order.chunk_size == chunk.length);

        return remove_raw(order, chunk.ptr);
    }

private:
    void[] remove_raw(Order order, void* ptr) {
        assert(() {
            for (auto p = _free_lists[order].next; p != &_free_lists[order]; p = p.next)
                if (p == ptr)
                    return true;
            return false;
        }());

        debug _lengths[order]--;
        return (cast(void*) (cast(Block*) ptr).remove())[0 .. order.chunk_size];
    }

    struct Block {
        Block* prev, next;

        bool empty() { return prev == next && prev == &this; }

        void insert_after(Block* other) {
            next = other.next;
            next.prev = &this;
            prev = other;
            prev.next = &this;
        }

        Block* remove() return {
            prev.next = next;
            next.prev = prev;
            return &this;
        }
    }

    Block[max_orders] _free_lists;
    debug size_t[max_orders] _lengths;
}

struct BitArray {
    ubyte[] array;

    bool opIndex(size_t bit) {
        const byte_index = bit / 8;
        return (array[byte_index] & (1 << (bit % 8))) != 0;
    }

    bool opIndexUnary(string op = "~")(size_t bit) {
        const byte_index = bit / 8;
        array[byte_index] ^= (1 << (bit % 8));
        return this[bit];
    }
}

unittest {
    auto array = BitArray([0]);

    assert(!array[0]);
    ~array[0];
    assert(array[0]);
    assert((array.array[0] & 1) != 0);
    assert((array.array[0] ^ 1) == 0);
    ~array[0];
    assert(!array[0]);

    assert(!array[7]);
    ~array[7];
    assert(array[7]);
    assert((array.array[0] & 1 << 7) != 0);
    assert((array.array[0] ^ 1 << 7) == 0);

    foreach (i; 0 .. 8)
        ~array[i];

    assert(array.array[0] == 127);
}

size_t block_index(Order order, Order max_order, size_t block_offset) {
    const block_index_in_order = block_offset / order.chunk_size;
    return 2 ^^ (max_order - order) + block_index_in_order;
}

size_t bit_index(Order order, Order max_order, size_t block_offset) {
    return block_index(order, max_order, block_offset) / 2;
}
