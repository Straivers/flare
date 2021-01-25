module flare.core.memory.common;


public import std.typecons: Ternary;

public import flare.core.memory.measures;
public import flare.core.math.util;

package:

PtrType!T emplace_obj(T, Args...)(PtrType!T mem, auto ref Args args)
in (mem.length > 0) {
    import std.conv : emplace;

    return mem.ptr.emplace(args);
}

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

void* align_pointer(void* ptr, size_t alignment) nothrow {
    auto rem = (cast(size_t) ptr) % alignment;
    return rem == 0 ? ptr : ptr + (alignment - rem);
}

@("align_pointer(void*, align_t)")
unittest {
    const p0 = null;
    assert(align_pointer(p0, 8) == null);

    const p1 = cast(void*) 1;
    assert(align_pointer(p1, 4) == cast(void*) 4);

    const p2 = cast(void*) 8;
    assert(align_pointer(p2, 8) == cast(void*) 8);
}
