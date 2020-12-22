module flare.core.memory.object_pool;

/// An opaque handle to an object allocated from an `ObjectPool`.
struct Handle {
    ulong value;
}

/**
 * A fixed-size pool of objects that are allocated and freed by handle. The use
 * of handles allows us to catch certain use-after-free bugs, so long as no
 * pointers to the contained memory are preserved beyond a calling scope. For
 * best results, do not pass pointers or references retrieved by `get()` to
 * called functions.
 */
struct ObjectPool(T, size_t size) {
    import flare.core.hash : hash_of;
    import flare.core.memory.base : get_ptr_type, PtrType;
    import std.traits : fullyQualifiedName;

    static assert(size <= 64, "Implementation defined max size, need to fix.");

    /// A pair holding the handle to an object as well as a pointer or reference
    /// to the allocated object itself.
    struct Slot {
        ///
        Handle handle;
        ///
        PtrType!T content;
        alias content this;
    }

public:
    @disable this();

    /// Initialize this object pool with a default value. All objects allocated
    /// from this pool will also be initialized to this value.
    this(T init_value) {
        _initial_value = init_value;
        _type_hash = hash_of(fullyQualifiedName!T).value[0 .. 4];

        foreach (i, ref slot; _slots) {
            slot.content = _initial_value;
            slot.handle.index = cast(ushort) i;
            slot.handle.type_hash = _type_hash;
        }

        // We want to reserve Handle(0) for invalid handles.
        _slots[0].handle.generation++;
    }

    size_t num_allocated() {
        import core.bitop: popcnt;

        return popcnt(~_bitmap);
    }

    bool is_valid(Handle handle) {
        auto i = Handle_(handle.value).index;

        return i < size && _slots[i].handle.value == handle.value;
    }

    /// Allocates an object from this pool. If the pool's capacity was exceeded,
    /// returns an empty slot.
    Slot alloc() {
        import core.bitop: bsf;

        if (_bitmap == 0)
            return Slot();

        const index = bsf(_bitmap);
        _bitmap ^= (1 << index);

        auto handle = Handle(_slots[index].handle.value);
        return Slot(Handle(_slots[index].handle.value), &_slots[index].content);
    }

    /// Returns the object identified by the handled to the pool. From this
    /// point on, any attempt to call `get()` with the handle will result in an
    /// erorr.
    ///
    /// This function is a no-op for invalid handles.
    void free(Handle handle) {
        auto slot = _get_slot(handle);

        if (slot is null)
            return;

        slot.handle.generation++;
        slot.content = _initial_value;
        _bitmap |= (1 << slot.handle.index);
    }

    /// Retrieves an object identified by handle if it exists, or `null`
    /// otherwise.
    PtrType!T get(Handle handle) {
        auto slot = _get_slot(handle);
        return slot ? get_ptr_type(slot.content) : null;
    }

    /// Creates a forward range iterating over every allocated slot.
    auto get_all_allocated() {
        struct Result {
            uint index;
            ObjectPool* pool;

            bool empty() { return index == size; }

            Slot front() {
                return Slot(Handle(pool._slots[index].handle.value), get_ptr_type(pool._slots[index].content));
            }

            void popFront() {
                index++;
                while (index < size && pool._is_free(index))
                    index++;
            }
        }

        auto r = Result(0, &this);
        if (_is_free(0))
            r.popFront();
        return r;
    }

private:
    union Handle_ {
        ulong value;
        
        struct {
            ushort index;
            ushort generation;
            ubyte[4] type_hash;
        }
    }

    struct Slot_ {
        Handle_ handle;
        T content;
    }

    Slot_* _get_slot(Handle handle) {
        auto i = Handle_(handle.value).index;

        if (i < size && _slots[i].handle.value == handle.value) {
            assert(!_is_free(i));
            return &_slots[i];
        }

        return null;
    }

    bool _is_free(uint index) {
        return (_bitmap & (1 << index)) == 1;
    }

    /// Bitmap of free slots. Every 1 bit is free. Every 0 bit is allocated.
    ulong _bitmap = ulong.max;
    Slot_[size] _slots;
    T _initial_value;
    ubyte[4] _type_hash;
}
