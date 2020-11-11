module flare.core.memory.base;

import std.traits: isIntegral;
import flare.core.memory.measures;

nothrow:

PtrType!T emplace_obj(T, Args...)(void[] mem, Args args)
in (mem.length >= object_size!T) {
    import std.conv : emplace;

    return (cast(PtrType!T) mem.ptr).emplace(args);
}

template PtrType(T) {
    static if (is(T == class))
        alias PtrType = T;
    else
        alias PtrType = T*;
}

pragma(inline, true) bool is_power_of_two(size_t n) {
    return (n != 0) & ((n & (n - 1)) == 0);
}

unittest {
    assert(is_power_of_two(1));
    assert(is_power_of_two(1 << 20));
    assert(!is_power_of_two(0));
}

pragma(inline, true) size_t round_to_power_of_two(size_t n) {
    if (n <= 1)
        return 1;
    
    return 1 << ilog2(n);
}

unittest {
    assert(round_to_power_of_two(0) == 1);
    assert(round_to_power_of_two(1) == 1);
    assert(round_to_power_of_two(2) == 2);
    assert(round_to_power_of_two(9) == 16);
}

/**
 Returns the integer log for `i`. Rounds up towards infinity.
 */
T ilog2(T)(T i) if (isIntegral!T) {
    import core.bitop: bsr;

    return i == 0 ? 1 : bsr(i) + !is_power_of_two(i);
}

size_t truncate_to_power_of_two(size_t n) {
    import core.bitop: bsr;

    assert(n > 0);

    if (n == 1)
        return 1;

    return 1 << bsr(n);
}
