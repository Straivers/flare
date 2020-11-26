module flare.core.memory.api;

public import flare.core.memory.measures: kib, mib, gib;

abstract class Allocator {
    import flare.core.memory.base: PtrType, emplace_obj;
    import flare.core.memory.measures: object_size, object_alignment;
    import std.traits: hasElaborateDestructor;
    
public nothrow:
    /**
     Allocates an untyped buffer of memory with the given alignment. If
     allocation fails, this function returns an empty array.
     */
    void[] alloc(size_t size, size_t alignment);

    // TODO: Implement realloc for resizing allocations

    PtrType!T alloc_object(T, Args...)(Args args) {
        auto mem = alloc(object_size!T, object_alignment!T);
        return mem ? mem.emplace_obj!T(args) : null;
    }

    T[] alloc_array(T)(size_t length, T default_value = T.init) {
        // D auto-conversion for array sizes from void[].
        auto arr = cast(T[]) alloc(T.sizeof * length, T.alignof);

        // In case the allocation failed.
        if (arr)
            arr[] = default_value;

        return arr;
    }

    /**
     Frees a buffer of memory owned by this allocator.

     If memory cannot be freed from the allocator, this function is a no-op.
     */
    void free(void[] memory);

    void free(T)(auto ref PtrType!T object) {
        static if (hasElaborateDestructor!T)
            destroy(object);
        
        free((cast(void*) object)[0 .. object_size!T]);
        object = null;
    }

    void dispose(T)(auto ref T[] array) {
        static if (hasElaborateDestructor!T) {
            foreach (ref t; array)
                destroy(t);
        }

        free(array);
        array = [];
    }

    void dispose(T)(auto ref PtrType!T object) {
        static if (hasElaborateDestructor!T)
            destroy(object);

        free(object);
        object = null;
    }
}

template as_api(T) {
    final class as_api : Allocator {
        override void[] alloc(size_t size, size_t alignment) {
            return base.alloc(size, alignment);
        }

        override void free(void[] memory) {
            return base.free(memory);
        }

        this(Args...)(Args args) {
            base = T(args);
        }

        ~this() {
            base.destroy();
        }

        private T base;
    }
}
