module flare.vulkan.compat;

import flare.core.memory;

@safe:

/**
 Converts an array of D-style strings to an array of C-style strings, using
 allocator as the memory store. The strings will be copied so that a
 null-termination character can be inserted at the ends of the strings. If the
 allocator runs out of memory midway through the operation, everything that has
 been allocated will be freed before the function returns.
 */
@trusted char*[] to_cstr_array(in string[] strings, ref ScopedArena allocator) nothrow {
    auto array = allocator.make_array!(char*)(strings.length);

    foreach (i, ref str; strings) {
        auto c_string = allocator.make_array!char(str.length + 1);

        if (!c_string)
            return [];

        c_string[0 .. str.length] = str;
        c_string[$ - 1] = '\0';
        array[i] = c_string.ptr;
    }

    return array;
}
