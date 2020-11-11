module flare.core.memory.temp;

import flare.core.memory.buddy_allocator;
import flare.core.memory.measures;
import flare.core.memory.base;

enum local_temp_allocator_size = 256.kib;

nothrow:

void[] tmp_alloc(size_t n_bytes) {
    return tmp_allocator.alloc(n_bytes);
}

auto tmp_obj(T, Args...)(Args args) {
    return tmp_allocator.alloc(object_size!T).emplace_obj!T(args);
}

auto tmp_array(T)(size_t length) {
    return cast(T[]) tmp_allocator.alloc(T.sizeof * length);
}

void tmp_free(void[] memory) {
    tmp_allocator.free(memory);
}

void tmp_free_obj(T)(PtrType!T t) {
    tmp_allocator.free((cast(void*) t)[0 .. object_size!T]);
}

void tmp_free_array(T)(T[] array) {
    tmp_allocator.free(cast(void[]) array);
}

private:

BuddyAllocator tmp_allocator;

static this() {
    tmp_allocator = BuddyAllocator(local_temp_allocator_size);
}
