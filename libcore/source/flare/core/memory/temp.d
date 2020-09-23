module flare.core.memory.temp;

import flare.core.memory.buddy_allocator;
import flare.core.memory.measures;
import flare.core.memory.base;

enum local_temp_allocator_size = 256.kib;

auto tmp_obj(T, Args...)(Args args) {
    struct Obj {
        PtrType!T t;
        alias t this;

        @disable this(this);

        ~this() {
            if (t)
                tmp_free(t);
        }
    }

    return Obj(tmp_allocator.alloc(object_size!T).emplace_obj!T(args));
}

auto tmp_array(T)(size_t length) {
    struct Arr {
        T[] t;
        alias t this;

        @disable this(this);

        ~this() {
            if (t)
                tmp_free(t);
        }
    }

    return Arr(cast(T[]) tmp_allocator.alloc(T.sizeof * length));
}

void tmp_free(T)(PtrType!T t) {
    tmp_allocator.free((cast(void*) t)[0 .. object_size!T]);
}

void tmp_free(T)(T[] array) {
    tmp_allocator.free(cast(void[]) array);
}

private:

BuddyAllocator tmp_allocator;

static this() {
    tmp_allocator = BuddyAllocator(local_temp_allocator_size);
}
