module flare.core.handle;

align(4) struct Handle32(string name) {
    void[4] value;

    T opCast(T : bool)() const {
        return *(cast(uint*)&value[0]) == 0;
    }
}

static assert(HandlePool!(uint, "", 64).num_slots == 64);
static assert(HandlePool!(uint, "", 64).num_generations == 67108864);

static assert(HandlePool!(uint, "", 12).num_slots == 16);
static assert(HandlePool!(uint, "", uint.max).num_generations == 1);

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
struct HandlePool(SlotData, string handle_name = __MODULE__, uint min_slots = 2 ^^ 20 - 1) {
    import flare.core.math.util : max;
    import flare.core.memory.allocators.allocator : Allocator, dispose, make_array;
    import flare.core.memory.common : PtrType, Ternary, align_pointer;
    import flare.core.memory.measures : bits_to_store, object_alignment, object_size;
    import std.bitmanip : bitfields;
    import std.traits : hasElaborateDestructor;

    alias Handle = Handle32!handle_name;

    // Subtract 1 from min_slots because we index from 0.
    enum num_slots = 2 ^^ bits_to_store(min_slots - 1);
    enum num_generations = 2 ^^ ((8 * uint.sizeof) - bits_to_store(min_slots - 1));

    private enum max_index = num_slots - 1;
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
        auto count = (memory.length - (base - memory.ptr)) / _Slot.sizeof;
        _slots = (cast(_Slot*) base)[0 .. count];

        _reserve_null_handle();
    }

    /**
    Initializes the pool with an allocator and the minimum number of slots to
    create. If the allocator's `get_optimal_alloc_size()` allows more slots, it
    will create them provided that it does not reduce `max_generations`.
    Ownership of the memory is held within the pool, and will be returned to the
    allocator when the pool is destroyed.
    */
    this(Allocator allocator) {
        _base_allocator = allocator;
        _slots = _base_allocator.make_array!_Slot(num_slots);

        _reserve_null_handle();
    }

    @disable this(this);

    ~this() {
        if (_base_allocator)
            _base_allocator.dispose(_slots);
    }

    Ternary owns(Handle handle) {
        return Ternary.no;
    }

    static if (!is(SlotData == void)) {
        PtrType!SlotData get(Handle handle) {
            return null;
        }
    }

    Handle make(Args...)(Args args) {

        static if (!is(SlotData == void)) {
            // constructor
        }

        return Handle();
    }

    void dispose(Handle handle) {
        static if (!is(SlotData == void) && hasElaborateDestructor!SlotData) {
            // destructor
        }
    }

private:
    align(max(object_alignment!SlotData, Handle.alignof)) struct _Slot {
        union {
            Handle handle;
            struct {
                mixin(bitfields!(
                        uint, "index", bits_to_store(max_index),
                        uint, "generation", bits_to_store(max_generation)));
            }
        }

        static if (!is(SlotData == void))
            void[object_size!SlotData] data;

        auto slot_data() {
            return cast(PtrType!SlotData) data.ptr;
        }
    }

    void _reserve_null_handle() {
        // If we can only have one generation per slot, skip over the first slot.
        static if (num_generations == 1) {
            _top++;
        }
        else {
            _slots[_top].generation = _slots[_top].generation + 1;
        }
    }

    Allocator _base_allocator;
    _Slot[] _slots;
    size_t _top;
}
