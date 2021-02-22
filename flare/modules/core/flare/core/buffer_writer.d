module flare.core.buffer_writer;

/**
 A basic writer to a buffer of elements.
 */
struct TypedWriter(ElementType) {
    import std.range: isInputRange;

public @safe @nogc pure nothrow:
    /// Constructs a writer with a preallocated buffer. The lifetime of the
    /// buffer must be greater or equal to the lifetime of the writer.
    this(ElementType[] buffer) {
        _buffer = buffer;
    }

    /// The number of elements that have been written to.
    size_t length() const {
        return _length;
    }

    /// The elements that have been written to.
    ///
    /// Returns: A slice into the written portion of the writer's buffer.
    inout(ElementType)[] data() inout {
        return _buffer[0 .. _length];
    }

    void clear() {
        _length = 0;
    }

    /// Writes a new element to the buffer. If the buffer is at capacity, this
    /// is a no-op.
    void put(in ElementType e) {
        if (_length == _buffer.length)
            return;
        
        _buffer[_length] = e;
        _length++;
    }

    /// Writes an array of elements to the buffer. If the array would cause the
    /// buffer to exceed capacity, this is s no-op.
    void put(in ElementType[] e) {
        if (_length + e.length > _buffer.length)
            return;
        
        _buffer[_length .. _length + e.length] = e;
        _length += e.length;
    }

    void put(R)(auto ref R range) if (isInputRange!R) {
        while (_length < _buffer.length && !range.empty) {
            _buffer[_length] = range.front;
            range.popFront();
            _length++;
        }
    }

private:
    size_t _length;
    ElementType[] _buffer;
}
