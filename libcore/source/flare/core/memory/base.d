module flare.core.memory.base;

PtrType!T emplace_obj(T, Args...)(void[] mem, Args args)
in (mem.length >= object_size!T) {
    import std.conv : emplace;

    return (cast(PtrType!T) mem.ptr).emplace(args);
}
