+++
title = "Back to Basics: From C char to string_view (Notes from building Coogle)"
author = "Yi-Ping Pan (Cloudlet)"
date = 2025-11-20

[taxonomies]
tags = ["c", "cpp", "strings", "memory-management", "pmr", "allocators", "vfs"]
categories = ["cpp"]
+++

# Back to Basics: From C char to string_view (Notes from building Coogle)

## Background

When I was implementing [Coogle](https://github.com/TheCloudlet/Coogle), I discovered something bizarre about C++ strings. That is why I wrote this note to summarize what I learned about C++ strings.

Coogle is a search engine that I implemented in C++. It is designed to quickly and efficiently find function signatures in large codebases—especially useful for 30-year-old C++ codebases that were migrated from C and mixed with C++11/14/17/20 features like my lovely everyday job.

Since I like Haskell and pure functions, I tried to pay tribute to Hoogle, a Haskell function search engine. The idea is to be able to search for function signatures in C/C++ and get back a list of matching functions.

First step, support simple types like: `int`, `char`. Okay that is not too hard.

```cpp
// This is my test file
int add(int a, int b);
int std::string(std::string s);
```

I expect when I search "int(int, int)", Coogle should be able to find this signature quickly. So, implemented that, and it worked fine.

But, when I try to search "std::string(std::string)" to find function signatures that take and return `std::string`, I found that Coogle could not find any results, even though there are many such functions in my test codebase.

This is really a WTF moment for me.

I couldn't understand why and got stuck for a while, then I printed out the full AST tree using libclang. That's when I saw something confusing: `std::basic_string<char, std::char_traits<char>, std::allocator<char>>` showed up instead of `std::string`.

What the heck is a trait and allocator? I don't understand C++ strings at all. I thought it was supposed to be just `std::string`!

Well... So I dug deeper and read more about C++ strings.

My initial thinking was to ask LLMs about C++ strings and designs. But since I work on legacy C and C++ code, and lots of my algorithms are implemented in C (for milking out best performance), I decided to first understand C strings and character types deeply.

As Jserv always says in [C Programming series](https://hackmd.io/@sysprog/c-programming):

> "Be honest with yourself. You don't know C." \
> &mdash; Jserv Huang

So, before we tackle std::string, let's be honest with ourselves and look at the chaos of char. Everything below is based on my research using different resources, including language standards, articles.

That may not be 100% accurate, but I tried my best to summarize what I learned. If you find any mistakes, please kindly point them out to me.

---

## PART 1: C99 chars and strings

Starting with my conclusion.

> In C, char doesn't really mean 'character'. It just means the smallest addressable unit of memory (a byte). ASCII or other encodings just happen to fit into this unit. \
> &mdash; The Cloudlet

Or maybe through the lens of VHDL we can see more clearly:

```
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package C_Types is
    -- Defined in <limits.h>
    -- Most likely 8, but could be 16 or 32 on DSPs
    constant CHAR_BIT : integer := 8;

    -- "unsigned char" -> 0 to 255
    subtype c_unsigned_char is unsigned(CHAR_BIT-1 downto 0);

    -- "signed char" -> -128 to 127
    subtype c_signed_char   is signed(CHAR_BIT-1 downto 0);

    -- Compiler defines "__CHAR_UNSIGNED__" on platforms like ARM.
    -- Set by Arch (x86=false, ARM=true)
    constant CHAR_IS_UNSIGNED : boolean := ???;

    alias c_char is
        case CHAR_IS_UNSIGNED generate
            when false => c_signed_char;   -- x86 (Default)
            when true  => c_unsigned_char; -- ARM
        end generate;

end package C_Types;
```

VHDL is chosen here specifically because of its strictness. It forces us to see the distinction between "Raw Bits" (std_logic_vector), "Unsigned Math" (unsigned), and "Signed Math" (signed).

### Quick C99 Char Summary

Please refer to ISO C99 standard §6.2.5 for more details.

1. The "Three Types" Rule: char, signed char, and unsigned char are three distinct types. The plain char is a wild card—it behaves like signed on x86 but unsigned on ARM.

2. Usage Rule:
   - Use `char` ONLY for text strings.
   - Use `signed char` for small value calculation
   - Use `unsigned char` (or uint8_t) for binary data.

### C Strings philosophy recap

This is CS101 stuff, I don't think we need to talk too much deeply about it. Just doing a quick recap and why C strings are designed this way.

**The Core Mechanism**

- `\0` is the null terminator.
- Operations like `strlen`, `strcpy`, `strcmp` are linear scan `O(n)`.

```
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│  H  │  e  │  l  │  l  │  o  │  ,  │     │  W  │  o  │  r  │  l  │  d  │  !  │ \0  │
├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│ 72  │ 101 │ 108 │ 108 │ 111 │ 44  │ 32  │ 87  │ 111 │ 114 │ 108 │ 100 │ 33  │  0  │
├─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│0x48 │0x65 │0x6C │0x6C │0x6F │0x2C │0x20 │0x57 │0x6F │0x72 │0x6C │0x64 │0x21 │0x00 │
└─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘
  [0]   [1]   [2]   [3]   [4]   [5]   [6]   [7]   [8]   [9]  [10]  [11]  [12]  [13]

  ^                                                                             ^
  |                                                                             |
  str (pointer to first character)                            Null terminator ('\0')
```

**The Why of Null-Terminated Strings**

I have searched around for why C strings are designed this way. What I can find is at 1970, there are 2 typical ways to represent strings in memory:

1. Pascal style: Length-prefixed strings (1 byte length + data)
2. C style: Null-terminated strings (data + '\0')

But I haven’t found a definitive answer to why C chose null-terminated strings over length-prefixed strings.
Instead, I stumbled upon some interesting articles pointing out that C strings are, frankly, a pain. Check out Joel Spolsky’s classic post, [Back to Basics](https://www.joelonsoftware.com/2001/12/11/back-to-basics/), where he describes the performance problems with strcat and how some developers resorted to “F\*\*\*ed-Up Strings” (Pascal-style strings in C) as a workaround for the shortcomings of null-terminated strings.

People have different implementations for string handling in C, just like the Linux kernel has its qstr implementation under `include/linux/dcache.h` when dealing with filesystem paths. Google's [Abseil](https://github.com/abseil) library also introduced `StringPiece` (which later evolved into string_view in C++17). The commonly accepted approach across these implementations is to keep a length field along with the char pointer to avoid repeated strlen calls.

Therefore, C++'s `std::string` is not the only solution to C string problems—but understanding its design can be helpful for compiler, library, and systems programmers.

**Update**: Community Insights (2025-11-26)

For the nul-terminated string design, some kind comments on Reddit pointed out that:

> Because in ye olden days a one byte length wasn't large enough to represent long strings, but using more bytes for the length field was inefficient for short strings. And I guess no one wanted the complexity of a variable length encoding for the length prefix. And so we live with the pain of null terminated strings today. \
> &mdash; u/Kered13

Also, thanks to u/vip17 for pointing out these excellent resources for diving deeper into the history:

> There are lots of places that explain the history of C's null-terminated strings: \
>
> - [Null-terminated strings on the PDP-7 (retrocomputing.stackexchange)](https://retrocomputing.stackexchange.com/questions/24855/null-terminated-strings-on-the-pdp-7) \
> - [Why did C and Linux API use null-terminated strings? (reddit r/cpp_questions)](https://www.reddit.com/r/cpp_questions/comments/qlzho1/why_did_c_and_linux_api_use_nullterminated_strings/) \
> - [Why do strings in C need to be null terminated? (stack overflow)](https://stackoverflow.com/questions/2221304/why-do-strings-in-c-need-to-be-null-terminated)

It seems the struggle between efficiency and simplicity has been with us since the dawn of C.

**Update**: The Memory's Perspective (2025-11-27)

Although we say `byte` is the smallest addressable unit of memory, I found out that in DRAM chips, the smallest unit that can be read/written is actually a `word` (typically 4 or 8 bytes). The concept of `byte` is more of a logical abstraction provided by the CPU architecture or ISA.

When the CPU accesses memory, it reads/writes in chunks of words. The memory controller then breaks these words down into bytes for the CPU to process. This means that even though we work with bytes in our code, under the hood, the memory system operates on larger units.

In the following reference, there is a detailed explanation of how memory systems work, including the concepts of cache lines, memory hierarchy, and how data is fetched from DRAM to CPU caches.

Reference: [Paper: What Every Programmer Should Know About Memory](https://people.freebsd.org/~lstewart/articles/cpumemory.pdf)

So, the answer to "Why C char are designed this way?" Is to fit the basic unit of memory access in **ISA/CPU architecture** while providing a simple abstraction for programmers to work with text data.

---

## PART 2: std::string and the Template Monster

Okay, back to Coogle's bug. I was searching for `std::string(std::string)` in the AST, but I see zero results. I then printed out the full type name stored in the AST using `libclang` and there it was, the monster type name:

`std::basic_string<char, std::char_traits<char>, std::allocator<char>>`

\*\*

### The Typedef Illusion

> `std::string` is just a typedef (alias) for a specific instantiation of the `std::basic_string` template class.

The search failed because I was looking for a name that doesn't exist in the type system. `std::string` is syntactic sugar for human programmers. The compiler sees only `basic_string<char>` and its full template instantiation with default arguments.

`basic_string` actually is a template with three parameters, two of which have defaults:

```cpp
template<
    class CharT,                           // Character type (char, wchar_t, etc.)
    class Traits = char_traits<CharT>,     // Character operations (comparison, copying)
    class Allocator = allocator<CharT>     // Memory management strategy
>
class basic_string;
```

Knowing this aliasing can be enough to solve my issue, but maybe understanding each parameter will help improving our programming skills.

**Deconstructing the monster**

- **CharT**:

  - Defines what kind of character the string holds—`char` for ASCII/UTF-8, `wchar_t` for wide characters, `char16_t` for UTF-16, etc. Simple enough.

- **Traits**:

  - Hmm... is more interesting. Accoding to [cppreference:char_traits](https://en.cppreference.com/w/cpp/string/char_traits):

    > The char_traits class is a traits class template that abstracts basic character and string operations for a given character type. The defined operation set is such that generic algorithms almost always can be implemented in terms of it.

    It means we can define custom behaviors for character operations like comparison, copying, length calculation, etc. For example, VHDL files are case-insensitive, so we could define a `case_insensitive_char_traits` that overrides comparison functions to ignore case differences.

    Cool!

- **Allocator**:

  - This is a powerful tool controls memory management. The default uses `new`/`delete`, but you can plug in custom allocators for specific memory strategies—arena allocation, pool allocation, debugging allocators that track leaks, etc. This is what C++17's PMR (Polymorphic Memory Resources) builds on, which we'll cover in PART 3.

> `std::basic_string` provides a flexible, reusable string class that can adapt to different character types, behaviors, and memory strategies.

**Quick summary diagram:**

```
                    Template Class (defined once)
    ┌────────────────────────────────────────────────────────────┐
    │  template<class CharT, class Traits, class Allocator>      │
    │  class basic_string {                                      │
    │      CharT* data_;                                         │
    │      size_t size_;                                         │
    │      size_t capacity_;                                     │
    │      // ... methods ...                                    │
    │  };                                                        │
    └────────────────────────────────────────────────────────────┘
                                  │
                                  │ Template Instantiation
                                  │
         ┌────────────────────────┼────────────────────────┐
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────┐      ┌─────────────────┐     ┌──────────────────────┐
│   std::string   │      │  std::wstring   │     │ std::pmr::u16string  │
├─────────────────┤      ├─────────────────┤     ├──────────────────────┤
│ CharT:          │      │ CharT:          │     │ CharT:               │
│   char          │      │   wchar_t       │     │   char16_t           │
│ Traits:         │      │ Traits:         │     │ Traits:              │
│   char_traits   │      │   char_traits   │     │   char_traits        │
│   <char>        │      │   <wchar_t>     │     │   <char16_t>         │
│ Allocator:      │      │ Allocator:      │     │ Allocator:           │
│   allocator     │      │   allocator     │     │   polymorphic_alloc  │
│   <char>        │      │   <wchar_t>     │     │   <char16_t>         │
└─────────────────┘      └─────────────────┘     └──────────────────────┘
   "Hello"                  L"Hello"              u"Hello"
   6 bytes                  12/24 bytes           12 bytes
                                                  PMR runtime alloc!

All are typedefs of basic_string with different template arguments!
std::pmr::u16string -> DIFFERENT allocator = DIFFERENT type!
```

### class basic_string

After discussing the arguments of the template, let's look at how `basic_string` is implemented under the hood.

This is exactly the same concept as Linux kernel's `qstr`. Using a `struct` to hold the pointer and length of the string data. There are some more features like capacity management (just like the previous mentioned `strcat` from Joel Spolsky's article), but the core idea is the same.

The code is self explanatory, so I will just paste it here:

```cpp
template<class CharT, class Traits, class Allocator>
class basic_string {
private:
    CharT* data_;       // Pointer to character buffer
    size_t size_;       // Current length (excluding null terminator)
    size_t capacity_;   // Allocated capacity
    Allocator alloc_;   // Often zero-size due to EBO

    // Many implementations use a union for SSO (Small String Optimization):
    union {
        struct {
            CharT* ptr;
            size_t size;
            size_t capacity;
        } heap;  // For long strings

        struct {
            CharT buffer[16];  // Size varies by implementation
            unsigned char size;
        } stack;  // For short strings (SSO)
    } data_;

    // Methods, iterators, etc.
};
```

For more detail like short string optimization, and `pmr`/allocator, please refer to PART 3.

---

## PART 3: The Cost of Abstraction (SSO, Linux, and string_view)

### Small String Optimization (SSO)

Looking at the above code snippet of `basic_string`, I noticed the `union` that holds either a heap-allocated buffer or a small stack buffer. This is called Small String Optimization (SSO).

The concept of SSO is simple! Stack memory allocation is much faster than heap allocation. So preallocating a small buffer inside the string object can avoid small strings calling `new`/`delete` frequently.

In brief, stack allocation in compiler or assembly is just moving the stack pointer (prolog/epilog insertion), while heap allocation involves complex bookkeeping, searching for free blocks, and updating metadata.

I then researched a bit then find Linux kernel also uses this SSO technique under virtual filesystem path. The Linux kernel's `dentry` structure uses a `union` called `shortname_store` to hold either a short string directly in the structure or a pointer to a longer string allocated on the heap. This is exactly the same idea as C++'s SSO. [source: `include/linux/dcache.h`]

```C
/*
 * Try to keep struct dentry aligned on 64 byte cachelines (this will
 * give reasonable cacheline footprint with larger lines without the
 * large memory footprint increase).
 */
#ifdef CONFIG_64BIT
# define DNAME_INLINE_WORDS 5 /* 192 bytes */
#else
# ifdef CONFIG_SMP
#  define DNAME_INLINE_WORDS 9 /* 128 bytes */
# else
#  define DNAME_INLINE_WORDS 11 /* 128 bytes */
# endif
#endif

union shortname_store {
	unsigned char string[DNAME_INLINE_LEN];
	unsigned long words[DNAME_INLINE_WORDS];
};

#define DNAME_INLINE_LEN (DNAME_INLINE_WORDS*sizeof(unsigned long))
struct dentry {
	/* RCU lookup touched fields */
	unsigned int d_flags;		/* protected by d_lock */
	seqcount_spinlock_t d_seq;	/* per dentry seqlock */
	struct hlist_bl_node d_hash;	/* lookup hash list */
	struct dentry *d_parent;	/* parent directory */
	union {
	struct qstr __d_name;		/* for use ONLY in fs/dcache.c */
	const struct qstr d_name;
	};
	struct inode *d_inode;		/* Where the name belongs to - NULL is
					               negative */
	union shortname_store d_shortname;  //<-- SSO buffer for short names

    // ...
};
```

**Why Linux's SSO is Genius**

While the concept is similar to C++, Linux implements it with a crucial twist for performance: Branchless Access.

In C++, accessing `std::string` often involves a check: "Is this short or long?" before deciding where to read data.

Linux avoids this check completely. The `d_name.name` pointer (inside `struct qstr`) is set up during creation to point either to the internal `d_shortname` buffer or the external heap.

- Consumer side: When you read a filename, you just follow the pointer. Zero branching. Zero checks.
- Cache Line: Also, notice the comments about 64-byte alignment. The buffer size is calculated so the whole struct fits perfectly into a CPU cache line.

This shows that for System Programmers, Memory Layout isn't just about saving bytes—it's about saving CPU cycles.

**Update**: Community Insights (2025-11-26)

Question from Reddit:

> If you avoid a branch, but gain a pointer indirection, how big win is that in the end, considering the branch prediction that modern CPU are capable of? \
> u/Supadoplex

Answer or trying to answer:

I don't know the exact answer, but here is my research.
It depends on predictability vs cache locality:

Branch misprediction cost:

- Modern x86 (Skylake/Zen): ~15-20 cycles (per Agner Fog's measurements)
- Older architectures: can be 30+ cycles

Pointer indirection cost:
(Numbers from [agner.org](https://www.agner.org/optimize/))

- L1 cache hit: ~4-5 cycles (Intel/AMD spec)
- L2 hit: ~12 cycles
- L3 hit: ~40 cycles
- RAM miss: 200+ cycles

So...

> If your branch is unpredictable (<80% hit rate) and your pointer data is cache-resident, indirection usually wins.
> &mdash; Cloudlet

**Customize size of SSO buffer**

Well, sometimes I think I need to customize the size of SSO buffer for specific use cases. For example, I once need to deal with complex Verilog/VHDL mix language path names, which can be quite long. So maybe next time I will try to implement a customize string to support larger SSO buffer. The key is finding the right balance between stack size and heap allocation frequency. That's too far for this article, maybe next time.

### The Missing Piece: std::string_view (C++17)

Look at the internal structure of `std::string_view` (from GCC's `libstdc++`). It is strikingly similar to Linux kernel's `qstr`:

```cpp
template<typename _CharT, typename _Traits = std::char_traits<_CharT>>
class basic_string_view
{
    //...
private:
    size_t        _M_len;
    const _CharT* _M_str;
}
```

Just a pointer and a length. No allocator. No heap. No ownership. The owership is owned by the `std::string` (the most common), `char` array, or `mmap`ed file.

Of course, there is no free lunch. `std::string_view` is a borrowed reference (like Rust's `&str`). Must ensure the original data (the Owner) outlives the view.

## Conclusion: The "Swiss Army Knife" vs. The Scalpel

`std::string` tries to do too much. It handles ownership, resizing, traits, and allocation all in one class. It is a Swiss Army Knife—great for general applications where productivity comes first. (I have to admit, using std::string and RAII feels good and is incredibly brain-friendly.)

But for a high-performance tool like Linux kernel or LLVM compiler, it is over-engineered.

Linux Kernel's `struct qstr` shows us the elegance of simplicity: just a pointer and a length (and a hash).

The good news? Modern C++ (C++17) finally admitted this with `std::string_view`. It strips away the allocator magic and memory ownership, giving us back the raw efficiency of a C-style `struct`, but with type safety.

So, for writing high-performance tools:

- Treat `std::string` as a heavy container (like `std::vector`).
- Use `std::string_view` as your primary interface.
- And always remember: Simplicity is the ultimate sophistication.

## Further Study

- What is PMR (Polymorphic Memory Resources) in C++17?
- How `absl::Cord` solves the contiguous memory problem for huge strings?
