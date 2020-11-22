module flare.core.memory.api;

public import flare.core.memory.measures: kib, mib, gib;

abstract class Allocator {
    import flare.core.memory.base: PtrType, emplace_obj;
    import flare.core.memory.measures: object_size, object_alignment;
    
public nothrow:
    /**
     Allocates an untyped buffer of memory with the given alignment. If
     allocation fails, this function returns an empty array.
     */
    void[] alloc_raw(size_t size, size_t alignment);

    /**
     Frees a buffer of memory owned by this allocator.

     If memory cannot be freed from the allocator, this function is a no-op.
     */
    void free_raw(void[] memory);

    // TODO: Implement realloc for resizing allocations

    PtrType!T alloc_obj(T, Args...)(Args args) {
        auto mem = alloc_raw(object_size!T, object_alignment!T);
        return mem ? mem.emplace_obj!T(args) : null;
    }

    void free_obj(T)(PtrType!T object) {
        free_raw((cast(void*) object)[0 .. object_size!T]);
    }

    void destroy_obj(T)(PtrType!T object) {
        destroy(object);
        free_obj(object);
    }

    T[] alloc_arr(T)(size_t length, T default_value = T.init) {
        // D auto-conversion for array sizes from void[].
        auto arr = cast(T[]) alloc_raw(T.sizeof * length, T.alignof);

        // In case the allocation failed.
        if (arr)
            arr[] = default_value;

        return arr;
    }

    void free_arr(T)(T[] array) {
        // D auto-conversion for array sizes to void[].
        free_raw(cast(void[]) array);
    }

    void destroy_arr(T)(T[] array) {
        foreach (ref t; array)
            destroy(t);
        free_arr(array);
    }
}
