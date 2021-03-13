module flare.core.list;

mixin template intrusive_list(T) {
    T* prev, next;

    struct ListHead {
        T* first, last;

        size_t length;

        bool is_empty() {
            return length == 0;
        }

        void push_front(T* new_node) {
            if (is_empty) {
                first = last = new_node;
            }
            else {
                assert(last);
                new_node.next = first;
                first.prev = new_node;
                first = new_node;
            }

            length++;
        }

        void push_back(T* new_node) {
            if (is_empty) {
                first = last = new_node;
            }
            else {
                assert(first);
                new_node.prev = last;
                last.next = new_node;
                last = new_node;
            }

            length++;
        }

        T* pop_front() {
            if (is_empty)
                return null;

            auto node = first;
            assert(node.prev is null);

            first = node.next;
            if (first) first.prev = null;
            else last = null;
            length--;

            node.prev = node.next = null;
            return node;
        }

        T* pop_back() {
            if (is_empty)
                return null;

            auto node = last;
            assert(node.next is null);

            last = node.prev;
            if (last !is null) last.next = null;
            else first = null;
            length--;

            node.prev = null;
            return node;
        }

        T* opIndex(size_t index) {
            for (auto node = first; node !is null; node = node.next) {
                if (index == 0)
                    return node;

                index--;
            }

            return null;
        }
    }
}

unittest {
    struct Foo {
        int value;

        mixin intrusive_list!Foo;
    }

    Foo.ListHead list;

    assert(list.is_empty);
    list.push_front(new Foo(100));
    assert(!list.is_empty);
    assert(list[0].value == 100);

    list.push_back(new Foo(200));
    assert(list[0].value == 100);
    assert(list[1].value == 200);

    assert(list.pop_back().value == 200);
    assert(list.pop_back().value == 100);
    assert(list.is_empty());

    foreach (i; 0 .. 100)
        list.push_back(new Foo(i));
    
    foreach (i; 0 .. 100)
        assert(list.pop_front().value == i);
    assert(list.is_empty());
}
