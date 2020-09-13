module flare.core.time;

/**
 An instant in time measured using the operating system's high-resolution timer.
 */
struct Time {
@safe @nogc nothrow:

    private long _raw_time;
}

/// TODO: struct(DeltaTime) and Time - Time

/**
 An instant in time in a more digestible format with millisecond resolution.
 */
struct TimeStamp {
    alias StringBuffer = char[23];

    /// The year of the Gregorian Calendar.
    short year;
    /// The month of a Gregorian year. 0 is January.
    ubyte month;
    /// The day of a Gregorian month.
    ubyte day;
    /// Hours past midnight, between 0-23.
    ubyte hour;
    /// Minutes past the current hour, between 0-59.
    ubyte minute;
    /// Seconds past the current minute between 0-60. It will only be 60 on a
    /// leap second.
    ubyte second;
    /// Milliseconds past the current second.
    short milliseconds;

    /// Writes the time as a string in ISO 8601 form to the buffer.
    ///
    /// Returns: The portion of the buffer that was written to.
    char[] write_string(char[] buffer) @safe @nogc const pure nothrow {
        // We use our own conversion to chars to ensure @nogc compatibility.
        import flare.core.buffer_writer : Writer;
        import flare.core.conv : to_chars;

        auto writer = Writer!char(buffer);

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
        char[60] b;
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

    // Because core.sys.windows.windows does not export this function.
    extern (Windows) void GetSystemTimePreciseAsFileTime(LPFILETIME) @nogc nothrow;

    Time get_time_impl() @trusted @nogc nothrow {
        long time;
        const qpc_err = QueryPerformanceCounter(&time);
        assert(qpc_err == 0);

        return Time(time);
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
                    cast(ubyte) wMonth,
                    cast(ubyte) wDay,
                    cast(ubyte) wHour,
                    cast(ubyte) wMinute,
                    cast(ubyte) wSecond,
                    wMilliseconds
            );
    }
}
else
    static assert(false, "Unsupported platform");
