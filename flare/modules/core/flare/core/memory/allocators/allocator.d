module flare.core.memory.allocators.allocator;

import flare.core.memory.measures;
import flare.core.memory.allocators.common;
import std.traits : hasMember, hasElaborateDestructor;

public import std.typecons: Ternary;

abstract class Allocator {

nothrow:
    /// The default alignment used by the allocator.
    size_t alignment() const;

    /**
    Tests if the memory was allocated from this allocator.

    Params:
        memory =    The block of memory to test. May be `null`.
    
    Returns: `yes` if `memory` is `null` or was allocated from the allocator,
             `unknown` if it _might_ have been allocated from this allocator,
             and `no` was not allocated from this allocator.
    */
    Ternary owns(void[] memory) const;

    /**
    Calculates the optimal allocation size for at least `size` bytes of data to
    minimize fragmentation.

    Params:
        size =      The minimum size of a block.
    
    Returns: The optimal size. If `size` is `0`, this must also be `0`.
    */
    size_t get_optimal_alloc_size(size_t size) const;

    /**
    Allocates `size` bytes from the allocator if `size > 0`, otherwise this
    function is a no-op.

    Params:
        size =      The size of the block of memory to allocate.
    
    Returns: A block of memory of the requested size, or `null` if `size == 0`
             or the allocation failed.
    */
    void[] allocate(size_t size);

    /**
    OPTIONAL

    If supported by the allocator, returns the memory to the allocator to be
    reused for further allocations. It is an error to call this with a block of
    memory that was not allocated by the allocator.

    Params:
        memory =    The block of memory to deallocate.

    Returns: `true` if `memory` was `null` or was returned to the allocator,
             `false` if the memory was not returned, or if allocator does not
             support deallocation.
    */
    bool deallocate(ref void[] memory);

    /// ditto
    bool deallocate(void[] memory) { return deallocate(memory); }

    /**
    OPTIONAL

    Attempts to resize a block of memory, possibly allocating new memory to do
    so. It is an error to call this with a block of memory that was not
    allocated by this allocator.

    Note: If `memory` is `null` and `size` is `0`, this function attempts an
    empty allocation.

    Params:
        memory =    The block of memory to resize. If `null`, `reallocate` will
                    attempt to allocate a block of memory.
        new_size =  The new size of the block. If `0`, `reallocate` will
                    attempt to deallocate the block.
    
    Returns: `true` if the memory block was reallocated, `false` otherwise.
    */
    bool reallocate(ref void[] memory, size_t new_size);

    /**
    OPTIONAL

    Attempts to resize a block of memory in-place. It is an error to call this
    with a block of memory that was not allocated by this allocator.

    Params:
        memory =    The block of memory to resize. Resizing fails if this is
                    `null`.
        new_size =  The new size of the block. Resizing fails if this is `0`.
    
    Returns: `true` if the memory block was resized, `false` otherwise.
    */
    bool resize(ref void[] memory, size_t new_size);
}

final class AllocatorApi(T) : Allocator {
nothrow public:
    this(Args...)(Args args) {
        _impl = T(args);
    }

    ~this() {
        destroy(_impl);
    }

    override size_t alignment() const {
        return _impl.alignment();
    }

    override Ternary owns(void[] memory) const {
        return _impl.owns(memory);
    }

    override size_t get_optimal_alloc_size(size_t size) const {
        return _impl.get_optimal_alloc_size(size);
    }

    override void[] allocate(size_t size) {
        return _impl.allocate(size);
    }

    alias deallocate = Allocator.deallocate;

    override bool deallocate(ref void[] memory) {
        static if (hasMember!(T, "deallocate"))
            return _impl.deallocate(memory);
        else
            return false;
    }

    override bool reallocate(ref void[] memory, size_t new_size) {
        static if (hasMember!(T, "reallocate"))
            return _impl.reallocate(memory, new_size);
        else
            return false;
    }

    override bool resize(ref void[] memory, size_t new_size) {
        static if (hasMember!(T, "resize"))
            return _impl.resize(memory, new_size);
        else
            return false;
    }
    
private:
    T _impl;
}

