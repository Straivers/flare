module flare.core.util;

struct CheckedVoidPtr {
    import flare.core.hash: Hash64, hash_of;
    import flare.core.memory.traits : PtrType, to_ptr_type;
    import std.traits : fullyQualifiedName;

    Hash64 cookie;
    void* ptr;

    this(T)(T* t) nothrow {
        enum type_hash = Hash64(fullyQualifiedName!T.hashOf);
        cookie = type_hash;
        ptr = t;
    }

    this(T)(T t) nothrow if (is(T == class) || is(T == interface)) {
        enum type_hash = Hash64(fullyQualifiedName!T.hashOf);
        cookie = type_hash;
        ptr = cast(void*) t;
    }

    PtrType!T get(T)() nothrow {
        enum type_hash = Hash64(fullyQualifiedName!T.hashOf);
        assert(type_hash == cookie);

        return to_ptr_type!T(ptr);
    }

    void opAssign(ref CheckedVoidPtr other) nothrow {
        this.cookie = other.cookie;
        this.ptr = other.ptr;
    }

    void opAssign(T)(T* t) nothrow {
        enum type_hash = Hash64(fullyQualifiedName!T.hashOf);
        cookie = type_hash;
        ptr = cast(void*) t;
    }

    void opAssign(T)(T t) nothrow if (is(T == class) || is(T == interface)) {
        enum type_hash = Hash64(fullyQualifiedName!T.hashOf);
        cookie = type_hash;
        ptr = cast(void*) t;
    }
}
