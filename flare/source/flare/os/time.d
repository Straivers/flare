module flare.os.time;

Duration msecs(double dur) {
    return Duration(dur / 1000);
}

Duration secs(double dur) {
    return Duration(dur);
}

/**
An instant in time in seconds, taken from the OS' high-resolution timer.
*/
struct Time {
    private double _raw_time;

@safe @nogc pure nothrow:
    Duration opBinary(string op = '-')(in Time rhs) const {
        assert(_raw_time >= rhs._raw_time);

        return Duration(_raw_time - rhs._raw_time);
    }

    Time opBinary(string op)(Duration duration) const {
        return Time(_raw_time + duration._raw_delta);
    }
}

/**
A duration of time in seconds.
*/
struct Duration {
    private double _raw_delta = 0;

@safe @nogc pure nothrow:
    double to_msecs() const {
        return _raw_delta * 1000;
    }

    Duration opBinary(string op)(Duration rhs) const if (op == "+" || op == "-") {
        mixin("return Duration(_raw_delta " ~ op ~ " rhs._raw_delta);");
    }

    double opBinary(string op)(Duration rhs) const if (op == "/") {
        mixin("return _raw_delta " ~ op ~ " rhs._raw_delta;");
    }

    Duration opBinary(string op)(double rhs) const if (op == "*" || op == "/") {
        mixin("return Duration(_raw_delta " ~ op ~ " rhs);");
    }

    Duration opOpAssign(string op)(Duration rhs) {
        mixin("_raw_delta " ~ op ~ "= rhs._raw_delta;");
        return this;
    }

    int opCmp(Duration rhs) const {
        if (_raw_delta < rhs._raw_delta)
            return -1;
        if (_raw_delta > rhs._raw_delta)
            return 1;
        return 0;
    }
}

/**
 An instant in time in a more digestible format with millisecond resolution.
 */
struct TimeStamp {
    import std.bitmanip: bitfields;

    alias StringBuffer = char[23];

@safe @nogc pure nothrow:

    mixin(bitfields!(
        uint, "year", 16,
        uint, "month", 5,
        uint, "day", 6,
        uint, "hour", 6,
        uint, "minute", 7,
        uint, "second", 7,
        uint, "milliseconds", 16,
        uint, "", 1
    ));

    this(short year, uint month, uint day, uint hour, uint minute, uint second, ushort milliseconds) {
        this.year = year;
        this.month = month;
        this.day = day;
        this.hour = hour;
        this.minute = minute;
        this.second = second;
        this.milliseconds = milliseconds;
    }

    /// Writes the time as a string in ISO 8601 form to the buffer.
    ///
    /// Returns: The portion of the buffer that was written to.
    char[] write_string(char[] buffer) const {
        // We use our own conversion to chars to ensure @nogc compatibility.
        import flare.util.buffer_writer : TypedWriter;
        import flare.util.conv : to_chars;

        auto writer = TypedWriter!char(buffer);

        char[20] scratch_space;

        void put_padded(int value) {
            auto part = value.to_chars(scratch_space);
            if (part.length == 1)
                writer.put('0');
            writer.put(part);
        }

        writer.put(year.to_chars(scratch_space));
        writer.put('-');
        put_padded(month);
        writer.put('-');
        put_padded(day);
        writer.put('T');
        put_padded(hour);
        writer.put(':');
        put_padded(minute);
        writer.put(':');
        put_padded(second);
        writer.put('.');
        writer.put(milliseconds.to_chars(scratch_space));

        return writer.data;
    }

    unittest {
        char[23] b;
        assert(TimeStamp(2020, 9, 13, 2, 43, 7, 671).write_string(b) == "2020-09-13T02:43:07.671");
    }
}

interface OsClock {
    Time get_time() @trusted @nogc nothrow;

    TimeStamp get_timestamp() @trusted @nogc nothrow;
}
