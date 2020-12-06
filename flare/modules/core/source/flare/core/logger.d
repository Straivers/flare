/**
 Usage:

 auto logger = Logger(LogLevel.All);
 logger.add_sink(new ConsoleLogger(true));

 logger.info("Hello");
 */
module flare.core.logger;

import flare.core.time : TimeStamp, get_timestamp;

/**
 Enumeration of logger levels of detail.
 */
enum LogLevel : ubyte {
    /// Every log is recorded. Currently equivalent to LogLevel.Trace.
    All = 0,
    /// Logs that provide added detail for identifying bugs.
    Trace = 1,
    /// Logs that describe actions or state that may be useful for a user or
    /// developer to know, such as the program's operating mode.
    Info = 2,
    /// Logs of events that may cause degraded performance or functionality.
    Warn = 3,
    /// Logs of unexpected circumstances that prevented or interrupted normal
    /// execution.
    Error = 4,
    /// End of program logs when an unrecoverable error has been encountered.
    Fatal = 5,
    /// Logging is disabled.
    Off = ubyte.max,
}

/**
 A record of a logged event.

 Because every event is of fixed size, memory waste caused by copying or saving
 these events could by quite wasteful. Therefor, they should be passed by
 reference whenever possible, and copied or preserved only when absolutely
 necessary.
 */
struct LogEvent {
@safe @nogc pure nothrow:
    static assert(typeof(this).sizeof == 256);

    /// The maximum length of any log message. This does not include the
    /// timestamp and other metadata.
    enum max_message_length = 208;

    /// The time at which the log was generated.
    TimeStamp time;
    /// The level of detail at which this log event was created.
    LogLevel level;
    /// The length of the string message.
    ubyte message_length;
    /// The line within the file where the log event was created.
    uint line;
    /// The name of the file where the log event was created.
    string module_name;
    /// The name of the function that generated the log event.
    string func_name;
    /// The message provided by the creator of the log event.
    char[max_message_length] message_storage;

    /// Constructs a log event without a message.
    this(TimeStamp time, LogLevel lod, string mod, uint line, string func) {
        this.time = time;
        this.level = lod;
        this.line = line;
        this.module_name = mod;
        this.func_name = func;
    }

    ///
    void set_message(in char[] message)
    in (message.length <= message_storage.length) {
        message_length = cast(ubyte) message.length;
        message_storage[0 .. message_length] = message;
    }

    ///
    const(char)[] get_message() const return  {
        return message_storage[0 .. message_length];
    }
}

/**
 A Logger is a tool for exporting program state to be intelligible by a reader
 during or after program execution without interacting with the program state
 itself. It is typically used for diagnostics, recording state that may be
 useful for determining the causes of a crash or other flaw.

 This Logger can be composed into a parent-tree by calling `set_parent_logger()`
 with a 'higher-level' logger. When a log is submitted to the logger, it will
 process it, then pass it on to its parent.
 */
struct Logger {

    /// The maximum number of event sinks that the logger can have registered at
    /// any time.
    enum max_event_sinks = 16;

@safe nothrow public:
    import flare.core.time : get_time;

    /// Initialize this logger with a minimum level of detail, and an optional
    /// parent.
    @nogc this(LogLevel level, Logger* parent = null) {
        _level = level;
        _parent = parent;
    }

    ~this() {
        for (int i = 0; _event_sinks[i]; i++)
            _event_sinks[i].end_logging();

        _level = LogLevel.All;
        _event_sinks[] = null;
        _parent = null;
    }

    /// Adjusts the level of detail filtering for this logger.
    @nogc void log_level(LogLevel new_level) {
        _level = new_level;
    }

    @nogc LogLevel log_level() {
        return _level;
    }

    /// Add an output location for this logger.
    SinkId add_sink(LogEventSink sink) {
        foreach (ubyte i, ref _sink; _event_sinks)
            if (_sink is null) {
                _sink = sink;
                _sink.begin_logging();
                return SinkId(i);
            }

        return SinkId.invalid;
    }

    /// Retrieves the event sink identified by `id`.
    @nogc LogEventSink get_sink(SinkId id) {
        return _event_sinks[id.value];
    }

    /// Remove an output location from this logger.
    void remove_sink(SinkId id) {
        _event_sinks[id.value].end_logging();

        // Find the last logger and move it into this slot. This allows us to
        // avoid iterating over the whole array -empty elements and all- during
        // log_event()
        foreach_reverse (ref last; _event_sinks) {
            if (last) {
                _event_sinks[id.value] = last;
                last = null;
                return;
            }
        }
    }

    void all(Args...)(string fmt, Args args, uint line = __LINE__, string mod = __MODULE__, string func = __PRETTY_FUNCTION__) {
        log!(LogLevel.All)(fmt, args, line, mod, func);
    }

    void trace(Args...)(string fmt, Args args, uint line = __LINE__, string mod = __MODULE__, string func = __PRETTY_FUNCTION__) {
        log!(LogLevel.Trace)(fmt, args, line, mod, func);
    }

    void info(Args...)(string fmt, Args args, uint line = __LINE__, string mod = __MODULE__, string func = __PRETTY_FUNCTION__) {
        log!(LogLevel.Info)(fmt, args, line, mod, func);
    }

