module flare.util.ring_buffer;

struct FixedRingBuffer(T, size_t size) {

    bool is_empty() {
        return _read_pos == _write_pos;
    }

    size_t count() {
        return _write_pos - _read_pos;
    }

    void push_back(T t) {
        _buffer[_write_pos % _buffer.length] = t;
        _write_pos++;

        // Overwrite oldest element.
        if (_write_pos - _read_pos > _buffer.length)
            _read_pos++;
    }

    T pop_front() {
        scope(exit) _read_pos++;
        return _buffer[_read_pos % _buffer.length];
    }

private:
    T[size] _buffer;
    size_t _read_pos;
    size_t _write_pos;
}

unittest {
    FixedRingBuffer!(uint, 4) buf;

    assert(buf.is_empty);

    buf.push_back(1);
    assert(!buf.is_empty);

    assert(buf.pop_front() == 1);
    assert(buf.count == 0);
    assert(buf.is_empty);

    foreach (i; 2 .. 6)
        buf.push_back(i);
    assert(buf.count == 4);
    assert(!buf.is_empty);

    foreach (i; 2 .. 6)
        assert(buf.pop_front() == i);
    assert(buf.count == 0);
    assert(buf.is_empty);

    foreach (i; 10 .. 20)
        buf.push_back(i);
    assert(buf.count == 4);
    assert(!buf.is_empty);

    assert(buf.pop_front() == 16);
    assert(buf.pop_front() == 17);
    assert(buf.pop_front() == 18);
    assert(buf.pop_front() == 19);
}
