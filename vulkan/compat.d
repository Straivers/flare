module flare.vulkan.compat;

import flare.core.memory.temp;

@safe nothrow:

/**
 Converts an array of D-style strings to an array of C-style strings.
 */
@trusted auto to_cstr_array(in string[] strings) {
    import std.algorithm: map, sum, move;
    import flare.core.buffer_writer: Writer;

    struct Cstr {
        char*[] array;
        char[] contents;
        void[] memory;

        alias array this;
    }

    const array_size = (char*).sizeof * strings.length;
    const total_size = strings.map!(s => s.length + 1).sum + array_size;
    auto mem = tmp_alloc(total_size);

    Cstr s = {
        array : (cast(char**) mem.ptr)[0 .. strings.length],
        contents : cast(char[]) mem[array_size .. $],
        memory : mem
    };

    assert(s.contents.length == total_size - array_size);

    auto b = Writer!char(s.contents);
    foreach (i, str; strings) {
        s.array[i] = b.position;
        b.put(str);
        b.put('\0');
    }

    return s;
}
