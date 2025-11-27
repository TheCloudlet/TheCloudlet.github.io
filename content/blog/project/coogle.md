+++
title = "Back to Basics: From C char to string_view (Notes from building Coogle)"
author = "Yi-Ping Pan (Cloudlet)"
date = 2025-11-20
draft = true

[taxonomies]
tags = ["c", "cpp", "strings", "google", "parser"]
categories = ["cpp", "project"]
+++

# Introducing Coogle: Bringing Haskell's Hoogle to C++

## FIXME:

The story started in 2024, when I decided to review basic algorithms and data structures. I started a repository called "[From Zero to Leetcode Hero](https://github.com/TheCloudlet/LeetcodeHero)." My intention was to learn and solve LeetCode problems using C++ and Haskell together.

Playing with both languages was fun. I discovered that tail recursion and iteration share almost the same control flow. The main difference lies in how the compiler (like LLVM) handles the stack frame prologue and epilogue, but that is a story for another time.

While exploring Haskell, I found an incredibly useful tool called [Hoogle](https://hoogle.haskell.org/). It allows you to search for functions by their type signatures.

For example, if I want a function that takes a list of integers and returns a single integer (like a total or a count), I can search for [Int] -> Int. Hoogle will suggest relevant functions like `sum`, `product`, or `length`.

```Haskell
add :: Int -> Int -> Int
add = undefined
```

- `add` is the function name.
- `::` means "has type".
- `Int -> Int -> Int` means it takes two `Int` arguments and returns an `Int`.
- `add = undefined` means the implementation is still pending. We don't care about the body yet; the signature tells the whole story.

The last type in the chain is the return type. So, a signature like Int -> Char means it takes an integer and returns a character.

This strict enforcement ensures that Hoogle can accurately match tools to your needs, and guarantees no "surprise actions" (side effects) modify values outside the function scope.

If this makes sense to you, great! But honestly, when I first encountered Haskell types, I was completely confused by the syntax.

**Why is searching by type signature useful?**

It allows me to ignore all the operations and irrelevant details, and focus on how data flows through functions.

From a compiler engineer's perspective, looking at code this way is a superpower. It forces us to separate the **Plumbing** (how we move data) from the **Logic** (what we do with data).

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

However, I couldn't find any similar tool for C/C++. That's why I created **Coogle** — a high-performance C++ command-line tool for searching C/C++ functions based on their type signatures, inspired by Hoogle from the Haskell ecosystem.

## Arguments

> Why not just use `grep` or `rg` to search for function names or patterns in header files?

That is the first question everyone asks. The answer is that C++ is not a regular language, and source code is not just text—it is structure.

- Scenario: You want a function that takes an `ASTNode`, and returns a `std::string`.
- Regex: Writing `std::string\s+\w+\(\s*const\s+ASTNode&\s*\w+\s*\)`
- The missed match:

  ```c++
  // The const is trailing
  std::string getName(ASTNode const& node);

  // There is a line break
  std::string
  getName(const ASTNode& node);
  ```

Okay, you claim that you can write more complex regex to cover these cases. Do you really want to write that crazy regex, or use something like this?

```bash
# Standard search
./coogle . "std::string(ASTNode const&)"

# It understands references and whitespace automatically
./coogle . "std::string ( ASTNode & )"

# Wildcards supported
./coogle . "std::string (*)"
```

> "What if I wrap the regex in a Python script?"

Fair point! But here's the thing: writing a Python script to manage complex regexes is basically building your own fragile parser. Sure, it's more convenient than raw regex, but it doesn't actually solve the correctness problem.

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

So, if you want correctness and reliability, building a proper parser is the only way, and that is what Coogle does.

## Building Coogle

- [Story A] ()
- [Story B] ()
- [Story C] ()

## problems

- Problems I meet, all fucntions that fits pops up
- perofrmance issues

## Conculsion
