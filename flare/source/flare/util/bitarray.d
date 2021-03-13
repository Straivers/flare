module flare.util.bitarray;

struct BitArray {
    ubyte[] array;

    nothrow:
    this(ubyte[] storage) {
        array = storage;
    }

    /// Returns the number of bytes required to store n bits
    static size_t required_size_for(size_t n_bits) {
        const div = n_bits / 8;
        const rem = n_bits % 8;
        return div + (rem != 0);
    }

    bool opIndex(size_t bit) {
        const byte_index = bit / 8;
        return (array[byte_index] & (1 << (bit % 8))) != 0;
    }

    bool opIndexUnary(string op = "~")(size_t bit) in (bit < array.length * 8) {
        const byte_index = bit / 8;
        array[byte_index] ^= (1 << (bit % 8));
        return this[bit];
    }
}

unittest {
    auto array = BitArray([0]);

    assert(!array[0]);
    ~array[0];
    assert(array[0]);
    assert((array.array[0] & 1) != 0);
    assert((array.array[0] ^ 1) == 0);
    ~array[0];
    assert(!array[0]);

    assert(!array[7]);
    ~array[7];
    assert(array[7]);
    assert((array.array[0] & 1 << 7) != 0);
    assert((array.array[0] ^ 1 << 7) == 0);

    foreach (i; 0 .. 8)
        ~array[i];

    assert(array.array[0] == 127);
}
