module flare.vulkan.compat;

import flare.core.memory.temp;
import flare.core.memory.api;

@safe nothrow:

/**
 Converts an array of D-style strings to an array of C-style strings, using
 allocator as the memory store. The strings will be copied so that a
 null-termination character can be inserted at the ends of the strings. If the
 allocator runs out of memory midway through the operation, everything that has
 been allocated will be freed before the function returns.
 */
@trusted char*[] to_cstr_array(in string[] strings, Allocator allocator) {
    auto array = allocator.alloc_arr!(char*)(strings.length);

    foreach (i, ref str; strings) {
        auto tmp = allocator.alloc_arr!char(str.length + 1);

        if (!tmp) {
            // free all allocated strings
            for (auto j = 0; j < array.length && array[j] !is null; j++)
                allocator.free_arr(array[j][0 .. strings[j].length + 1]);
            // free array of strings
            allocator.free_arr(array);

            return [];
        }

        tmp[0 .. str.length] = str;
        tmp[$ - 1] = '\0';
        array[i] = tmp.ptr;
    }

    return array;
}
