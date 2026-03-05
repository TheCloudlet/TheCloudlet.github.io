+++
title = "Emacs Internal #02: Data First — Deconstructing Lisp_Object in C"
description = "From von Neumann architecture to C struct memory layouts: understanding the core data representation of Emacs Lisp."
author = "Yi-Ping Pan (Cloudlet)"
date = 2026-03-05

[taxonomies]
tags = ["c", "system-design", "history", "lisp", "compiler"]
categories = ["c", "project", "compiler", "emacs"]

[extra]
math = true
math_auto_render = true
+++

In the first part of this GNU Emacs series, I focused on the history and explains why there is a Lisp interpreter embedded inside a text editor. Before diving into this part, I recommend reading the previous post:

[Emacs Internal #01: Emacs is a Lisp Runtime in C, Not an Editor](@/blog/project/emacs-01.md)

In this post, I want to look at GNU Emacs from a higher system-design perspective.

## The Mathematical Foundation: McCarthy's Lisp

Before diving into the source code, I left a short reference on Lisp here. Feel free to skip it if you are familiar with its background.

- [Wiki - Lisp](<https://en.wikipedia.org/wiki/Lisp_(programming_language)>) (LISt Processing)
- [The Roots of Lisp](https://languagelog.ldc.upenn.edu/myl/llog/jmc.pdf) - Paul Graham
- [How Lisp Became God's Own Programming Language](https://twobithistory.org/2018/10/14/lisp.html) - Two-Bit history

## First Principle: Data and Operations

This is how I personally approach reading source code: I start from how general computation works.

> Given some **data**, and some **operation**, then we get a new piece of **data**

Starting with the very basic, `3 + 4 = 7`. The data is `3` and `4`. The operation is `+`.

If we pile up the abstractions of basic math operations with data abstractions:

- **Complex numbers**:
  $$
  (a + bi)(c + di) = (ac - bd) + (ad + bc)i
  $$
- **Matrix multiplication**:
  $$
  C_{ij} = \sum_{k=1}^{n} A_{ik} B_{kj}
  $$
- **Convolution**:
  $$
  (f * g)(t) = \int_{-\infty}^{\infty} f(\tau)g(t - \tau)\, d\tau
  $$
- **A step function**:
  $$
  H(x) = \begin{cases} 1 & \text{if } x \ge 0 \\ 0 & \text{if } x < 0 \end{cases}
  $$

**From mathematical computation to a Von Neumann machine**, the computation can be lowered through IRs and eventually to assembly code.

```asm
op rd, r1, r2
```

When I think about compilers here, I usually picture SSA form at this stage.

At this level, the model is brutally clean:

- **Data** is a sequence of bits in the memory hierarchy, waiting to be fetched into a register.
- **Operations** are high-level semantics that the compiler lowers — pass by pass, IR by IR — until they become the native instruction set the silicon actually understands.

This leads me to three things:

First, modern compilers work from this first principle. LLVM's main challenge is to merge, traverse, and select a sequence of instructions so that we have the least computation time (usually on a single core). MLIR aims to unify lowering across heterogeneous hardware targets, especially when the hardware supports domain-specific operations like convolution, matrix multiplication, and precision conversion. (MLIR is the next planned series to dive in.)

Second, the idea that **code is data, and data is code** keeps showing up for me. Data is just bits; instructions are also just bit patterns stored in memory. The instruction stream lives in the same memory hierarchy as the data it operates on, and the CPU treats some bits as "code" only because the program counter (PC) points to them. From this perspective, Lisp machines and von Neumann machines are computationally equivalent (both are Turing complete), even though their architectures are very different.

Third, when I read code, I tend to start from the data: in C/C++ terms, the `struct` or private members of a class. Data is often more self-descriptive than operations. Once I understand the data model, the operations become transformations over that model. This is a personal bias, but it matches how I think about functional programming (FP) and data-oriented programming (DOP). It also explains why OOP doesn’t click with me as easily: it starts from behavior and encapsulation, while I prefer to anchor my understanding in data first. From this lens I could talk about side effects, mutability, and other concepts, but that would take us too far.

Starting with the data...

## Lisp_Object: The Universal C Type

### Tagged Pointer Layout

Back to the GNU Emacs [source code](https://github.com/emacs-mirror/emacs), the core data type used to represent Elisp values in C is called `Lisp_Object`, defined in `src/lisp.h`.

For simplicity, using a 64-bit system to explain.

Lisp_Object is a 64-bit machine word. For pointers, because heap allocations are 8-byte aligned, their lowest 3 bits are guaranteed to be `000`. Emacs simply embeds the 3-bit type tag directly into these "free" zero bits. For immediate integers (fixnums), the upper 62 bits hold the actual value.

```
64-bit Lisp_Object:
┌────────────────────────────────────────────────┬─────┐
│        pointer or value (61 bits)              │ tag │
│                                                │ 3b  │
└────────────────────────────────────────────────┴─────┘
```

Why the lowest 3 bits?

Because all heap-allocated objects are 8-byte aligned (due to `GCALIGNMENT`), their addresses always end in 000 in binary. These 3 bits are "free" — we can borrow them to store type information without losing any address precision.

The tag is a enum, named `Lisp_Type`. And the simplified source code is as below:

```C
enum Lisp_Type
  {
    Lisp_Symbol = 0,       // 0b000
    Lisp_Type_Unused0 = 1, // 0b001
    Lisp_Int0 = 2,         // 0b010
    Lisp_Int1 = 6,         // 0b110 <-- !
    Lisp_String = 4,       // 0b100
    Lisp_Vectorlike = 5,   // 0b101
    Lisp_Cons = 3,         // 0b010 <-- !
    Lisp_Float = 7         // 0b111
  };
```

### Stealing One More Bit

Looking closely to the `Lisp_Int0` and `Lisp_Int1`, something looks weird...

```
Lisp_Int0 = 0b010
Lisp_Int1 = 0b110
               ^^
lowest 2 bits are the same!
```

This design actually doubled the value that can be represented by a `Lisp_Int`

```
Normal 3-bit tag:
┌─────────────────────────────────────────────────────┬─────┐
│ value (61 bits)                                     │ tag │
│                                                     │ 3b  │
└─────────────────────────────────────────────────────┴─────┘
Range: -2^60 to 2^60-1

Fixnum with 2-bit tag:
┌───────────────────────────────────────────────────────┬───┐
│ value (62 bits)                                       │tag│
│                                                       │2b │
└───────────────────────────────────────────────────────┴───┘
Range: -2^61 to 2^61-1 (doubled!)
```

One important distinction: for a fixnum, the upper bits hold the integer value directly (an _immediate_). For all other types, those bits are a heap pointer to the underlying C struct.

### The Operation Conventions

The macros (or in debug mode is inline function) that work on `Lisp_Object` follow a naming convention:

- **`X` prefix** — _eXtract_: strip the tag bits and get the underlying value or pointer
- **`P` suffix** — _Predicate_: check the type, returns bool
- **`CHECK_` prefix** — _Assert_: like a predicate, but signals a Lisp error if the type is wrong

For example, to check if an object is an integer and then read it:

```c
// Source: src/bignum.h
if (FIXNUMP (obj))                // P: check type tag
{
    EMACS_INT n = XFIXNUM (obj);  // X: extract value
}
```

internally, `XSTRING`, `XCONS`, `XFIXNUM` and all other X macros work by masking off the tag bits using XUNTAG, then casting to the appropriate C struct pointer.

For `XFIXNUM` the mask is 2 bits, so

```c
// Source: src/lisp.h — XFIXNUM_RAW

return XLI(a) >> INTTYPEBITS;   // INTTYPEBITS = 2 for fixnums
```

PS. By performing a right shift (`>>`) on a signed integer, it forces the compiler to emit an arithmetic shift instruction. The hardware preserves the sign bit.

and for other types using `XUNTAG`:

```c
// Source: src/lisp.h — XUNTAG (for pointer types: XCONS, XSTRING, XSYMBOL, ...)
#define XUNTAG(a, type, ctype) \
  ((ctype *) ((uintptr_t) XLP(a) - (uintptr_t) LISP_WORD_TAG(type)))

// e.g. XCONS expands to:
return XUNTAG (a, Lisp_Cons, struct Lisp_Cons);
//     ^^^^^^ subtract the tag word from the raw pointer address
```

Why clear the lower 3 bit tag using subtraction (`-`) instead of a bitwise AND (`& ~0x7`)?

On architectures like x86, memory addressing supports `Base - Offset`. A C compiler can fold the tag clearing and the subsequent struct access (like `.car` or `.cdr`) into a single instruction, saving a CPU register.

Wait, why would an application developer care about instruction folding and x86 addressing modes? Because GNU Emacs was built by the same maniacs who built GCC. What??????

### The Big Picture

```
McCarthy's Lisp (1960)          abstract math
  atom  eq  car  cdr
  cons  quote  cond
        │
        │  Emacs engineers bridge:
        │  "statically typed C must represent
        │   dynamically typed Lisp"
        ▼
  Lisp_Object  (src/lisp.h)      C layer
  ┌──────────────────────┬────┐
  │  pointer or value    │tag │  ← one machine word
  │      61 bits         │ 3b │
  └──────────────────────┴────┘
        │
        ├─ tag = Cons    → CONSP()   → XCONS()    → struct Lisp_Cons
        ├─ tag = String  → STRINGP() → XSTRING()  → struct Lisp_String
        ├─ tag = Int0/1  → FIXNUMP() → XFIXNUM()  → EMACS_INT (immediate)
        └─ tag = Symbol  → SYMBOLP() → XSYMBOL()  → struct Lisp_Symbol
                                                          machine bits
```

With the data representation in place, we can now map McCarthy's original 7 axioms directly onto these C macros.

## Mapping McCarthy's 7 Axioms to C

If McCarthy's 7 axioms are the soul of Lisp, the Emacs source is its physical body — but that body is not confined to a single file. The axioms split across three files depending on whether they are about _data representation_, _memory_, or _control flow_:

| Axiom   | Meaning                   | C struct / function                                           | File      |
| ------- | ------------------------- | ------------------------------------------------------------- | --------- |
| `atom`  | is it NOT a pair?         | `!CONSP(obj)` (e.g., `EMACS_INT`, `struct Lisp_String`, etc.) | `lisp.h`  |
| `eq`    | are two refs identical?   | `Lisp_Object` (raw 64-bit word compare)                       | `lisp.h`  |
| `car`   | first element of pair     | `struct Lisp_Cons` - `.car` field                             | `lisp.h`  |
| `cdr`   | rest of pair              | `struct Lisp_Cons` - `.cdr` field                             | `lisp.h`  |
| `cons`  | construct a new pair      | `struct Lisp_Cons` allocated by `Fcons()`                     | `alloc.c` |
| `quote` | return without evaluating | `Fquote()` — special form                                     | `eval.c`  |
| `cond`  | branch on predicate       | `Fcond()` — special form                                      | `eval.c`  |

Notice the split: the first four axioms — `atom`, `eq`, `car`, `cdr` — are pure _data_ operations, living entirely in `lisp.h`. `cons` crosses into memory management. Only `quote` and `cond` require the _evaluator_ — they are the boundary where data becomes behavior.

PS. Other important files written in C.

- `lread.c` — tokenizing and reading Lisp source into `Lisp_Object` trees
- `eval.c` — evaluating those trees
- `alloc.c` — allocating and garbage-collecting Lisp objects
- `xdisp.c` — redisplay engine

## Next step

The tagged pointer trick Emacs uses is a specific instance of a broader pattern in systems programming: the _tagged union_. In the next post, we will look at how the same idea appears across different languages and eras — from manual C `union` + discriminant, to C++ `std::variant`, to Rust's `enum`. Same problem, different levels of language support.

---

Emacs Internal Series:

- #01: [Emacs is a Lisp Runtime in C, Not an Editor](@/blog/project/emacs-01.md)
- #02: Data First — Deconstructing Lisp_Object in C <-- We are here
