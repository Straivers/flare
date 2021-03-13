module flare.os.types;

version (Windows) {
    import core.sys.windows.windows: HWND;

    alias OsWindow = HWND;
}
