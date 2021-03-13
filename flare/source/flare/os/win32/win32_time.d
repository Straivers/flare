module flare.os.win32.win32_time;

version (Windows):

import flare.os.time;
import core.sys.windows.windows;

final class Win32Clock : OsClock {
    this() {
        long hz;
        if (!QueryPerformanceFrequency(&hz))
            assert(false, "Failed to determine system timer frequency.");
        performance_counter_frequency = hz;
    }

    Time get_time() @trusted @nogc nothrow {
        long time;
        if (QueryPerformanceCounter(&time))
            return Time(time / performance_counter_frequency);
        assert(0, "Failed to query high-resolution timer.");
    }

    TimeStamp get_timestamp() @trusted @nogc nothrow {
        FILETIME file_time;
        GetSystemTimePreciseAsFileTime(&file_time);

        SYSTEMTIME sys;
        if (!FileTimeToSystemTime(&file_time, &sys))
            assert(0, "Failed to retrieve high-resolution timestamp information.");

        return TimeStamp(
                sys.wYear,
                sys.wMonth,
                sys.wDay,
                sys.wHour,
                sys.wMinute,
                sys.wSecond,
                sys.wMilliseconds
        );
    }

private:
    double performance_counter_frequency;
}

private:

extern (Windows) void GetSystemTimePreciseAsFileTime(LPFILETIME) @nogc nothrow;
