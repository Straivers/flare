module flare.core.handle;

import flare.core.math.util : min, max;
import flare.core.memory;
import flare.core.memory.allocators.common;
import std.traits : hasElaborateDestructor;

align(4) struct Handle32(string name) {
    void[4] value;

    T opCast(T : bool)() const {
        return value == value.init;
    }

    uint int_value() const {
        return *(cast(uint*) &value[0]);
    }
}

static assert(HandlePool!(uint, "", 64).max_slots == 64);
static assert(HandlePool!(uint, "", 64).num_generations == 67108864);

static assert(HandlePool!(void, "", 12).max_slots == 16);
static assert(HandlePool!(void, "", uint.max).num_generations == 1);

/*
A HandlePool provides a fixed number of slots from which objects may be
allocated. Each object is given a handle that is unique to that object that will
become invalid when the object is returned to the pool. This handle may be
compared with other handles from the same pool for equality only. Each
HandlePool has a name which is used to distinguish handles created from
different pools, otherwise two pools in different places would produce handles
that may be indistinguishable from each other.

The slots in the pool each have a fixed number of times they can be reused,
called its generation. Once its generation is saturated, the slot becomes
unusable. This limit is called `num_generations`, and depends on the number of
slots the pool was created with. The more slots, the fewer the generations per
slot.

Params:

    SlotData    = The type of data that is to be stored in each slot. Set to
                  'void' to store no per-slot data.

    handle_name = A unique name that distinguishes pools from each other so
                  that handles from different pools are unique.

    min_slots   = The minimum number of slots that the pool should have. Affects
                  the number of supported generations.
*/
struct HandlePool(SlotData, string handle_name = __MODULE__, size_t min_slots = 2 ^^ 20 - 1)
if ((0 < min_slots && min_slots <= (1uL << 32)) && (is(SlotData == void) || object_size!SlotData > 0)) {
    import std.bitmanip : bitfields;

    alias Handle = Handle32!handle_name;

    // Subtract 1 from min_slots because we index from 0.
    enum max_slots = 2 ^^ bits_to_store(min_slots - 1);
    enum num_generations = 2 ^^ ((8 * uint.sizeof) - bits_to_store(min_slots - 1));

    private enum max_index = max_slots - 1;
    private enum max_generation = num_generations - 1;

public:
    /**
    Initializes the pool with a block of memory. The pool will create as many
    slots as will fit within the block. Ownership of the memory remains with the
    caller of this constructor, but the caller must not modify this memory until
    the pool has reached the end of its lifetime.
    */
    this(void[] memory) {
        auto base = memory.ptr.align_pointer(_Slot.alignof);
        const count = (memory.length - (base - memory.ptr)) / _Slot.sizeof;
        this((cast(_Slot*) base)[0 .. min(max_slots, count)]);
    }

    /**
    Initializes the pool with an allocator. At least `min_slots` will be
    allocated. Ownership of the memory is held within the pool, and will be
    returned to the allocator when the pool is destroyed.
    */
    this(Allocator allocator) {
        _base_allocator = allocator;
        const count = _base_allocator.get_optimal_alloc_size(_Slot.sizeof * min_slots) / _Slot.sizeof;
        this(_base_allocator.make_array!_Slot(min(max_slots, count)));
    }

    private this(_Slot[] slots) {
        _slots = slots;

        static if (num_generations > 1)
            _deallocate_slot(_allocate_slot());
        else
            _top++;
    }

    @disable this(this);

    ~this() {
        if (_base_allocator)
            _base_allocator.dispose(_slots);
    }

    size_t num_slots() const {
        return _slots.length;
    }

    size_t num_allocated() const {
        return _num_allocated;
    }

    Ternary owns(Handle handle) const {
        const _handle = _Handle(handle);

        if (_handle.index_or_next < _top) {
            static if (num_generations > 1)
                return Ternary(_slots[_handle.index_or_next].handle == _handle);
            else
                return Ternary(_slots[_handle.index_or_next].handle != _Handle());
        }

        return Ternary.no;
    }

    static if (!is(SlotData == void)) {
        inout(PtrType!SlotData) get(Handle handle) inout {
            assert(owns(handle) == Ternary.yes);
            const _handle = _Handle(handle);
            return cast(inout) _slots[_handle.index_or_next].slot_data;
        }
    }

    Handle make(Args...)(Args args) {
        if (auto slot = _allocate_slot()) {
            static if (!is(SlotData == void))
                emplace(slot.slot_data, args);

            _num_allocated++;
            return slot.handle.handle;
        }
        return Handle();
    }

    void dispose(Handle handle) {
        const _handle = _Handle(handle);
        auto slot = &_slots[_handle.index_or_next];

        assert(slot.handle == _handle, "Detected destruction of invalid handle.");

        static if (hasElaborateDestructor!SlotData) {
            static if (is(SlotData == class) || is(SlotData == interface))
                destroy(slot.data_ptr);
            else
                destroy(*slot.data_ptr);
        }

        _num_allocated--;
        _deallocate_slot(slot);
    }

private:
    union _Handle {
        Handle handle;
        struct {
            mixin(bitfields!(
                    uint, "index_or_next", bits_to_store(max_index),
                    uint, "generation", bits_to_store(max_generation)));
        }
    }

    align(max(object_alignment!SlotData, Handle.alignof)) struct _Slot {
        _Handle handle;

        static if (!is(SlotData == void)) {
            void[object_size!SlotData] data;

            auto slot_data() inout {
                return cast(PtrType!SlotData) data.ptr;
            }
        }
    }

    _Slot* _allocate_slot() {
        if (_freelist_length > 0) {
            auto slot = &_slots[_first_free_slot];
            const slot_index = _first_free_slot;

            _first_free_slot = slot.handle.index_or_next;
            slot.handle.index_or_next = slot_index;
            _freelist_length--;

            return slot;
        }

        if (_top < _slots.length) {
            auto slot = &_slots[_top];
            slot.handle.index_or_next = _top;

            static if (num_generations > 1)
                slot.handle.generation = 0; // For non-zeroing `_base_allocator`s

            _top++;
            return slot;
        }

        return null;
    }

    void _deallocate_slot(_Slot* slot) {
        // If each slot supports multiple generations
        static if (num_generations > 1) {
            if (slot.handle.generation != max_generation) {
                // Invalidate old handles
                slot.handle.generation = slot.handle.generation + 1;

                // Add slot to freelist
                const slot_index = slot.handle.index_or_next;
                slot.handle.index_or_next = _first_free_slot;
                _first_free_slot = slot_index;

                // Record new element of freelist
                _freelist_length++;
                return;
            }
        }

        // Invalidate handle of consumed slot to catch use-after-free.
        slot.handle = _Handle();
    }

    Allocator _base_allocator;
    _Slot[] _slots;

    uint _num_allocated;

    uint _top;
    uint _first_free_slot;
    uint _freelist_length;
}

