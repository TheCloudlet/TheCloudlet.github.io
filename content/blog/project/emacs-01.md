+++
title = "Emacs Internal #01: is a Lisp Runtime in C, Not an Editor"
description = "Exploring why GNU Emacs embeds a Lisp interpreter in C -- from TECO marcos to Greenspun's Tenth Rule, with architecture comparisons to Neovim and VSCode"
author = "Cloudet (Yi-Ping Pan)"
date = 2026-02-26

[taxonomies]
categories = ["systems-programming"]
tags = ["lisp-interpreter", "teco-macros", "mccarthy-axioms", "greenspun-tenth-rule"]
+++

I tried to move to an LLM-friendly platform like VSCode or Cursor, but I kept returning to GNU Emacs. After reading other users' stories, I realized this is a common pattern. Very few tools survive 40 years and still feel hard to leave.

I read parts of the source code and discovered that Emacs is not just a code editor. There is **design philosophy**, **system software trade-offs**, and code that still feels like a treasure today. I want to record some personal discoveries that might be worth sharing.

Before we dive into the implementation, here is the "why" and the history I looked up.

## The Church: why people cannot leave GNU Emacs

Starting with the long-standing joke:

> Emacs, "a great operating system, lacking only a decent editor"
> -- [Editor War](https://en.wikipedia.org/wiki/Editor_war)

Joshua Blias's [Returning to the Church (of Emacs)](https://www.youtube.com/watch?v=sBc7toJaCxw) is a true story about switching to Neovim and coming back to GNU Emacs.

Here are common reasons why, in this modern world, people still use GNU Emacs, from a [Reddit post](https://www.reddit.com/r/emacs/comments/1brnmds/why_use_emacs/).

- "_Because I love being a pariah at the office._"
- "_I learn one editor, once, and use it for my whole career._"
- "_It fits like a tailored suit._" -- customizable experience, and you can mostly customize "EVERYTHING".
- Tools that cannot be replaced: OrgMode, Magit
- Tsoding - [The Annoying Usefulness of Emacs](https://www.youtube.com/watch?v=DMbrNhx2zWQ)
- The romantic Free Software Foundation spirit and unwillingness to be controlled by big tech

So here is my first big question:

## The history: Why Emacs Embeds an Elisp Interpreter in C

In the 1970s, hackers at the MIT AI Lab used a text editor called [TECO](<https://en.wikipedia.org/wiki/TECO_(text_editor)>). Unlike modern editors with a cursor, users had to input a sequence of password-like strings to cast the magic that edits text ([TECO manual](https://github.com/blakemcbride/TECOC/blob/master/doc/teco-manual.txt)). To reduce the pain, people started writing "macros" to speed up the process.

![TECO layout](https://www.copters.com/pictures/teco_layout.gif)

As macros grew larger and more complicated, they needed variables, `if-else` control flow, and loops. At that point, [Richard Stallman](https://en.wikipedia.org/wiki/Richard_Stallman) and [Guy Steele](https://en.wikipedia.org/wiki/Guy_L._Steele_Jr.) (the creator of Scheme) made a decision: "If the macro is complicated enough to act like a programming language, why not give it a real [Turing-complete](https://en.wikipedia.org/wiki/Turing_completeness) programming language?"

This is the birth of Emacs (Editor MACroS). An interpreter made the editor itself programmable, so users could extend and evolve it live without recompiling or waiting for upstream changes. In the earliest Emacs, the "interpreter" was just TECO's macro language. Later, GNU Emacs adopted **Emacs Lisp**. Lisp was a natural choice because its syntax is simple, its macros are powerful, and the interpreter is small and flexible, which makes live customization easy.

Later, Lisp machines were a commercial failure, and **C on von Neumann architecture** dominated the industry. When Richard Stallman and the [Free Software Foundation](https://en.wikipedia.org/wiki/Free_Software_Foundation) wanted a free Emacs on Unix, there was no Lisp environment there. So he wrote a **Lisp virtual machine and interpreter core in C**, effectively reviving the spirit of Lisp machines in a Unix ecosystem, because it was the path of least resistance to a complete Unix toolchain.

This helps explain why GNU Emacs' source code looks the way it does, and why jokes like "a great operating system" evolved.

---

## Things learned from the Story

### GNU Emacs source code directly

After understanding more about Emacs' history, the code and directory layout feel more reasonable. In this series, we'll discuss how C implements the Lisp interpreter, memory allocation, dynamic binding, and more.

### Worse is better: human nature

As to why C became dominant and not Lisp, a classic articulation of this "less elegant but more successful" outcome is Richard P. Gabriel's The Rise of [Worse is Better](https://www.dreamsongs.com/RiseOfWorseIsBetter.html). Sometimes the real world works this way too...

### Greenspun's Tenth Rule

> Any sufficiently complicated C or Fortran program contains an ad hoc, informally-specified, bug-ridden, slow implementation of half of Common Lisp.
> -- [Philip Greenspun](https://philip.greenspun.com/research/)

In more direct words: "Don't fool yourself: it starts as a simple config, but it won't stop there." Humans have unlimited desire, and long-lived software eventually evolves into a DSL and needs an embedded virtual machine.

Vimscript is a perfect victim of this Greenspun's Rule. On the other side, Richard Stallman's vision already foresaw this curse.

So Vim eventually needed a fork: Neovim using a **Lua runtime** (still an interpreter inside). They chose Lua because **LuaJIT** is a modern, fast runtime. Now Lua turns Neovim into a "Lua virtual machine text editor platform." Richard Stallman would probably laugh and say, "we did this 40 years ago."

Although the idea looks similar, Neovim often feels faster than Emacs in practice because it leans on newer runtimes and techniques (e.g., LuaJIT, async jobs, and RPC). The following are some ways Neovim outperforms Emacs.

|                   | Emacs Lisp                                     | Neovim                                                                                                                                 |
| :---------------- | :--------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------- |
| **architecture**  | Monolithic C core + embedded Elisp interpreter | C core + embedded LuaJIT + Msgpack RPC host/guest plugins                                                                              |
| **concurrency**   | single-threaded main loop                      | event loop; async jobs and RPC-based plugins                                                                                           |
| **union tagging** | tagged pointers + cons cells/immediates        | [NaN-tagging](https://medium.com/@kannanvijayan/exboxing-bridging-the-divide-between-tag-boxing-and-nan-boxing-07e39840e0ca) in LuaJIT |

For modern editors like VSCode, an interpreter is still inside. VSCode is essentially a web browser for code, built on Electron (Chromium + V8). That means a **VM is part of the editor's core**. From a language-design viewpoint it may look less elegant (JavaScript is slow), but in practice it feels fast because of JIT, SIMD, and async IPC that keeps the UI responsive. Either way, the pattern repeats: a VM sits at the core of the editor.

**Appendix (PS): Other Greenspun's Tenth Rule victims**

- Bash scripting
- LaTeX
- CMake
- Printer/PDF scripting languages
- eBPF in the Linux kernel
- Tcl (Tool Command Language) in the EDA industry
- LLVM TableGen (`.td`)

This is also why my cache simulator [Stratum](https://github.com/TheCloudlet/Stratum) uses Racket to create a DSL for cache configuration.

## Next step:

A. How to build a tiny Emacs Lisp interpreter in C with only seven elements

1.  quote
2.  atom
3.  eq
4.  car
5.  cdr
6.  cons
7.  cond

B. How `Lisp_Object` works?

---

Emacs Internal Series:

- #01: Emacs is a Lisp Runtime in C, Not an Editor
- #02: [Data First — Deconstructing Lisp_Object in C](@/blog/project/emacs-02.md)
- #03: [Tagged Union, Tagged Pointer, and Poor Man's Inheritance](@/blog/project/emacs-03.md)
