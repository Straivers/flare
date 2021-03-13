module flare.util.object_pool;

import flare.memory.allocators.allocator;
import flare.memory.allocators.common;
import flare.memory.allocators.pool;
import flare.memory.measures;

/**
An object pool stores a fixed pool of objects, which may be allocated and freed
quickly.
*/
struct ObjectPool(T) {
public nothrow:
    /**
    Initializes the object pool using a preallocated block of memory. Ownership
    of the memory remains with the caller, but the caller must guarantee that
    the memory will not be modified except through the pool while the pool
    exists.

    Params:
        memory = The block of memory from which object allocations will be
                 served. It must be a multiple of `object_size!T`.
    */
    this(void[] memory) {
        _pool = MemoryPool(memory, object_size!T);

        // Class alignment = 8 (pointers)
        assert(_pool.alignment == T.alignof);
    }

    /**
    Initializes the object pool by allocating a block of memory from the base
    allocator. This block will be automatically cleaned up when the pool is
    destroyed.

    Params:
        base_allocator =    The allocator that provides the pool's memory.
        pool_size =         The number of elements to have in the pool.
    */
    this(Allocator base_allocator, size_t pool_size) {
        _pool = MemoryPool(base_allocator, object_size!T, pool_size);
    }

    /// The alignment of every allocation from this pool, in bytes.
    size_t alignment() const {
        return _pool.alignment;
    }

    /**
    Tests if the object was allocated from this pool.

    Params:
        object = The pointer to test
    
    Returns: `yes` if the object belongs, `no` otherwise.
    */
    Ternary owns(PtrType!T object) const {
        return _pool.owns((cast(void*) object)[0 .. object_size!T]);
    }

    /**
    Allocates a new object and initializes it in place.

    Params:
        args = Arguments for the object's constructor. May be empty.
    
    Returns: A pointer to the object if allocation was successful, or null if it
             failed.
    */
    PtrType!T make(Args...)(auto scope ref Args args) {
        return flare.memory.allocators.allocator.make!T(_pool, args);
    }

    /**
    Deallocates the object returns it to the pool.

    Note: It is an error to call this function with an object not owned by the
    pool.

    Params:
        object = The object of the object to deallocate.
    */
    void dispose(ref PtrType!T object) {
        return flare.memory.allocators.allocator.dispose(_pool, object);
    }

private:
    MemoryPool _pool;
}