    void warn(Args...)(string fmt, Args args, uint line = __LINE__, string mod = __MODULE__, string func = __PRETTY_FUNCTION__) {
        log!(LogLevel.Warn)(fmt, args, line, mod, func);
    }

    void error(Args...)(string fmt, Args args, uint line = __LINE__, string mod = __MODULE__, string func = __PRETTY_FUNCTION__) {
        log!(LogLevel.Error)(fmt, args, line, mod, func);
    }

    void fatal(Args...)(string fmt, Args args, uint line = __LINE__, string mod = __MODULE__, string func = __PRETTY_FUNCTION__) {
        log!(LogLevel.Fatal)(fmt, args, line, mod, func);
    }

    /**
     Logs an event. the event is first checked for level of detail, then sent
     passed to each LogEventSink registered to this logger. Finally, it is
     passed on to its parent logger if one was provided.
     */
    void log(LogLevel level, Args...)(string fmt, Args args, uint line, string mod, string func) {
        import std.format : sformat;

        if (level > 0 && level < _level)
            return;

        char[LogEvent.max_message_length] msgbuf;

        auto event = LogEvent(get_timestamp(), level, mod, line, func);
        try
            event.set_message(sformat(msgbuf, fmt, args));
        catch (Exception e)
            event.set_message("ERR LOG MESSAGE TOO LONG");

        log_event(event);
    }

private:
    void log_event(in LogEvent event) {
        for (int i = 0; _event_sinks[i]; i++)
            _event_sinks[i].log_event(event);

        if (_parent)
            _parent.log_event(event);
    }

    LogLevel _level;
    Logger* _parent;
    LogEventSink[max_event_sinks] _event_sinks;
}

/// A Logger-unique identifier for an event sink. Use this to control and remove
/// sinks individually.
struct SinkId {
    enum invalid = SinkId(ubyte.max);

    ubyte value;
}

/**
 This interface defines the functions necessary that a logger requires in order
 to output log events.

 We use an interface here instead of a function pointer for a few reasons:
 1. Assuming a release configuration, where the vast majority of events are
    `LogLevel.Trace` and are ignored, the frequency with which a `LogEventSink`
    should be reasonably small.
 2. Using an interface allows us to bring sink-specific data physically closer
    to the output implementation, hopefully reducing mental overhead.
 */
interface LogEventSink {
    /// Called on sink registration with a logger. Open files, initialize
    /// sockets, or do any other pre-logging setup here.
    @safe void begin_logging() nothrow;

    /// Process an event for output.
    @safe void log_event(in LogEvent) nothrow;

    /// Flush any buffers to their destinations immediately.
    @safe void flush() nothrow;

    /// Called on sink deregistration or logger destruction. Close files,
    /// terminate sockets, or any other cleanup here.
    @safe void end_logging() nothrow;
}

/**
 Colorized `stdout` implementation of LogEventSink.

 Log events are buffered up to `event_buffer_size` events.
 */
final class ConsoleLogger : LogEventSink {

    /// The number of log events to buffer before writing them out to `stdout`.
    enum event_buffer_size = 2;

public:
    this(bool colorize) {
        _colorized = colorize;
    }

    override void begin_logging() {
        // no-op
    }

    override void log_event(in LogEvent event) {
        if (_buff_size == _buffer.length)
            flush();

        _buffer[_buff_size] = event;
        _buff_size++;
    }

    override void flush() {
        import std.format : formattedWrite;
        import flare.core.buffer_writer : Writer;
        import core.stdc.stdio : printf;

        char[512] out_buffer;
        TimeStamp.StringBuffer ts_buffer;

        auto writer = Writer!char(out_buffer);
        foreach (ref event; _buffer[0 .. _buff_size]) {
            auto ts = event.time.write_string(ts_buffer);

            try {
                if (_colorized)
                    writer.put(colors[event.level]);

                writer.formattedWrite!"%23s %s"(ts, text[event.level]);
                debug writer.formattedWrite!"{%s:%s} "(event.module_name, event.line);
                writer.put(event.get_message());
                writer.put("\033[0m\n\0");
                () @trusted { printf(&writer.data()[0]); }();
            }
            catch (Exception e)
                return;
            finally
                writer.clear();
        }

        _buff_size = 0;
    }

    override void end_logging() {
        flush();
    }

private:
    // dfmt off
    immutable colors = [
        ""       , // LogLevel.All
        "\033[0m", // LogLevel.Trace
        "\033[96m", // LogLevel.Info
        "\033[33m", // LogLevel.Warn
        "\033[31m", // LogLevel.Error
        "\033[91m", // LogLevel.Fatal
    ];

    immutable text = [
        "",         // LogLevel.All
        "[Trace] ",  // LogLevel.Trace
        "[Info ] ",   // LogLevel.Info
        "[Warn ] ",   // LogLevel.Warn
        "[Error] ",  // LogLevel.Error
        "[Fatal] ",  // LogLevel.Fatal
    ];
    // dfmt on

    bool _colorized;
    ubyte _buff_size;
    LogEvent[event_buffer_size] _buffer;
}
