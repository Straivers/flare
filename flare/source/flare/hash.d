module flare.hash;

nothrow:

alias Hash = Hash64;

align (8) struct Hash64 {
    ulong value;
}

Hash64 hash_of(const(char)[] str) {
    import std.digest.murmurhash: digest, MurmurHash3;

    auto v = digest!(MurmurHash3!128)(str);
    return Hash(*(cast(ulong*) v.ptr));
}
