module flare.vulkan.compat;

import flare.core.memory.temp;

@safe:

/**
 Converts an array of D-style strings to an array of C-style strings.
 */
@trusted auto to_cstr_array(in string[] strings) {
    import std.algorithm: sum, map;
    import flare.core.buffer_writer: Writer;

    const array_size = strings.length * (char*).sizeof;
    const data_size = strings.map!(s => s.length + 1).sum();
    const size = array_size + data_size;

    auto memory = tmp_alloc(size);
    assert(memory, "Out of temporary memory!");
    auto array = cast(char*[]) memory[0 .. array_size];
    auto writer = Writer!char(cast(char[]) memory[array_size .. $]);

    foreach (i, ref ptr; array) {
        ptr = writer.position;
        writer.put(strings[i]);
        writer.put('\0');
    }

    struct TmpCStrArray {
        void[] memory;
        char*[] array;

        void free() {
            tmp_free(memory);
        }

        char** ptr() { return array.ptr; }

        size_t length() { return array.length; }
    }

    return TmpCStrArray(memory, array);
}
