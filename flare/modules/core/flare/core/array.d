module flare.core.array;

import flare.core.math.util : max;
import flare.core.memory : Allocator, make_array, resize_array, dispose;
import std.algorithm : move;
import std.traits: hasElaborateDestructor;

struct Array(T) {
    enum default_initial_size = 8;

public:
    this(Allocator allocator) {
        _allocator = allocator;
    }

    this(Allocator allocator, size_t initial_size) {
        this(allocator);
        _array = make_array!T(_allocator, initial_size);
    }

    @disable this(this);

    ~this() {
        dispose(_allocator, _array);
    }

    size_t length() const {
        return _length;
    }

    size_t capacity() const {
        return _array.length;
    }

    void trim() {
        trim((size_t s, ref T t) {
            static if (hasElaborateDestructor!T)
                destroy(t);
        });
    }

    void trim(scope void delegate(size_t, ref T) nothrow on_destroy) {
        resize_array(
            _allocator,
            _array,
            _length,
            (size_t s, ref T t) {},
            on_destroy
        );
    }

    void push_back()(auto ref T value) {
        if (_length == _array.length)
            _grow();

        _array[_length] = move(value);
        _length++;
    }

    T pop_back() {
        assert(_length > 0);

        scope (exit)
            _length--;

        return move(_array[_length - 1]);
    }

    ref inout(T) opIndex(size_t index) inout {
        return _array[index];
    }

private:
    void _grow() {
        if (_array.length == 0)
            _array = make_array!T(_allocator, default_initial_size);
        else {
            const resized = resize_array(_allocator, _array, _array.length * 2);
            if (!resized)
                assert(0, "Out of memory! Array could not be expanded");
        }
    }

    Allocator _allocator; 
    size_t _length;
    T[] _array;
}

unittest {
    import flare.core.memory : AllocatorApi, Arena;

    auto mem = new AllocatorApi!Arena(new void[](2 * int.sizeof * 512));
    auto arr = Array!int(mem);

    foreach (i; 0 .. 512)
        arr.push_back(i);
    assert(arr.length == 512);

    foreach (i; 0 .. 512)
        assert(arr[i] == i);

    foreach_reverse (i; 0 .. 512) {
        assert(arr.pop_back() == i);
        assert(arr.length == i);
    }
}

unittest {
    import flare.core.memory : AllocatorApi, Arena;

    struct Foo {
        int value;
        @disable this(this);
    }

    auto mem = new AllocatorApi!Arena(new void[](2 * Foo.sizeof * 512));
    auto arr = Array!Foo(mem);

    foreach (i; 0 .. 512)
        arr.push_back(Foo(i));
    assert(arr.length == 512);

    foreach (i; 0 .. 512)
        assert(arr[i].value == i);

    foreach_reverse (i; 0 .. 512) {
        assert(arr.pop_back().value == i);
        assert(arr.length == i);
    }
}