unittest {
    auto pool = HandlePool!uint(new void[](4.kib));

    static assert(pool.max_slots == 1 << 20);
    static assert(pool.num_generations == 4 * (1 << 10));
    
    assert(pool.num_slots == 512);

    assert(pool.owns(pool.Handle()) == Ternary.no);

    const a1 = pool.make(1);
    assert(pool.owns(a1) == Ternary.yes);
    assert(*pool.get(a1) == 1);

    {
        const h1 = pool._Handle(a1);
        assert(h1.index_or_next == 0);
        assert(h1.generation == 1);
    }

    pool.dispose(a1);
    assert(pool.owns(a1) == Ternary.no);

    foreach (i; 0 .. 4093)
        pool.dispose(pool.make());
    
    const a2 = pool.make(100);
    assert(*pool.get(a2) == 100);

    {
        const h2 = pool._Handle(a2);
        assert(h2.index_or_next == 0);
        assert(h2.generation == 4095);
    }

    pool.dispose(a2);

    const a3 = pool.make(0);

    {
        const h3 = pool._Handle(a3);
        assert(h3.index_or_next == 1);
        assert(h3.generation == 0);
    }
}

unittest {
    const pool = HandlePool!(uint, "", 64)(new void[](4.kib));
    assert(pool.max_slots == 64);
    assert(pool.num_slots == 64);
}

unittest {
    auto pool = HandlePool!(void, "", 1UL << 32)(new void[](4.kib));
    assert(pool.max_slots == 1UL << 32);
    assert(pool.num_generations == 1);

    assert(pool.owns(pool.Handle()) == Ternary.no);

    const a1 = pool.make();
    assert(pool.owns(a1) == Ternary.yes);
    pool.dispose(a1);
    assert(pool.owns(a1) == Ternary.no);

    {
        const h1 = pool._Handle(pool.make());
        assert(h1.index_or_next == 2);
        assert(h1.generation == 0);
    }
}
