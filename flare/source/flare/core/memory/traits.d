module flare.core.memory.traits;

template PtrType(T) {
    static if (is(T == class))
        alias PtrType = T;
    else
        alias PtrType = T*;
}

PtrType!T get_ptr_type(T)(ref T object) {
    static if (is(T == class) || is(T == interface))
        return object;
    else
        return &object;
}

PtrType!T to_ptr_type(T)(void* ptr) {
    static if (is(T == class) || is(T == interface))
        return cast(T) ptr;
    else
        return cast(T*) ptr;
}
