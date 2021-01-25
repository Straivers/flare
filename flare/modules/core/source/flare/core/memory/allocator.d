module flare.core.memory.allocator;

import flare.core.memory.common;
import std.traits: hasElaborateDestructor, hasMember;

public import std.typecons: Ternary;

interface Allocator {

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
    import std.traits: hasMember;

public:
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
Allocates the memory for an object of type `T` then initializes it with the
provided arguments (if any) in-place. If memory allocation or object
initialization fails, returns `null`.
*/
auto make(T, A, Args...)(auto ref A allocator, auto ref Args args) {
    assert(allocator.alignment >= object_alignment!T, "Non-default alignment not currently supported ");
    auto memory = allocator.allocate(object_size!T);

    if (!memory)
        return null;

    scope (failure)
        allocator.deallocate(memory);

    auto typed = () @trusted { return cast(T[]) memory; } ();
    assert(typed.length == 1);
    return emplace_obj!T(typed, args);
}

/**
Allocates a default-initialized array of the given length.
*/
auto make_array(T, A)(auto ref A allocator, size_t length) {
    if (!length)
        return null;

    auto memory = allocator.allocate(T.sizeof * length);

    if (!memory)
        return null;

    auto typed = () @trusted { return cast(T[]) memory; } ();
    typed[] = T.init;

    assert(typed.length == length, "DLang assumption about void[] -> T[] violated.");
    return typed;
}

/**
Resizes an array to a new_length elements. If `length > array.length`, new
elements are initialized to `T.init`. Resizing to a length of 0 will deallocate
the array.
*/
bool resize_array(T, A)(auto ref A allocator, ref T[] array, size_t new_length) {
    import std.algorithm: min;

    auto array_ = cast(void[]) array;
    if (!allocator.reallocate(array_, T.sizeof * new_length))
        return false;
    array = cast(T[]) array_;

    const common_length = min(array.length, new_length);
    if (common_length < new_length)
        array[common_length .. $] = T.init;

    return true;
}

/**
Destroys an object or array and returns the memory it occupied to the allocator.
Note that it is undefined behavior for to free an object with an allocator that
does not own its memory.
*/
void dispose(T, A)(auto ref A allocator, auto ref T* object) {
    if (!object)
        return;

    static if (hasElaborateDestructor!T)
        destroy(*object);

    auto memory = (cast(void*) object)[0 .. object_size!T];
    assert(allocator.owns(memory));
    allocator.deallocate(memory);

    static if (__traits(isRef, object))
        object = null;
}

/// Ditto
void dispose(T, A)(auto ref A allocator, auto ref T object)
if (is(T == class) || is(T == interface)) {
    if(!object)
        return;

    static if (is(T == interface))
        auto obj = cast(Object) object;
    else
        alias obj = object;

    destroy(obj);

    auto memory = (cast(void*) object)[0 .. object_size!T];
    assert(allocator.owns(memory) != Ternary.no);
    allocator.deallocate(memory);

    static if (__traits(isRef, object))
        object = null;
}

/// Ditto
void dispose(T, A)(auto ref A allocator, auto ref T[] array) {
    static if (hasElaborateDestructor!T)
        foreach (ref element; array)
            destroy(element);

    assert(allocator.owns(array) != Ternary.no);
    auto untyped = cast(void[]) array;
    allocator.deallocate(untyped);

    static if (__traits(isRef, array))
        array = null;
}

version (unittest) {
    import std.traits: hasMember;

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

    void test_resize_api(AllocatorType)(ref AllocatorType allocator) {
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
        assert(!allocator.resize(m, allocator.get_optimal_alloc_size(1) + 1));

        static if (hasMember!(AllocatorType, "deallocate")) {
            allocator.deallocate(m);
            assert(!m);
        }
    }
}