/**
Resizes an array to `new_length` elements, calling `init_obj` on newly
allocated objects, and `clear_obj` on objects to be deallocated.

If `new_length > 0` and `array == null`, a new array will be allocated, and the
slice assigned to `array`. Similarly, if `new_length == 0` and `array != null`,
the array will be freed, and `array` will become `null`.

Params:
    allocator   = The allocator that the array was allocated from.
    array       = The array to be resized. May be `null`.
    new_length  = The length of the array after resizing. May be `0`.
    init_obj    = The delegate to call on newly allocated array elements (during array expansion).
    clear_obj   = The delegate to call on array elements that will be freed (during array reduction).
*/
bool resize_array(T, A)(
        auto ref A allocator,
        ref T[] array,
        size_t new_length,
        scope void delegate(size_t, ref T) nothrow init_obj = null,
        scope void delegate(size_t, ref T) nothrow clear_obj = null) nothrow {
    import std.algorithm: min;

    static assert(!hasMember!(T, "opPostMove"), "Move construction on array reallocation not supported!");

    if (new_length == array.length)
        return true;

    const common_length = min(array.length, new_length);

    if (new_length < array.length && clear_obj) {
        foreach (i, ref object; array[new_length .. $])
            clear_obj(i, object);
    }

    void[] array_ = array;
    if (!allocator.reallocate(array_, T.sizeof * new_length))
        return false;
    array = cast(T[]) array_;

    if (common_length < new_length && init_obj) {
        foreach (i, ref object; array[common_length .. $])
            init_obj(i, object);
    }

    return true;
}

public import std.experimental.allocator: make, make_array = makeArray, dispose;

version (unittest) {
    void test_allocate_api(AllocatorType)(ref AllocatorType allocator) {
        assert(allocator.owns([]) == Ternary.yes);
        assert(allocator.allocate(0) == []);

        auto empty = [];

        static if (hasMember!(AllocatorType, "deallocate"))
            assert(allocator.deallocate(empty));

        assert(allocator.get_optimal_alloc_size(0) == 0);

        auto m = allocator.allocate(allocator.get_optimal_alloc_size(1));
        assert(m);
        assert(m.length == allocator.get_optimal_alloc_size(1));
        assert(allocator.owns(m) != Ternary.no);
        assert((cast(size_t) m.ptr) % allocator.alignment == 0);

        static if (hasMember!(AllocatorType, "deallocate")) {
            // cleanup
            allocator.deallocate(m);
            assert(!m);
        }
    }

    void test_reallocate_api(AllocatorType)(ref AllocatorType allocator) {
        void[] m;
        allocator.reallocate(m, 20);
        assert(m);
        assert(m.length == 20);
        const s = m.ptr;
        
        // Reallocation as resize
        assert(allocator.reallocate(m, 1));
        assert(m.ptr == s);
        assert(m.length == 1);

        // Reallocation as resize (limits)
        assert(allocator.reallocate(m, allocator.get_optimal_alloc_size(1)));
        assert(m.ptr == s);

        // Reallocation as allocation and copy
        static if (hasMember!(AllocatorType, "resize"))
            assert(!allocator.resize(m, m.length + 1));

        assert(allocator.reallocate(m, m.length + 1));
        assert(m.length == allocator.get_optimal_alloc_size(1) + 1);
        assert(m.ptr != s); // error here!

        // Reallocation as deallocation
        assert(allocator.reallocate(m, 0));
        assert(m == null);

        // Empty reallocation
        assert(allocator.reallocate(m, 0));
    }

    /// Set can_grow to indicate that resize() may grow an allocation even where
    /// `size == optimal_alloc_size(s)`
    void test_resize_api(bool can_grow = false, AllocatorType)(ref AllocatorType allocator) {
        auto empty = [];
        assert(!allocator.resize(empty, 1));
        assert(!allocator.resize(empty, 0));

        auto m = allocator.allocate(1);
        const s = m.ptr;

        // Resize fail on size 0
        auto m2 = m;
        assert(!allocator.resize(m2, 0));
        assert(m2 == m);

        // Resize down
        assert(allocator.resize(m, 1));
        assert(m.length == 1);
        assert(m.ptr == s);

        // Resize up
        assert(allocator.resize(m, allocator.get_optimal_alloc_size(1)));
        assert(m.ptr == s);

        // Failed resize (limits)
        static if (!can_grow)
            assert(!allocator.resize(m, allocator.get_optimal_alloc_size(1) + 1));

        static if (hasMember!(AllocatorType, "deallocate")) {
            allocator.deallocate(m);
            assert(!m);
        }
    }
}
