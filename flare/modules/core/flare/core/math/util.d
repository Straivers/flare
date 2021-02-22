module flare.core.math.util;

public import std.algorithm : min, max;

import std.traits : isIntegral;

pragma(inline, true) bool is_power_of_two(size_t n) nothrow {
    return (n != 0) & ((n & (n - 1)) == 0);
}

@("is_power_of_two(size_t)")
unittest {
    assert(is_power_of_two(1));
    assert(is_power_of_two(1 << 20));
    assert(!is_power_of_two(0));
}

pragma(inline, true) size_t round_to_power_of_two(size_t n) nothrow {
    if (n <= 1)
        return 1;
    
    return 1 << ilog2(n);
}

@("round_to_power_of_two(size_t)")
unittest {
    assert(round_to_power_of_two(0) == 1);
    assert(round_to_power_of_two(1) == 1);
    assert(round_to_power_of_two(2) == 2);
    assert(round_to_power_of_two(9) == 16);
}

/**
 Returns the integer log for `i`. Rounds up towards infinity.
 */
T ilog2(T)(T i) nothrow if (isIntegral!T) {
    import core.bitop : bsr;

    return i == 0 ? 1 : bsr(i) + !is_power_of_two(i);
}

size_t truncate_to_power_of_two(size_t n) nothrow {
    import core.bitop : bsr;

    assert(n > 0);

    if (n == 1)
        return 1;

    return 1 << bsr(n);
}

size_t round_to_next(size_t value, size_t base) nothrow {
    const rem = value % base;
    return rem ? value + (base - rem) : value;
}
