module flare.core.memory.virtual;

import core.memory : pageSize;
import flare.core.memory.base;

version (Windows) {
    import core.sys.windows.winbase : VirtualAlloc, VirtualFree;
    import core.sys.windows.winnt : MEM_RELEASE, MEM_COMMIT, MEM_RESERVE,
        PAGE_READWRITE, PAGE_NOACCESS;
}

nothrow:

void[] vm_alloc(size_t size) {
    const actual_size = round_to_page(size);
    version (Windows) {
        auto start = VirtualAlloc(null, actual_size, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
        return start[0 .. actual_size];
    }
}

void vm_free(void[] mem) {
    version (Windows) {
        VirtualFree(mem.ptr, 0, MEM_RELEASE);
    }
}

private:

size_t round_to_page(size_t n) {
    return n + ((pageSize - n) % pageSize);
}
