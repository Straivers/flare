module flare.core.hash;

alias Hash = Hash64;

struct Hash64 {
    ubyte[8] value;
}

Hash hash_of(const(char)[] str) {
    import std.digest.murmurhash: digest, MurmurHash3;

    return Hash(digest!(MurmurHash3!128)(str)[0 .. Hash.value.length]);
}
