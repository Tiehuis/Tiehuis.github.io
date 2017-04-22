---
title: Generic Data Structures in C
layout: post
---

<small>*See [here](https://gist.github.com/tiehuis/6e10dfa4a36c1f414b3119dd1b77fa6b)
for a final implementation if you don't want to read all this.*</small>

Generic data structures in C typically have a pretty unfriendly API. They
either rely on void pointers and erase type information or have resort to
macros to provide a semblance of the templating system found in C++.

This post will look at constructing a macro-based vector in C with a focus on
ease of use. We will use modern C11 features and ample compiler extensions to
see where we can take this.

A Generic Vector
----------------

First, lets define our vector type. We'll call it `qvec` because its
short and sweet.

```c
#define qvec(T)             \
    struct qvec_##T {       \
        size_t cap, len;    \
        T data[];           \
    }
```

We take a parameter `T` which will represent the type that is stored in our
vector. This will be templatized at compile-time, similar to how `vector<T>` is
in C++.

The `data` field is a [flexible array
member](https://en.wikipedia.org/wiki/Flexible_array_member)
from C99.

<small>*Note: We will forgo error checking of `malloc` and `realloc`
for simplicity.*</small>

### `new`

The `new` function should `malloc` enough memory for some initial members.
The size of the required storage will depend on the size of `T`. A possible
implementation could be

```c
#define qvec_new(T, v)                                       \
do {                                                         \
    size_t initial_size = 16;                                \
    v = malloc(sizeof(qvec(T)) + sizeof(T) * initial_size);  \
    v->cap = initial_size;                                   \
    v->len = 0;                                              \
} while (0)
```

which we can use to initialize a vector of integers as

```c
qvec(int) *v;
qvec_new(int, v);
```

The flexible array member allows us to get away with a single call to `malloc`
which is a minor nicety. Otherwise, this is a little underwhelming. The
seperation of declaration and initializtion is not ideal.

To make this a bit nicer, we can use [statement expressions](https://gcc.gnu.org/onlinedocs/gcc/Statement-Exprs.html#Statement-Exprs)
which allow multiple statements to be used as an expression.
Our new definition for `new` would then be

```c
#define qvec_new(T)                                                           \
({                                                                            \
    const size_t initial_size = 16;                                           \
    struct qvec_##T *v = malloc(sizeof(qvec(T)) + sizeof(T) * initial_size);  \
    v->cap = initial_size;                                                    \
    v->len = 0;                                                               \
    v;                                                                        \
})
```

which gives us the much more natural usage

```c
qvec(int) *v = qvec_new(int);
```

Standard Functions
------------------

Lets now implement the common vector functions `push`, `pop` and `at`.

### `pop`

`pop` doesn't require any special knowledge of the type `T` so this is simply

```c
#define qvec_pop(v) (v->data[--v->len])
```

### `at`

`at` is slightly more interesting. When working with a C++ vector (or a
standard C array), the notation `array[x]` is an `lvalue` which can be
assigned to. It would be nice if our `qvec` has this property as well.

First, lets define the helper function

```c
#define qvec_ref(v, i) (&v->data[i])
```

This returns an `lvalue` and so can be used with a pointer dereference. e.g.
`*qvec_ref(v, i) = 5`.

We can wrap this in another macro to hide this dereference

```c
#define qvec_at(v, i) (*(qvec_ref(v, i)))
```

### `push`

`push` presents a small problem. If we were to generate a standard
implementation

```c
#define qvec_push(v, i)                                 \
({                                                      \
    if (v->len >= v->cap) {                             \
        v->cap *= 2;                                    \
        v = realloc(v, sizeof(?) * v->cap * sizeof(?)); \
    }                                                   \
    v->data[v->len++] = (i);                            \
})
```

we might be left wondering what to insert into the `?` marked locations.

The second `?` is less worrying. This should be `sizeof(T)`. We could just pass
the type again, but doing it on every push is not ideal. In fact, we don't need
any new information. Recall that the `data` field of `qvec` is of type `T[]`.
Performing a dereference of this will give us the size of a single `T`, exactly
what we want!

The first `?` is more bothersome. We are interested in determining the value of
`sizeof(qvec(T))`. We can't use the `data` field here, since the `T` required
here is the actual typename used during initialization. This would be viable if
it were possible to generate a type name from an arbitrary variable but
unfortunately we cannot do this.

The way to get this size is first to realise that the `data` member in a `qvec`
doesn't actually take up any space within the array, not even for a pointer.

We can confirm this by checking the following

```c
struct {
    char a, b;
    char b[]
} foo;

printf("foo is %zu bytes\n", sizeof(foo));
```

which will print

```
foo is 2 bytes
```

Since this `data` doesn't take any space, we can see that the other members
(`len` and `cap`) have a fixed type and therefore size, regardless of the type
of `T`.

We can seperate the type of `qvec` into

```c
#define qvec_base       \
    struct {            \
        size_t cap, len;\
    }

#define qvec(T)         \
    struct qvec_##T {   \
        qvec_base;      \
        T data[];       \
    }
```

This now allows us to query the size of the type-independent part of a `qvec`
while retaining access to all the members in the same way.

As an aside, we can define this using less macro-wizadry if we enable the
`-fplan9-extensions` option in GCC as documented [here](https://gcc.gnu.org/onlinedocs/gcc/Unnamed-Fields.html).

```c
struct qvec_base {
    size_t cap, len;
}

#define qvec(T)             \
    struct qvec_##T {       \
        struct qvec_base;   \
        T data[];           \
    }
```

This allows embedding of existing struct definitions as an anonymous struct.

Now, finally, we can define our `push` function as:

```c
#define qvec_push(v, i)                                                 \
({                                                                      \
    if (v->len >= v->cap) {                                             \
        v->cap *= 2;                                                    \
        v = realloc(v, sizeof(qvec_base) * v->cap * sizeof(*v->data));  \
    }                                                                   \
    v->data[v->len++] = (i);                                            \
})
```

### `free`

Since we only use a single `malloc` to initialize the type, this is simply

```c
#define qvec_free(v) free(v)
```

### API so far

Lets see what this gives us so far

```c
qvec(int) *iv = qvec_new(int);
qvec_push(iv, 5);
qvec_push(iv, 8);
printf("%d\n", qvec_at(iv, 0));
qvec_at(iv, 1) = 5;
qvec_free(iv);
```

and compared to similar C++ vector

```c++
std::vector<int> iv;
iv.push_back(5);
iv.push_back(8);
printf("%d\n", iv[0]);
iv[1] = 5;
```

Looking okay, but lets go a bit further.

Extended Functions
------------------

### Generic Printing

It is fairly common that we want to dump the values of a vector to see what is
inside. If we wanted to write this for an integer vector, the following would
work

```c
#define qvec_int_print(v)               \
({                                      \
    printf("[");                        \
    for (int i = 0; i < v->len; ++i) {  \
        printf("%d", v->data[i]);       \
        if (i + 1 < v->len)             \
            printf(", ");               \
    }                                   \
    printf("]\n");                      \
})
```

which can be used as

```c
qvec_print(iv); // [5, 5]
```

This is nice, but since it isn't generic it has a limited use case. Fortunately
for us, C11 brings some new interesting features to the table which we can use.

The C11 `_Generic` keyword allows rudimentary switching based on the type of
its input. Think of it just as a **compile-time switch statement on types**.

For example, we could construct a macro to print the name of a type

```c
#define type_name(x) _Generic((x), int: "int", float: "float")

printf("This is a %s\n", type_name(5.0f));
printf("This is a %s\n", type_name(5));
```

which when run would output

```
This is a float
This is a int
```

We can use this to generate the appropriate `printf` format specifier for the
passed type.

```c
#define GET_FMT_SPEC(x) _Generic((x), int: "%d", float: "%f", char*: "%s")
```

and modifying our print function

```c
#define qvec_print(v)                   \
({                                      \
    printf("[");                        \
    for (int i = 0; i < v->len; ++i) {  \
        printf(GET_FMT_SPEC(v->data[i]), v->data[i]);\
        if (i + 1 < v->len)             \
            printf(", ");               \
    }                                   \
    printf("]\n");                      \
 })
```

This would now work on an integer and float `qvec` type with no modifications.
Of course, we could extend `GET_FMT_SPEC` with whatever types we need.

*You may recall that I mentioned that we could solve an earlier issue regarding
our `push` function if we could generate a type name from a variable. It seems
like the `_Generic` keyword would help is achieve this and indeed it does in
part. The problem is that it is evaluated after preprocessing, so we cannot use
its output as part of the preprocessor token concatenation process.*

*This is an easy mistake to make, since `_Generic` is seen pretty much solely
within macro definitions for obvious reasons. This isn't required though,
the following being perfectly valid code.*

```c
int a;
float b;

printf("%s\n", _Generic(a, int: "a is an int", float: "a is a float"));
printf("%s\n", _Generic(b, int: "b is an int", float: "b is a float"));
```

Initializer Lists
-----------------

Since C++11, vectors can now be initialized with initializer lists

```c++
std::vector<int> = {4, 5, 2, 3};
```

This is pretty nice. Let's add something similar to our `new` function using
C99 variadic macros with a [GCC extension](https://gcc.gnu.org/onlinedocs/cpp/Variadic-Macros.html)
which allows an arbitrary name to be given for them.

```c
#define QVEC_ALEN(a) (sizeof(a) / sizeof(*a))

#define qvec_new(T, xs...)                                                    \
({                                                                            \
    const size_t initial_size = 16;                                           \
    const T _xs[] = {xs};                                                     \
    struct qvec_##T *v = malloc(sizeof(qvec(T)) + sizeof(T) * QVEC_ALEN(_xs));\
    v->cap = initial_size;                                                    \
    v->len = QVEC_ALEN(_xs);                                                  \
    for (int i = 0; i < v->len; ++i)                                          \
        v->data[i] = _xs[i];                                                  \
    v;                                                                        \
})
```

`xs` here collects all arguments except the first. We assign these to a
temporary array which allows us to work with the values, but also has the effect
of typechecking the values.

```c
qvec(int) *v = qvec_new(int, 4, 5, 2, 3);
```

Complex Objects
---------------

Suppose we have the following type

```c
typedef struct {
    char *id;
    bool is_tasty;
} Food;
```

We might try and utilize C99 struct initializers to perform the following

```c
qvec(Food) *v = qvec_new(Food);
qvec_push(v, { .id = "apple", .is_tasty = true });
```

This however fails to compile. Under clang, we get the following error

```text
qvec.c:103:34: error: too many arguments provided to function-like macro
      invocation
    qvec_push(v, { "strawberry", 1 });
                                 ^
qvec.c:42:9: note: macro 'qvec_push' defined here
#define qvec_push(v, i)                                                       \
        ^
qvec.c:103:5: note: cannot use initializer list at the beginning of a macro
      argument
    qvec_push(v, { "strawberry", 1 });
    ^            ~~~~~~~~~~~~~~~~~~~~
qvec.c:103:5: error: use of undeclared identifier 'qvec_push'
    qvec_push(v, { "strawberry", 1 });
    ^
```

The reason this doesn't work is that the C preprocessor is dumb. It doesn't know
that this is a designated initializer because it doesn't actually know anything
about the C language. Instead, it sees two arguments. The first being
`{ .id = "apple"` and the second `.is_tasty = true }`.




The can get around this is by using the previously mentioned variadic macros once
again. Using a similar technique to the previously extended `new` function.

```c
#define qvec_push(v, xs...)                                             \
({                                                                      \
    const typeof(*v->data) _xs[] = {xs};                                \
    if (v->len + QVEC_ALEN(_xs) >= v->cap) {                            \
        while (v->cap <= v->len + alen(_xs)) {                          \
            v->cap = 2 * v->cap;                                        \
        }                                                               \
        v = realloc(v, sizeof(qvec_base) + v->cap * sizeof(*v->data));  \
    }                                                                   \
    for (int i = 0; i < QVEC_ALEN(_xs); ++i) {                          \
        v->data[v->len++] = _xs[i];                                     \
    }                                                                   \
    v;                                                                  \
})
```

The reason variadic macros help here is that all macro arguments are gathered at
once and treated as input to an array initializer. Even though individual
arguments are not valid tokens, it doesn't matter, since the full set of
argments is.

Another thing to note is the use of the
[`typeof`](https://gcc.gnu.org/onlinedocs/gcc/Typeof.html#Typeof) keyword. This
allows us to retrieve the type of an expression, which can be used to initialize
new types. The most common example of its usage is likely within a type-generic
swap macro.

```c
#define swap(x, y)              \
do {                            \
    const typeof(x) _temp = y;  \
    y = x;                      \
    x = _temp;                  \
} while (0)
```

Extensions, Extensions, Extensions
----------------------------------

Our code is already filled with compiler-specific C extensions, so we may as
well go overboard.

### RAII

One of the better features of C++ is the ability to utilize RAII to run
destructors on block exit. This reduces the chance that leaks occur within
programs and just makes using complex types much more pleasant.

The
[`cleanup`](https://gcc.gnu.org/onlinedocs/gcc-6.1.0/gcc/Common-Variable-Attributes.html)
variable attribute is a GCC extension which allows a user-defined cleanup
function to automatically run when the value goes out of scope.

This attribute takes one argument, a function of type `void cleanup(T**)` where
`T` is the type which this attribute is declared with.

Using this with our `qvec`, it may look like

```c
static inline _qvec_free(void **qvec) { free(*qvec); }

int main(void)
{
    qvec(int) __attribute__ ((cleanup(_qvec_free))) *qv = qvec_new(int);
    // No qvec_free here!
}
```

This is a little verbose however, so lets define our own *keyword* which we can
use instead.

```c
#define raii __attribute__ ((cleanup(_qvec_free)))

int main(void)
{
    raii qvec(int) *qv = qvec_new(int);
}
```

Note that an attribute doesn't strictly need to be specified after the type
definition.

This is nice, but if you had actually compiled the above you would get a number
of type errors.

```
qvec.c: In function ‘main’:
qvec.c:13:12: warning: passing argument 1 of ‘_qvec_free’ from incompatible pointer type [-Wincompatible-pointer-types]
     struct {                                                                  \
            ^
qvec.c:26:40: note: in expansion of macro ‘qvec_base’
     struct qvec_##T *v = malloc(sizeof(qvec_base) + sizeof(_xs));             \
                                        ^
qvec.c:94:25: note: in expansion of macro ‘qvec_new’
     raii qvec(int) *v = qvec_new(int);
                         ^
qvec.c:88:20: note: expected ‘void **’ but argument is of type ‘struct qvec_int **’
 static inline void _qvec_free(void **qvec) { free(*qvec); }
```

The compiler complains because we are relying on an implicit cast to void. We
know this is actually valid however, since every `qvec` is going to use a
single call to `free` in order to release its memory.

As far as I'm aware, this requires a pragma at the callsite to disable this
locally. This is quite inconvenient, and really loses out any usability that we
may have gained from using this. The following will compile without warnings

```c
int main(void)
{
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wincompatible-pointer-types"
    raii qvec(int) *v = qvec_new(int, 5, 4, 3);
#pragma GCC diagnotic pop
}
```

At this stage though, remembering to just manually free seems like a saner
choice.

### Type Inference

One of the nice features of C++11 onwards is the revitalization of the `auto`
keyword. This now provides type inference which is very nice in a number of
circumstances.

If we look at our vector initialization

```c
qvec(int) *v = qvec_new(int);
```

we clearly have a bit of redundancy. Unfortunately the C language doesn't support
type inference... as part of the standard at least. An interesting extension is
the [`_auto_type`](https://gcc.gnu.org/onlinedocs/gcc/Typeof.html) keyword which
provides some limited type inference capabilities.

Since the `auto` keyword is practically useless, lets just redefine it

<small>_Redefining keywords is usually a **very** bad idea. Although, GCC
[will allow it](https://gcc.gnu.org/onlinedocs/cpp/Macros.html#Macros)._</small>

```c
#define auto __auto_type

auto iv = qvec_new(int);
```

Although yet again, our expectations differ to reality. This will not compile!
The reason for this is that previously we were relying on the inline struct
definition of `qvec(T)` that was declared on every initialization. Without this
declaration, our new `auto` keyword cannot find any struct which matches the
return type and must fail.

As an example, the following works fine

```c
qvec(int) *a = qvec_new(int);
auto b = qvec_new(int);
```

because the `qvec(int)` declared the struct, so the next `qvec` return type can
be deduced correctly. This is simply an inherent limitation with the tools we
have. A simple solution would be simply forward declare our structs.

```c
qvec(int);

int main(void)
{
    auto a = qvec_new(int); // Ok!
}
```

But this is one extra line to type for each `qvec` type required!

Drawbacks
---------

We have a pretty good set of functions associated with our `qvec` so far.
Usability is ok and we have a few of the more desirable features of C++ in our
hands within C.

Undoubtedly however, there are some inherent problems that we just can't solve.

### Complex Container Types

We can do the following in C++

```c++
std::vector<std::vector<std::vector<int>>> v;
```

To do this with our `qvec` the following is required

```c
typedef qvec(int) qvec_int;
typedef qvec(qvec_int) qvec_qvec_int;
qvec(qvec_qvec_int) *v = qvec_new(qvec_qvec_int);
```

Recall back to our `new` implementation. We generate a struct with a name
`qvec_##T` where `T` is the type. Since this is concatenated to make an
identifier, the types *must* be comprised only of characters which can exist
within an identifier (`[_0-9A-Za-z]`). Any types which use other characters,
such as functions, pointers and even our own `qvec` types must have a typedef
before we can use them.

As an example, the following

```c
qvec(char**);
```

expands to the invalid struct declaration

```c
struct qvec_char** {
    size_t cap, len;
    char* data[];
};
```

### Too Much Inlining

Since we are dealing with macros, every call is going to generate the same code
at the call site. This isn't too big a deal with our `qvec`, since a vector is
inherently pretty simple, but if we wanted to use the same techniques to
construct a generic hashmap, for example, the code duplication would be much
worse.

This is where the generic containers which rely on simply generating the
required functions for each type (see
[khash](https://attractivechaos.wordpress.com/2008/09/02/implementing-generic-hash-library-in-c/))
definitely have the upper hand.

These approaches however do lose out a bit in terms of the expressiveness of the
resulting API (which is our main focus here).

### Which Names are Which?

Say we wanted to do the following contrived thing

```c
void print(qvec(int) *v)
{
    qvec_print(v);
}

int main(void)
{
    qvec(int) *v = qvec_new(int, 1, 2, 3);
    print(v);
}
```

This will spew our a mess of errors about anonymous structs. The reason being is
that the `qvec(int)` in the `print` parameter list is declaring a new anonymous
struct, and the two `qvec(int)` declarations are completely different
structures.

This can be worked around by doing a typedef at the start of your file and using
this, but again at the cost of extra work for the programmer.

How about the following example. Will this `qvec_new` be aware of the type being
used within the `Foo` struct?

```c
struct Foo {
    qvec(int) *values;
};

void foo_init(Foo *v)
{
    v->value = qvec_new(int);
}

int main(void)
{
    struct Foo f;
    foo_init(&f);
}
```

This in fact will work potentially to some surprise. Even though this does, it
still highlights a pretty important problem. Even though the API is nice and
appears easy to use, there are a number of naming issues that the user must be
aware of, which greatly limits its usage as a *just works* type of structure.

A Final Look
------------

```c
#include <qvec.h>

typedef char* string;

typedef struct {
    int x, y;
} Tuple;

int main(void)
{
    raii qvec(string) *sv = qvec_new(string, "Who", "are", "you?");
    qvec_print(sv);
    qvec_at(sv, 2, "we?");
    qvec_print(sv);

    raii auto iv = qvec_new(int, 1, 2, 3, 4);
    qvec_print(iv);
    printf("%d\n", qvec_pop(iv));

    qvec(Tuple) *tv = qvec_new(Tuple, { .x = 0, .y = 1 }, { 4, 2 }, { 5, 4 });
    printf("%d\n", qvec_at(1).x);
    printf("%d\n", qvec_at(2).x);
    qvec_free(tv);
}
```

So would I recommend using this? Probably not. If you were insistent on
sticking with C however I think the best compromise would be to generate the
specific instantiations (similar to what [khash](https://attractivechaos.wordpress.com/2008/09/02/implementing-generic-hash-library-in-c/)
does).Keeping implementations in their own implementation file which gets rid of
practically all the problems specified here. Alternatively, if performance and
the "type-safety" isn't a big deal, then a tried and tested `void*`
implementation would be good too.

At the end of the day though, the pragmatic solution would be to just use C++
if there are no reasons not to and call it a day. Especially if you are
considering performing these types of C macro chicanery.
