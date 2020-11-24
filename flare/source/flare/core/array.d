module flare.core.array;

import flare.core.memory.api;
import flare.core.memory.base : PtrType;

struct Array(T) {
    enum default_size = 8;

public:
    @disable this(this);

    this(size_t length, Allocator mem) {
        _array = mem.alloc_array!T(length);
        _mem = mem;
    }

    ~this() {
        if (_mem) {
            _mem.dispose(_array);
            _array = [];
            _mem = null;
        }
    }

    void opOpAssign(string op = "~", T)(auto ref T value) {
        if (_length < _array.length) {
            _array[length] = value;
            _length++;
        }
        else if (_length > 0) {
            auto tmp = _mem.alloc_array!T(_array.length * 2);
            tmp[0 .. _array.length] = _array;
            _mem.free(_array);
            _array = tmp;
        }
        else {
            _array = _mem.alloc_array!T(default_size);
            _array[0] = value;
            _length = 1;
        }
    }

    PtrType!T ptr() {
        return _array.ptr;
    }

    size_t length() {
        return _length;
    }

    T[] array() {
        return _array[0 .. _length];
    }

    size_t opDollar() {
        return _length;
    }

    ref T opIndex(size_t index) {
        return _array[index];
    }

    void opIndexAssign(ref T value, size_t index)
    in (index < length) {
        _array[index] = value;
    }

    void opIndexAssign(T value, size_t index)
    in (index < length) {
        _array[index] = value;
    }

    int opApply(scope int delegate(ref T) dg) {
        int result = 0;
        foreach (ref item; array()) {
            result = dg(item);
            if (result)
                break;
        }
    
        return result;
    }

    int opApply(scope int delegate(ref size_t index, ref T) dg) {
        int result = 0;
        foreach (i, ref item; array()) {
            result = dg(i, item);
            if (result)
                break;
        }
    
        return result;
    }

private:
    T[] _array;
    size_t _length;
    Allocator _mem;
}
