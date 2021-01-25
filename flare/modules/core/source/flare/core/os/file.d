module flare.core.os.file;

import flare.core.memory;

ubyte[] read_file(string path, Allocator storage) {
    import std.mmfile: MmFile;
    import std.typecons: scoped;

    auto file = scoped!MmFile(path);
    auto data = storage.make_array!ubyte(file.length);
    data[] = cast(ubyte[]) file[];
    return data;
}


// TODO: Custom mmap implementation
