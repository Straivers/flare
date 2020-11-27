module flare.core.memory.measures;

// dfmt off
size_t kib(size_t n) { return n * 1024; }
size_t mib(size_t n) { return n * (1024 ^^ 2); }
size_t gib(size_t n) { return n * (1024 ^^ 3); }
// dfmt on

template object_size(T) {
    static if (is(T == class))
        enum object_size = __traits(classInstanceSize, T);
    else
        enum object_size = T.sizeof;
}

template object_alignment(T) {
    import std.traits: classInstanceAlignment;

    static if (is(T == class))
        enum object_alignment = classInstanceAlignment!T;
    else
        enum object_alignment = T.alignof;
}
