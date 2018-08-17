# Big Integers in Zig
<div class="published"><time>13 May 2018</time></div>

I've recently been writing a big-integer library, [zig-bn](https://github.com/tiehuis/zig-bn)
in the [Zig](https://ziglang.org/) programming language.

The goal is to have reasonable performance in a fairly simple implementation
with a generic implementation with no assembly routines.

I'll list a few nice features about Zig which I think suit this sort of library
before exploring some preliminary performance comparisons and what in the
language encourages the speed.

## Transparent Local Allocators

Unlike most languages, the Zig standard library does not have a default
allocator implementation. Instead, allocators are specified at runtime, passed
as arguments to parts of the program which require it. I've used the same idea
with this big integer library.

The nice thing about this is it is very easy to use different allocators on a
per-integer level. A practical example may be to use a faster stack-based 
allocator for small temporaries, which can be bounded by some upper limit.

```
// Allocate an integer on the heap
var heap_allocator = std.heap.c_allocator;
var a = try BigInt.init(heap_allocator);
defer a.deinit();

// ... and one on the stack
var stack_allocator = std.debug.global_allocator;
var b = try BigInt.init(stack_allocator);
defer b.deinit();

// ... and some in a shared arena with shared deallocation
var arena = ArenaAllocator.init(heap_allocator);
defer arena.deinit();

var c = try BigInt.init(&arena.allocator);
var d = try BigInt.init(&arena.allocator);
```

This isn't possible in [GMP](https://gmplib.org/), which allows [specifying custom
allocation](https://gmplib.org/manual/Custom-Allocation.html)
functions, but which are shared across the all objects. Only one
set of memory functions can be used per program.

## Handling OOM

One issue with GMP is that out-of-memory conditions cannot easily be handled.
The only feasible way in-process way is to override the allocation functions and
use exceptions in C++, or longjmp back to a clean-up function which can attempt
to handle this as best as it can.

Since Zig was designed to handle allocation in a different way to C, we can
handle these much more easily. For any operation that could fail (either
out-of-memory or some other generic error), we can handle the error or pass it
back up the call-stack.

```
var a = try BigInt.init(failing_allocator);
// maybe got an out-of-memory! if we did, lets pass it back to the caller
try a.set(0x123294781294871290478129478);
```

There is the small detriment that it is required to explicitly handle possible
failing functions (and for zig-bn, that is practically all of them). The
provided syntax makes this minimal boilerplate, and unlike GMP we
can at least see where something could go wrong and not have to rely on hidden
error control flow.

## Compile-time switch functions

Zig provides a fair amount of compile-time support. A particular feature is the
ability to pass an arbitrary type `var` to a function. This gives a duck-typing
sort of feature and can provide more fluent interfaces than we otherwise could
write.

For example:

```
pub fn plusOne(x: var) @typeOf(x) {
    const T = @typeOf(x);

    switch (@typeInfo(T)) {
        TypeId.Int => {
            return x + 1;
        },
        TypeId.Float => {
            return x + 1.0;
        },
        else => {
            @compileError("can't handle this type, sorry!");
        },
    }
}
```

This feature is used to combine `set` functions into a [single function](https://github.com/tiehuis/zig-bn/blob/8691da48134b029c26df5fd26ddf07b78b90bca3/bigint.zig#L104)
instead of needing a variety of functions for each type as in GMP (`mpz_set_ui`,
`mpz_set_si`, ...).

## Peformance

Perhaps the most important detail of a big integer library is its raw
performance. I'll walk through the low-level addition routine and look at some
techniques we can use to speed it up incrementally.

The benchmarks used here can be found in this [repository](https://github.com/tiehuis/zig-bn/tree/8691da48134b029c26df5fd26ddf07b78b90bca3/bench).
We simply compute the 50000'th fibonacci number. This requires addition and
subtraction only.

Our initial naive implementation is as follows. It uses 32-bit limbs (so our
double-limb is a 64-bit integer) and simply propagates the carry. We force
inline the per-limb division and our debug asserts are compiled out in release
mode. Memory allocation is handled in the calling function.

```
// a + b + *carry, sets carry to overflow bits
fn addLimbWithCarry(a: Limb, b: Limb, carry: &Limb) Limb {
    const result = DoubleLimb(a) + DoubleLimb(b) + DoubleLimb(*carry);
    *carry = @truncate(Limb, result >> Limb.bit_count);
    return @truncate(Limb, result);
}

fn lladd(r: []Limb, a: []const Limb, b: []const Limb) void {
    debug.assert(a.len != 0 and b.len != 0);
    debug.assert(a.len >= b.len);
    debug.assert(r.len >= a.len + 1);

    var i: usize = 0;
    var carry: Limb = 0;

    while (i < b.len) : (i += 1) {
        r[i] = @inlineCall(addLimbWithCarry, a[i], b[i], &carry);
    }

    while (i < a.len) : (i += 1) {
        r[i] = @inlineCall(addLimbWithCarry, a[i], 0, &carry);
    }

    r[i] = carry;
}
```

The results are as follows:

```
fib-zig: 0:00.75 real, 0.75 user, 0.00 sys
  debug: 0:06.61 real, 6.60 user, 0.00 sys
```

For comparison, the GMP run time is:

```
fib-c:   0:00.17 real, 0.17 user, 0.00 sys
```

A more comparable C implementation (python) is:

```
fib-py:  0:00.77 real, 0.77 user, 0.00 sys
```

A bit of work to do against GMP! We aren't out of the ballpark compared
to less heavily optimized libraries. We are comparing the debug runtime version
as well since I consider it important that it runs reasonably quick for a good
development cycle, and not orders of magnitude slower.

### Leveraging Compiler Addition Builtins

Zig provides a number of LLVM builtins to us. While these shouldn't
usually be required, they can be valuable in certain cases. We'll be using the
[`@addWithOverflow`](https://ziglang.org/documentation/master/#addWithOverflow)
builtin to perform addition while catching possible overflow.

Our new addition routine is now:

```
fn lladd(r: []Limb, a: []const Limb, b: []const Limb) void {
    debug.assert(a.len != 0 and b.len != 0);
    debug.assert(a.len >= b.len);
    debug.assert(r.len >= a.len + 1);

    var i: usize = 0;
    var carry: Limb = 0;

    while (i < b.len) : (i += 1) {
        var c: Limb = 0;
        c += Limb(@addWithOverflow(Limb, a[i], b[i], &r[i]));
        c += Limb(@addWithOverflow(Limb, r[i], carry, &r[i]));
        carry = c;
    }

    while (i < a.len) : (i += 1) {
        carry = Limb(@addWithOverflow(Limb, a[i], carry, &r[i]));
    }

    r[i] = carry;
}
```

The new results:

```
fib-zig: 0:00.69 real, 0.69 user, 0.00 sys
  debug: 0:06.47 real, 6.42 user, 0.00 sys
```

A minimal, but noticeable improvement.

### Improving Debug Performance

Debug mode in Zig performs runtime bounds checks which include array checks and other
checks for possible [undefined behavior](https://ziglang.org/documentation/master/#Undefined-Behavior).

For these inner loops this is a lot of overhead. Our assertions are sufficient
to cover all the looping cases. We can disable these safety checks on
a per-block basis:

```
fn lladd(r: []Limb, a: []const Limb, b: []const Limb) void {
    @setRuntimeSafety(false);
    ...
}
```

```
fib-zig: 0:00.69 real, 0.69 user, 0.00 sys
  debug: 0:03.91 real, 3.90 user, 0.00 sys
```

That is a lot better.

### 64-bit limbs (and 128-bit integers).

We have been using 32-bit words this entire time. Our machine word-size however
is 64-bits. Lets change our limb size only, and rerun our tests.

```
fib-zig: 0:00.35 real, 0.35 user, 0.00 sys
  debug: 0:01.95 real, 1.95 user, 0.00 sys
```

Unsurprisingly, this is now twice as fast! It is fairly useful if your compiler
supports builtin 128-bit integer types when using 64-bit limbs. The reason is it
makes handling overflow in addition and especially multiplication much more
simple and easier to optimize by the compiler. Otherwise, [software
workarounds](https://github.com/v8/v8/blob/6.8.137/src/objects/bigint.cc#L2331)
need to be done which can be much less performant.

## Implementation Performance Summary

Benchmark code [here](https://github.com/tiehuis/zig-bn/tree/master/bench).

A performance comparison using the following libraries/languages:
 - [zig-bn](https://github.com/tiehuis/zig-bn)
 - [GMP](https://gmplib.org/)
 - [Go](https://golang.org/pkg/math/big/)
 - [CPython](https://github.com/python/cpython/blob/master/Objects/longobject.c)
 - [Rust-num](https://github.com/rust-num/num-bigint)

Note that C and Go use assembly, while Rust/CPython both are implemented in Rust and C
respectively, and are comparable as non-tuned generic implementations.

#### System Info

```
Architecture:        x86_64
Model name:          Intel(R) Core(TM) i5-6500 CPU @ 3.20GHz
```

#### Compiler Versions

```
zig:  0.2.0.ef3111be
gcc:  gcc (GCC) 8.1.0
go:   go version go1.10.2 linux/amd64
py:   Python 3.6.5
rust: rustc 1.25.0 (84203cac6 2018-03-25)
```

### Addition/Subtraction Test

Computes the 50,000th fibonacci number.

```
fib-zig: 0:00.35 real, 0.35 user, 0.00 sys
fib-c:   0:00.17 real, 0.17 user, 0.00 sys
fib-go:  0:00.20 real, 0.20 user, 0.00 sys
fib-py:  0:00.75 real, 0.75 user, 0.00 sys
fib-rs:  0:00.81 real, 0.81 user, 0.00 sys
```

### Multiplication/Addition Test

Computes the 50,000th factorial.

Zig uses naive multiplication only while all others use asymptotically faster
algorithms such as [karatsuba multiplication](https://en.wikipedia.org/wiki/Karatsuba_algorithm).

```
fac-zig: 0:00.54 real, 0.54 user, 0.00 sys
fac-c:   0:00.18 real, 0.18 user, 0.00 sys
fac-go:  0:00.21 real, 0.21 user, 0.00 sys
fac-py:  0:00.50 real, 0.48 user, 0.02 sys
fac-rs:  0:00.53 real, 0.53 user, 0.00 sys
```

### Division Test (single-limb)

Computes the 20,000th factorial then divides it back down to 1.

Rust is most likely much slower since it [doesn't special-case](https://github.com/rust-num/num-bigint/blob/master/src/algorithms.rs#L420)
length 1 limbs.

```
facdiv-zig: 0:00.99 real, 0.98 user, 0.00 sys
facdiv-c:   0:00.16 real, 0.16 user, 0.00 sys
facdiv-go:  0:00.93 real, 0.93 user, 0.00 sys
facdiv-py:  0:00.99 real, 0.99 user, 0.00 sys
facdiv-rs:  0:05.01 real, 4.98 user, 0.00 sys
```

## Summary

In short, zig-bn has managed to get fairly good performance from a pretty simple
implementation. It is twice as fast as other generic libraries for the functions
we have optimized, and is likely to be similarly fast using comparable
algorithms for multiplication/division.

While I consider these good results for a very simple implementation (<1k loc,
excluding tests) it is still lacking vs. GMP. Most notably, the algorithms used
are much more advanced and the gap would continue to grow as numbers grew even
larger. Hats off to the GMP project, as always.

A good start for a weeks work.
