module flare.os.file;

import flare.memory;

nothrow:

ubyte[] read_file(string path, Allocator storage) {
    import std.mmfile: MmFile;
    import std.typecons: scoped;

    try {
        auto file = scoped!MmFile(path);
        auto data = storage.make_array!ubyte(file.length);
        data[] = cast(ubyte[]) file[];
        return data;
    } catch (Exception e) {
        assert(0);
    }
}


// TODO: Custom mmap implementation
