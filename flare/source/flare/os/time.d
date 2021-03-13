module flare.os.time;

Duration msecs(double dur) {
    return from_msecs_impl(dur);
}

Duration secs(double dur) {
    return from_secs_impl(dur);
}

/**
 An instant in time measured using the operating system's high-resolution timer.
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

struct Duration {
    private double _raw_delta = 0;

@safe @nogc pure nothrow:
    double to_msecs() const {
        return to_msecs_impl(this);
    }

    Duration opBinary(string op)(Duration rhs) const if (op == "+" || op == "-") {
        mixin("return Duration(_raw_delta " ~ op ~ " rhs._raw_delta);");
    }

    double opBinary(string op)(Duration rhs) const if (op == "*" || op == "/") {
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

/// TODO: struct(DeltaTime) and Time - Time

/**
 An instant in time in a more digestible format with millisecond resolution.
 */
struct TimeStamp {
    import std.bitmanip: bitfields;

    alias StringBuffer = char[23];

    /// The year of the Gregorian Calendar.
    short year;

    /// Milliseconds past the current second.
    ushort milliseconds;

@safe @nogc pure nothrow:

    mixin(bitfields!(
        uint, "month", 5,
        uint, "day", 6,
        uint, "hour", 6,
        uint, "minute", 7,
        uint, "second", 7,
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

/// Retrieve the current system time from the OS's high-resolution timer for
/// time-delta measurements.
Time get_time() @trusted @nogc nothrow {
    return get_time_impl();
}

/// Retrives the current system time from the OS's high-resolution timer since
/// the UNIX Epoch.
TimeStamp get_timestamp() @trusted @nogc nothrow {
    return get_timestamp_impl();
}

private:

version (Windows) {
    import core.sys.windows.windows;

    immutable double perf_counter_frequency_hz;
    immutable real perf_counter_frequency_msecs;

    shared static this() {
        long hz;
        if (!QueryPerformanceFrequency(&hz))
            assert(false, "Failed to determine system timer frequency.");
        perf_counter_frequency_hz = hz;
        perf_counter_frequency_msecs = real(perf_counter_frequency_hz) / 1000;
    }

    // Because core.sys.windows.windows does not export this function.
    extern (Windows) void GetSystemTimePreciseAsFileTime(LPFILETIME) @nogc nothrow;

    Time get_time_impl() @trusted @nogc nothrow {
        long time;
        const qpc_err = QueryPerformanceCounter(&time);
        assert(qpc_err != 0);

        return Time(time);
    }

    double to_msecs_impl(Duration d) @safe @nogc pure nothrow {
        return d._raw_delta / perf_counter_frequency_msecs;
    }

    Duration from_msecs_impl(double d) {
        return Duration(d * perf_counter_frequency_msecs);
    }

    Duration from_secs_impl(double d) {
        return Duration(d * perf_counter_frequency_hz);
    }

    TimeStamp get_timestamp_impl() @trusted @nogc nothrow {
        // Note, this is available only for >= Windows 8. We should be ok,
        // right???
        FILETIME file_time;
        GetSystemTimePreciseAsFileTime(&file_time);

        SYSTEMTIME system_time;
        const err = FileTimeToSystemTime(&file_time, &system_time);
        assert(err != 0);

        with (system_time)
            return TimeStamp(
                    wYear,
                    wMonth,
                    wDay,
                    wHour,
                    wMinute,
                    wSecond,
                    wMilliseconds
            );
    }
}
else
    static assert(false, "Unsupported platform");
