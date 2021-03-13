module flare.util.functions;

auto if_not_null(Fn, Args...)(Fn fn, Args args) {
    if (fn)
        return fn(args);
}
