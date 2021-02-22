module flare.core.conv;

import flare.core.buffer_writer: TypedWriter;

char[] to_chars(long value, char[] out_buffer) @safe @nogc pure nothrow {
    import std.math : abs;

    char[20] buffer;
    auto next = 19;
    
    const is_negative = value < 0;

    while (value) {
        buffer[next] = cast(char) ('0' + abs(value % 10));
        value /= 10;
        next--;
    }

    if (is_negative) {
        buffer[next] = '-';
        next--;
    }

    const start = next + 1;
    out_buffer[0 .. buffer.length - start] = buffer[start .. $];
    return out_buffer[0 .. buffer.length - start];
}

unittest {
    char[20] buffer;
    assert(long.max.to_chars(buffer) == "9223372036854775807");
    assert(long.min.to_chars(buffer) == "-9223372036854775808");
}
