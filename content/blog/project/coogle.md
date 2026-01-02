+++
title = "Introducing Coogle: Bringing Haskell's Hoogle to C++"
description = "Building a type signature search engine for C++ inspired by Haskell's Hoogle—tackling libclang AST traversal, template canonicalization, and performance optimization"
author = "Yi-Ping Pan (Cloudlet)"
date = 2025-12-02

[taxonomies]
tags = ["c", "cpp", "strings", "google", "parser"]
categories = ["cpp", "project"]
+++

## Why I Started This Project?

The story started in 2024, when I decided to review basic algorithms and data structures. I started a repository called "[From Zero to Leetcode Hero](https://github.com/TheCloudlet/LeetcodeHero)." My intention was to learn and solve LeetCode problems using C++ and Haskell together.

Playing with both languages was fun. I discovered that tail recursion and iteration share almost the same control flow. The main difference lies in how the compiler (like LLVM) handles the stack frame prologue and epilogue, but that is a story for another time.

While exploring Haskell, I found an incredibly useful tool called [Hoogle](https://hoogle.haskell.org/), which allows you to search for functions by their type signatures.

For example, if I want a function that takes a list of integers and returns a single integer (like a total or a count), I can search for `[Int] -> Int`. Hoogle will suggest relevant functions like `sum`, `product`, or `length`.

```Haskell
add :: Int -> Int -> Int
add = undefined
```

- `add` is the function name.
- `::` means "has type".
- `Int -> Int -> Int` means it takes two `Int` arguments and returns an `Int`.
- `add = undefined` means the implementation is still pending. We don't care about the body yet; the signature tells the whole story.

The last type in the chain is the return type. So, a signature like `Int -> Char` means it takes an integer and returns a character.

This strict enforcement ensures that Hoogle can accurately match tools to your needs, and guarantees no "surprise actions" (side effects) modify values outside the function scope.

Honestly, when I first encountered Haskell types, I was completely confused by the syntax. It took me a while to fully translate my mindset, but then signature searching just clicked.

**Why is searching by type signature useful?**

It allows me to ignore all the operations and irrelevant details, and focus on how data flows through functions.

From a compiler engineer's perspective, looking at code this way is a superpower. It forces us to separate the **Plumbing** (how we move data) from the **Logic** (what we do with data). This separation is the essence of Data Abstraction taught in foundational texts like SICP: you focus on the behavior of functions at the highest level (the interface) without concerning yourself with their messy implementation details.

From my daily work experience, for example, when I need to handle getting a real name from an AST node, I often find myself searching for functions that convert `ASTNode` to `std::string`. This is especially true when dealing with unfamiliar third-party libraries or legacy codebases.

So I am looking for the function signature like:

```Haskell
foo :: ASTNode -> String
foo = undefined
```

or in C++ notation:

```C++
std::string foo(const ASTNode& node);
```

> What if I could use this approach in my everyday VHDL compiler development? Searching for the input class and the output class would be incredibly useful.

However, I couldn't find any similar tool for C/C++. That's why I created **Coogle** — a high-performance C++ command-line tool for searching C/C++ functions based on their type signatures, inspired by Hoogle from the Haskell ecosystem.

## The Semantic Gap: Why Text Matching Fails C++ Code

> Why not just use `grep` or `rg` to search for function names or patterns in header files?

That is the first question everyone asks. The answer is simple: C++ is not a regular language, and source code is not just text—it is structure.

Consider this scenario: You want a function that takes an `ASTNode` and returns a `std::string`.

- **Regex approach**: Writing `std::string\s+\w+\(\s*const\s+ASTNode&\s*\w+\s*\)`
- **The problem**: This will miss many valid matches:

  ```c++
  // The const is trailing
  std::string getName(ASTNode const& node);

  // There is a line break
  std::string
  getName(const ASTNode& node);
  ```

Sure, you might claim that you can write more complex regex to cover these cases. But do you really want to write that crazy regex, or would you rather use something like this?

```bash
# Standard search
./coogle . "std::string(ASTNode const&)"

# It understands references and whitespace automatically
./coogle . "std::string ( ASTNode & )"

# Wildcards supported
./coogle . "std::string (*)"
```

> "What if I wrap the regex in a Python script?"

Fair point! However, here's the thing: writing a Python script to manage complex regexes is basically building your own fragile parser. Sure, it's more convenient than raw regex, but it doesn't actually solve the correctness problem.

Even with a script wrapping text-matching logic, you'll still run into two fundamental C++ features that trip up regex—but Coogle handles them naturally:

1. **Type Aliases (The Semantic Gap)** — Regex sees text; Coogle sees types.
   - Code: `using NodeID = uint64_t;`
   - Search: You want a function returning `uint64_t`.
   - Regex/Python: Will miss `NodeID get_id()` because `"NodeID" != "uint64_t"`.
   - Coogle: Understands the alias and finds the match.

2. **Template Nesting (The "Greedy" Match Problem)** — Regex struggles with balanced brackets and recursive structures.
   - Code: `std::map<std::string, std::vector<int>>`
   - Regex: Writing a regex to correctly match nested `<...>` without accidentally matching the closing `>` of a different template is a nightmare (and theoretically impossible for standard regex engines).
   - Coogle: Parses the AST structure correctly.

Therefore, if you want correctness and reliability, building a proper parser is the only way—and that is exactly what Coogle does.

## Building Coogle

I'd like to thank Professor Ching-Han Chen (陳慶瀚) at National Central University, Taiwan, for teaching me the MIAT methodology. One of the most valuable lessons I learned was this: **the best way to start any project is to clearly define your inputs and outputs first.**

So that's exactly where I began with Coogle.

### Defining the Interface

The tool needed to be simple and intuitive. I envisioned a command-line interface that takes two arguments:

1. **File or directory path** — where to search
2. **Type signature** — what to find

The output should tell me exactly where the matching functions are:

```bash
# Input: Search for a function that takes an int and returns an int
./coogle . "int(int)"

# Output: Show the file, line number, and function name
foo.cpp:42:addOne
bar.cpp:108:increment
```

Simple enough. With the interface defined, I could now think about the internal architecture.

At the highest level, Coogle is just a function that transforms inputs into outputs:

```
┌──────────────────────────────┐
│           INPUT              │
│  • C/C++ File Path           │
│  • Search Signature String   │
└──────────────┬───────────────┘
               │
               v
       ┌───────────────┐
       │    Coogle     │
       └───────┬───────┘
               │
               v
┌──────────────┴───────────────┐
│           OUTPUT             │
│  • file:line:functionName    │
│  • file:line:functionName    │
│  • ...                       │
└──────────────────────────────┘
```

I sketched out how data would flow through Coogle. Following the functional programming principle that **everything is a function**, I broke down the entire system into a pipeline where each stage has clearly defined inputs and outputs:

```
══════════════════════════════════════════════════════════
              Coogle Processing Pipeline
══════════════════════════════════════════════════════════

[C/C++ File Path]                [Search Signature String]
        |                                   |
        v                                   v
  findSourceFiles()              parseFunctionSignature()
(recursively discover)              (custom parser)
        |                                   |
        | Output: List<FilePath>            | Output: Signature
        v                                   v
        |                                   |
        +-----------> foreach file <--------+
                           |
                           v
               clang_parseTranslationUnit()
                   (via libclang)
                           |
                           | Output: CXTranslationUnit (AST)
                           v
                      visitor()
               (CXCursor, Signature*) -> CXChildVisitResult
                           |
                           | Extract function declarations
                           | Build actual signature
                   isSigntaureMatch()
                           | Output: List<Match>
                           |     where Match = {file, line, name, sig}
                           v
                    fmt::print()
                   (List<Match>) -> IO
                           |
                           v
                       [Screen]
```

This looked simple enough, and I thought this would be a one-week project. I was completely wrong. I jumped into several potholes and had to crawl my way out. Let me share the key challenges I faced.

## Pothole 1: Understanding `libclang`

To be honest, I don't feel comfortable using tools or concepts that I don't understand well. My background is in Communication Engineering (Electrical Engineering), where we were trained in highly detailed mathematical modeling and derivation from first principles. We learned to question "black box" solutions and rigorously verify foundational theories before applying any abstraction—from Karnaugh maps to Gray codes, from probability theory to QPSK modulation.

My first "panic moment" came during COVID-19, when I volunteered to help my company build a pandemic survey web form. I chose the Django framework, but felt completely blind while implementing the website. It was like baking without understanding the chemistry—tweaking the amount of salt, yeast, and dough resting time, with no idea what was actually happening under the hood. Nevertheless, it eventually worked.

When working with `libclang`, I felt the same way. I knew I only needed to focus on the visitor function, but the syntax looked so unfamiliar—this didn't look like the familiar C/C++ code I was used to.

```C++
CXChildVisitResult visitor(CXCursor Cursor, [[maybe_unused]] CXCursor Parent,
                           CXClientData ClientData) {
  auto *Ctx = static_cast<VisitorContext *>(ClientData);

  CXCursorKind Kind = clang_getCursorKind(Cursor);
  if (Kind == CXCursor_FunctionDecl || Kind == CXCursor_CXXMethod) {
    // Build actual signature from libclang
    coogle::SignatureStorage ActualStorage;

    // Get return type
    CXType RetType = clang_getCursorResultType(Cursor);
    assert(RetType.kind != CXType_Invalid &&
           "Invalid return type obtained from libclang");
    CXString RetSpelling = clang_getTypeSpelling(RetType);
    std::string_view RetTypeSV = clang_getCString(RetSpelling);
    std::string_view RetTypeInterned = ActualStorage.internString(RetTypeSV);
    std::string_view RetTypeNorm =
        coogle::normalizeType(ActualStorage.arena(), RetTypeInterned);
    clang_disposeString(RetSpelling);
    //...
  }
}
```

After some research, I realized that Clang might not be so different from the RTL compiler I'm used to. At minimum, I needed to get a grasp of the high-level code structure and how data flows—that would comfort me a bit.

**The full story of demystifying `libclang`—including the visitor pattern, AST traversal strategies, and how different languages handle compilation—deserves its own dedicated post.** For now, let's treat this as a black box with a well-defined interface: input a file, output an AST.

Stay tuned for: _"Inside libclang: From Visitor Pattern to AST Mastery"_

## Pothole 2: The `std::string` and Template Matching Issue

At the beginning, I thought `std::string` was a real type. (Yes, this is how naive I was—despite working with professional C++ programmers and being tortured by `std::string` issues regularly, I didn't know this fundamental fact). So when I expected to find `std::string` but actually got `std::basic_string<...>`, I was very confused.

I documented my learning journey in detail here:
[Back to Basics: From C char to string_view (Notes from building Coogle)](https://thecloudlet.github.io/blog/cpp/cpp-string/)

**The fix: Canonicalization (The Search for Truth)**

To solve this, I couldn't just store the function signature as it appears in the source code. I had to store the Canonical Type.

Clang provides `GetCanonicalType()`. This strips away all the "sugar"—typedefs, type aliases, and redundant qualifiers. This process mirrors the Lisp philosophy of Uniformity (Homogeneity). Just as Lisp treats code as data (S-expressions), canonicalization treats disparate C++ type aliases as a single, uniform data structure. By stripping away the syntactic sugar, we reveal the underlying mathematical truth of the function's type.

## Pothole 3: The Translation Unit Trap (The Flood of Headers)

This was the funniest bug.

When I searched for a simple signature like `void(void*)` inside `main.cpp`, I expected to find my own utility functions. Instead, Coogle vomited thousands of results: internal functions from `libc++`, `std::vector` helpers, and obscure symbols from the system SDK.

**The Root Cause:** I forgot how C++ compilers actually work. `libclang` operates on a **Translation Unit (TU)**. When reading `#include <iostream>`, the preprocessor copy-pastes the entire content of `iostream` (and everything it includes) into the file. So, to the parser, those `std::` functions are just as much "part of the file" as `main()`.

**The Fix: Defense in Depth (Double Filtering)**

To address this, I realized I needed a rigorous filtering strategy to separate "my code" from "library code." I implemented a two-layer filter:

**Layer 1: The Safety Net (System Header Check)**

First, I ask Clang if the cursor is explicitly inside a system header. This handles cases where file paths might be ambiguous but the compiler knows it's a library.

```C++
CXSourceLocation location = clang_getCursorLocation(cursor);
if (clang_Location_isInSystemHeader(location)) {
  return CXChildVisit_Continue; // Layer 1: Drop system headers immediately
}
```

**Layer 2: The Strict Scope (File Provenance Check)**

Second, even if it's not a system header, I don't want to see results from other user headers included in the TU unless I explicitly asked for them. I verify that the cursor physically resides in the target file.

```C++
CXFile File;
clang_getSpellingLocation(location, &File, &Line, &Column, nullptr);
CXString FileName = clang_getFileName(File);
const char *FileNameStr = clang_getCString(FileName);

// Layer 2: Only show results from the file we're explicitly parsing
if (!FileNameStr || Ctx->CurrentFile != FileNameStr) {
  return CXChildVisit_Continue;
}
```

By combining **System Header Filtering** (Blacklist) with **Explicit File Matching** (Whitelist), I achieved zero noise. Coogle now respects the user's intent: "Search this file, and only this file."

## Pothole 4: Performance Issue When Dealing With Large Codebases

Running Coogle on a small "Hello World" project was instant. But when I unleashed it on a massive codebase like LLVM itself? It choked. It got stuck for over 40 minutes, eating up CPU cycles like there was no tomorrow.

Profiling revealed two things:

1. Too many things are being parsed
2. `std::string` memory allocating issue

### Issue 1: The "Lazy Parser" Strategy

By default, Clang behaves like a compiler—it wants to build a perfect, complete AST. It resolves every `#include`, parses every template inside `<vector>`, and validates every function body.

**The Epiphany: Coogle is a Search Engine, not a Compiler.**

I don't need to generate binary code; I just need to read the **Signatures**. I realized I could aggressively turn off Clang's "heavy lifting" features to trade correctness for speed.

I decided to strip down the parsing process to the bare minimum by injecting specific compiler flags and options.

**1. Cutting the Cord to System Headers**

Since I already implemented the "File Filtering" logic in Pothole 3, parsing system headers was now purely wasted time.

```C++
ArgsVec.push_back("-nostdinc");   // Stop searching standard system directories
ArgsVec.push_back("-nostdinc++"); // Stop searching standard C++ directories
```

**The Logic:** This tells Clang: "Ignore the standard library."

**The Gain:** We skip parsing thousands of lines from `<iostream>`, `<vector>`, and `<string>`. The parser no longer wastes time building ASTs for the entire STL ecosystem.

**2. Skipping the Implementation Details**

I don't care how a function is implemented; I only care what it takes and returns.

```C++
unsigned Options = CXTranslationUnit_SkipFunctionBodies | ...
```

**The Logic:** `CXTranslationUnit_SkipFunctionBodies`.

**The Gain:** `libclang` completely ignores the code inside `func { ... }`. This is huge. For a 1000-line function, we now parse only the first line.

**3. Tolerating Imperfection**

Since I cut off the system headers, the code is technically "broken" (types like `std::string` are now undefined symbols to the parser).

```C++
unsigned Options = ... | CXTranslationUnit_Incomplete;
```

**The Logic:** `CXTranslationUnit_Incomplete`.

**The Gain:** This tells Clang: "It's okay if you find missing symbols or headers. Don't error out; just give me what you have." This makes the parser resilient to my aggressive optimization strategy.

### Issue 2: String Allocation Overhead (Memory Pool Optimization)

While fixing the parser flags solved the CPU bottleneck, I noticed the memory usage was still alarmingly high. This is where my previous deep dive into `std::string` and SSO (from Pothole 2) came back to save me.

The old `Signature` structure I used looked like this:

```C++
struct Signature {
  std::string RetType;                  // Original return type
  std::string RetTypeNorm;              // Normalized return type
  std::vector<std::string> ArgType;     // Original argument types
  std::vector<std::string> ArgTypeNorm; // Normalized argument types
};
```

For every matched signature, I needed at least 4 heap allocations (`void(void)`), which is obviously very expensive.

To solve this, I implemented a String Interning mechanism backed by a linear memory arena:

- **Storage**: A central `std::vector<char>` (or similar deque) acts as a persistent string pool.
- **Reference**: Instead of holding `std::string` (which owns memory), my AST nodes now hold `std::string_view` (which borrows memory).
- **Deduplication**: Before storing a type name, I check if it exists in the pool. If yes, I return a view to the existing data.

```C++
struct Signature {
  std::string_view RetType;            // Original return type
  std::string_view RetTypeNorm;        // Normalized return type
  span<std::string_view> ArgTypes;     // Original argument types
  span<std::string_view> ArgTypesNorm; // Normalized argument types
} __attribute__((packed));
```

By using `string_view` pointing to a stable memory arena, we are effectively enforcing Immutability. Once a string is interned, it never changes. This immutability eliminates the need for defensive copying and complex ownership management, much like how functional languages handle data structures.

Initially, I considered caching all `int` strings in a hash table to avoid duplicates, but I found that searching the table with string comparisons and checking whether the string is preallocated was actually slower than directly writing to the string pool.

**The Result**: This shifted the architecture from "Object-Oriented Ownership" (everyone owns their strings) to "Data-Oriented Sharing". Memory footprint dropped significantly, and more importantly, cache locality improved because related string data was now packed tightly in the arena rather than scattered across the heap.

In the end, I successfully reduced the whole AST parsing time for LLVM from being completely stuck (40+ minutes) down to just 6 minutes. While still not blazing fast, it's at least workable. If we want it even faster, we could integrate `compile_commands.json` or customize JSON file dumps, so we parse once and can check different signatures in split seconds.

## Conclusion (The Takeaway)

Building Coogle wasn't just about making a search tool—it was a journey of demystifying compilers and embracing the power of **Plumbing vs. Logic** separation.

I started with fear: fear of `libclang`, fear of the "black box," fear of diving into unfamiliar territory. But by applying the principles I learned from both SICP and practical engineering—**Data Abstraction** (separating interface from implementation), **Canonicalization** (normalizing types to their single source of truth), and **Lazy Evaluation** (only parsing what we need)—I managed to tame the beast.

The four potholes I encountered taught me valuable lessons:

1. **Understanding `libclang`** — Sometimes you don't need to understand everything; treating components as black boxes with clear interfaces is okay.
2. **Template Matching** — `std::string` isn't what I thought it was, and understanding the underlying type system is crucial.
3. **Translation Unit Filtering** — Defense in depth with layered filtering (system headers + file provenance) achieves zero noise.
4. **Performance Optimization** — Aggressive optimization strategies (lazy parsing + memory pools) can reduce 40+ minutes to 6 minutes.

Now, Coogle serves as my daily driver for navigating complex C++ codebases. It's not perfect, but it's built on a solid understanding of how C++ compilers actually work under the hood.

**What's Next?**

- Integrate `compile_commands.json` for persistent AST caching
- Consider building a language server protocol (LSP) extension

If you're interested in trying Coogle, check out the repository: [github.com/TheCloudlet/Coogle](https://github.com/TheCloudlet/Coogle)

## Appendix: Architecture Diagram

```
+---------------------+       +----------------------+
|   C/C++ Source      |       |   User Query         |
|   (File / Project)  |       |   "int(int)"         |
+----------+----------+       +-----------+----------+
           |                              |
           v                              v
+----------+------------------------------+----------+
|                 Coogle Frontend                    |
|                                                    |
|   [ libclang Parser ] <---- (Translation Unit)     |
|           |                                        |
|           v                                        |
|      (Clang AST)                                   |
|           |                                        |
|           v                                        |
|   < RecursiveASTVisitor > --+                      |
|           |                 |                      |
|           | (Visit)         | (Filter)             |
|           v                 v                      |
|   [ FunctionDecl ]      [ System Header Check ]    |
+-----------+----------------------------------------+
            |
            v
+-----------+----------------------------------------+
|                 Coogle Backend                     |
|                                                    |
|   1. Type Extraction (Get Raw Signature)           |
|      "NodeID get(int)"                             |
|           |                                        |
|           v                                        |
|   2. Canonicalization & Matching                   |
|           |                                        |
|           v                                        |
|   3. String Interning (Memory Pool)                |
|      Store unique signature via string_view        |
+-----------+----------------------------------------+
            |
            v
    +-------+-------+
    |    Output     |
    +---------------+
```
