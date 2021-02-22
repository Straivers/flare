module flare.core.memory.traits;

template PtrType(T) {
    static if (is(T == class))
        alias PtrType = T;
    else
        alias PtrType = T*;
}

PtrType!T get_ptr_type(T)(ref T object) {
    static if (is(T == class))
        return object;
    else
        return &object;
}
