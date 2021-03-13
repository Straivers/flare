module flare.math.vector;

alias float2 = Vector!(float, 2);
alias float3 = Vector!(float, 3);

struct Vector(T, size_t n_dimensions) {
    union {
        T[n_dimensions] values;

        struct {
            static if (n_dimensions > 0)
                T x;
            
            static if (n_dimensions > 1)
                T y;
            
            static if (n_dimensions > 2)
                T z;
            
            static if (n_dimensions > 3)
                T w;
        }

        struct {
            static if (n_dimensions > 0)
                T r;
            
            static if (n_dimensions > 1)
                T g;
            
            static if (n_dimensions > 2)
                T b;
            
            static if (n_dimensions > 3)
                T a;
        }
    }

    this(T[] parts...) {
        assert(parts.length <= n_dimensions);
        values[0 .. parts.length] = parts;
    }
}
