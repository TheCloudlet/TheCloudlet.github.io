+++
title = "Stratum: Architecting a Configurable Cache Simulator with C++ and Racket"
description = "Using Lisp to manage complexity in high-performance memory modeling."
author = "Yi-Ping Pan (Cloudlet)"
date = 2026-01-29

[taxonomies]
tags = ["c", "cpp", "template", "cache-simulation", "dsl", "sicp"]
categories = ["cpp", "project"]
+++

## The Interview That Changed Everything

During a recent interview, the conversation started well. The interviewer asked about my open-source contribution to [rv32emu](https://github.com/sysprog21/rv32emu)—specifically, how I achieved 52% faster lookups and 35% faster insertions in the red-black tree implementation ([commit 434c466](https://github.com/sysprog21/rv32emu/commit/434c46660f67c78d9a4f587e05d2d59ec2102dc0)).

My brain immediately started searching for the answer from _memory_—both the biological kind and the DRAM kind. Since I'd explained this optimization before, the answer was already cached:

**The optimization:** Eliminate the parent pointer from each node, shrinking node size by 20%. Fewer bytes per node means better cache density.

**The technique:** Instead of storing parent pointers in every node, maintain a path array on the stack during tree traversal. The path array stays hot in L1 cache, while the old approach scattered parent pointers across the heap, causing cache misses at every step.

```c
// Old: 3 pointers per node
struct map_node {
    void *key, *data;
    unsigned long parent_color;
    struct map_node *left, *right;
};

// New: 2 pointers per node
struct map_node {
    void *key, *data;
    struct map_node *left, *right_red;
};

// Path tracking on stack (stays in L1)
rb_path_entry_t path[RB_MAX_DEPTH];
for (pathp = path; pathp->node; pathp++) {
    pathp->cmp = (rb->comparator)(node->key, pathp->node->key);
}
```

Simple, clean, and—I thought—demonstrated solid understanding of cache behavior.

If there were a camera rolling, I probably had a pretty confident smile on my face. Then the interviewer asked the next question:

> **"What is the main cause of cache-miss latency?"**

Well, I replied. (Also from my cache.)

"If we can't find data in L1, we fall back to L2. And since L2 is usually bigger than L1, finding an address in L2 is slower."

Seemed reasonable, right?

> **"If L2 is the same size as L1, where does the latency difference come from?"**

"Physical distance," I replied. "The wire length from CPU to L1 versus L2."

The interviewer paused, then continued:

> **"What if you ran your benchmark on an ARM big.LITTLE SoC instead of x86?"**
> **"What if the cache associativity changed?"**
> **"What if the replacement policy was different?"**

My smile faded. If this were a cartoon, there'd be question marks floating above my head.

That's when I realized: I could optimize _for_ cache behavior, but I didn't actually understand _how_ caches work.

My rb-tree optimization succeeded on one machine with one cache configuration. I had no idea if it would work anywhere else—or why.

---

## Back to the basics: Study Cache in a Software Engineer's Perspective

After that interview, I needed to understand caches from first principles. I started with CS:APP Chapter 6 ([book](https://www.cs.sfu.ca/~ashriram/Courses/CS295/assets/books/CSAPP_2016.pdf), [lectures](https://www.youtube.com/watch?v=vusQa4pfTFU))—the canonical resource for cache architecture.

### The Fundamentals That Matter

**Cache Structure: It's Just a 2D Array**

A cache is organized as S sets × E ways. Each cache line contains three fields:

```
         1 valid bit   t tag bits      B = 2^b bytes
          per line      per line        per cache block
          +-------+------------------+---+---+-----+-----+
  Set 0:  | Valid |       Tag        | 0 | 1 | ... | B-1 |  <- Way 0
          +-------+------------------+---+---+-----+-----+
  Set 1:  | Valid |       Tag        | 0 | 1 | ... | B-1 |  <- Way 1
          +-------+------------------+---+---+-----+-----+
                            ...
          +-------+------------------+---+---+-----+-----+
Set S-1:  | Valid |       Tag        | 0 | 1 | ... | B-1 |
          +-------+------------------+---+---+-----+-----+

Cache size: C = S × E × B data bytes
```

**Example:** 8-way set-associative, 256 sets, 64-byte blocks
-> 256 × 8 × 64 = 128 KB cache

**Associativity:** The Trade-off I Missed

This is what the interviewer was asking about. Associativity (E-way) determines how many cache lines in a set can hold data:

1. **Direct-mapped (E=1)**: Each address maps to exactly ONE location
   - Fastest (no way selection)
   - Most conflict misses

2. **N-way set-associative (E=N)**: Each address can go into N locations within a set
   - Hardware checks all N tags in parallel
   - Requires N-input multiplexer -> higher latency

3. **Fully-associative**: Any address can go anywhere
   - No conflict misses
   - Slowest (compare against ALL cache lines)

**Now the interviewer's question made sense:**

Same size, different latency -> different associativity -> different tag comparison circuitry.

L2 isn't slower because it's "bigger"—it's slower because it's 16-way instead of 8-way.

### The Recursive Pattern

**Cache Read Process:**

1. **Select the set** using set_index
2. **Check all ways** in the set (parallel tag comparison)
3. **Handle the result:**
   - **Cache hit**: Return data immediately
   - **Cache miss**:
     1. **Fetch from next level** (L2, L3, or DRAM)
     2. **Store in current cache** (allocate a line, evict if needed)
     3. **Return data** to CPU

Wait. Step 3 is interesting.

When L1 misses, it asks L2. When L2 misses, it asks L3. When L3 misses, it asks DRAM. Each level follows the same pattern: check locally, delegate on miss.

This is a **recursive process**—the same pattern SICP Chapter 1.2 describes as "deferred operations that build up." Each cache level is a function that either returns data or calls the next level.

```scheme
; Cache lookup as recursive process (SICP perspective)
; This is pseudocode to illustrate the concept, not actual Stratum code
(define (cache-lookup addr level)
  (let ((result (probe-cache level addr)))
    (if (hit? result)
        (extract-data result)
        (let ((data (cache-lookup addr (next-level level))))
          (cache-fill level addr data)  ; Write fetched data back to current level
          data))))
```

That's when I decided: **implement cache hierarchy as recursive types in C++.**

Instead of a traditional OOP design with virtual methods and polymorphism, use template metaprogramming to bind the hierarchy at compile time—just like hardware does at synthesis time.

---

**Further reading:**

- [CS:APP Chapter 6](https://www.cs.sfu.ca/~ashriram/Courses/CS295/assets/books/CSAPP_2016.pdf) - Cache fundamentals
- [SICP Chapter 1.2](https://web.mit.edu/6.001/6.037/sicp.pdf) - Recursive processes
- [What Every Programmer Should Know About Memory](https://people.freebsd.org/~lstewart/articles/cpumemory.pdf) - Section 3.1

---

## Building Stratum: Digging Through Memory Layers

Here's how I think about cache hierarchy from a compiler backend perspective:

![Stratum Memory Hierarchy](/images/stratum-svg.svg)

The name "Stratum" comes from this mental model: memory hierarchy as **geological layers**.

**Above ground:** CPU and registers—visible, fast, directly accessible.

**Below ground:** Cache stratums—hidden, progressively deeper and slower. When the compiler generates a load instruction (`lw` in RISC-V), it's essentially saying "dig down through the strata until you find this data."

- L1 cache miss? Dig deeper to L2.
- L2 cache miss? Dig deeper to L3.
- L3 cache miss? Excavate all the way down to DRAM.

> From the grounds down.

_(Apologies to Canadian aviation students Not up--we're compiler people, we dig)_

From a compiler backend perspective, every load instruction digs _down_ through memory layers to find data. Which stratum is your data in? L1? L2? DRAM? The depth determines the latency.

That's why this project is named "Stratum"—because cache hierarchy is literally about drilling through geological layers of memory.

### Design Principles

This geological metaphor shaped Stratum's architecture:

**1. Discrete layers**: Each cache level is independent
**2. Miss delegation**: On miss, ask the next layer down
**3. Fixed topology**: Like rock strata, layers don't rearrange at runtime

This maps to the recursive pattern from SICP Chapter 1.2: each level is a function that either returns data or recursively calls the next level.

```cpp
using MemType = MainMemory<"MainMemory">;
using L2Type = Cache<"L2", MemType, 512,  8, 64, LRUPolicy,    10>;
using L1Type = Cache<"L1",  L2Type,  64,  8, 64, LRUPolicy,    4>;
//                     ^     ^       ^    ^   ^         ^      ^
//                  Name NextLayer Sets Ways BlockSize Policy HitLatency
```

Each cache level is a **type** that statically binds to the next layer. The entire hierarchy resolves at compile time—just like how hardware interconnects are fixed when you synthesize a Verilog/VHDL design into gates.

**Why this design?**

Traditional OOP would use virtual methods and runtime dispatch. But cache topology is fixed at hardware synthesis—there's no runtime decision about "which next level to query."

Think of it like **wiring in Verilog** (`wire` keyword), **signal connections in VHDL**, or **module connections in Chisel** (`:=` and `<>` operators): L1's miss port is hardwired to L2's input port. You don't change this at runtime; it's baked into the silicon.

Template metaprogramming captures this constraint: compile-time binding eliminates virtual dispatch overhead, mirroring how HDL synthesis produces fixed interconnects.

**Disadvantages:**

1. **Template error messages are cryptic**
   Template instantiation errors are... educational. You will become very familiar with `std::enable_if` and SFINAE, whether you want to or not.

2. **Recompilation required for every configuration**
   This is fine for one-off experiments but painful for systematic exploration. (Just like changing Verilog parameters requires resynthesis. This is why I added the Racket code generator.)

**Advantages:**

1. **Significantly faster than OOP design**
   No vtable overhead, no runtime dispatch—like the difference between software function calls vs. hardwired logic gates.

2. **Very simple configuration**
   Just a few parameters to specify cache size, associativity, block size, etc.

### Automating Configuration with Racket

The C++ template approach was fast, but had a painful limitation:
**Every configuration change requires full recompilation.**

Want to compare 2-level vs 3-level cache? Recompile. \
Want to test LRU vs FIFO? Recompile. \
Want to sweep associativity from 4-way to 16-way? Recompile.

For a single experiment, this is tolerable. For systematic exploration across dozens of configurations, it's a productivity killer.

**Solution: Generate the C++ code programmatically.**

Instead of manually editing templates, define configurations as S-expressions and generate all variants at one:

```racket
;; Compare 3-level vs 2-level hierarchy
(define experiments
  (case_001
  ;; name   sets  way latency policy      nextLevel
    (L1     64    8    4      LRUPolicy   L2)
    (L2     512   8    64     LRUPolicy   L3)
    (L3     8192  16   64     LRUPolicy   MainMemory))

  (case_002
  ;; name   sets  way latency policy      nextLevel
    (L1     64    8    4      LRUPolicy   L2)
    (L2     512   8    64     LRUPolicy   MainMemory)))
```

Run `racket config.rkt` to generate `case_001.cpp` and `case_002.cpp`.

Compile once, run both experiments.

Then build using cmake, we can have all different reports of executable ready to compare.

```bash
racket scripts/config.rkt  # Regenerate C++ code
cmake --build build        # Build executable

# Run experiments
./build/bin/case_001 > results_3level.txt
./build/bin/case_002 > results_2level.txt
diff results_3level.txt results_2level.txt
```

Output:

```
=========================================================
Running Simulation: Sequential (/path/to/sequential.txt)
=========================================================

=== Simulation Results (Aggregated) ===
Level                 Hits     Misses    Avg Latency (cyc)
L1                    4375        625                    4
L2                       0        625                    0
L3                       0        625                    0
MainMemory             625          0                  232
```

**Why Racket for Code Generation?**

**TL;DR: I didn't want to write a parser.**

In Racket, the configuration file IS the program:

```racket
;; This is valid Racket code AND valid configuration data:
(define experiments
  '((case_001
     (L1 64 8 4 LRUPolicy L2)
     (L2 512 8 64 LRUPolicy L3))))
```

No JSON. No YAML. No `configparser`. Just `read` the file and you have nested lists ready to process.

In Python, you'd need to pick a format (JSON? YAML? TOML?) and write parsing logic:

```python
import json
with open("config.json") as f:
    experiments = json.load(f)  # Now deal with dicts/lists
    name = config["name"]  # String keys everywhere
```

**The cost:** ~100 lines of Racket code vs ~150-200 lines of Python (after adding `json.load`, error handling, and dict unpacking).

**The benefit:** For someone who already knows Lisp, Racket is faster to write and harder to break (no missing commas in JSON, no YAML indentation errors).

If you don't already know Racket, **use Python**. The productivity gain only exists if you're fluent in Lisp.

---

## Building Stratum: Answering the Questions I Couldn't

After studying CS:APP and building [Stratum](https://github.com/TheCloudlet/Stratum), I can now properly answer those interview questions. More importantly, I understand _why_ my rb-tree optimization worked--and when it might not.

### Question 1: What Causes Cache-Miss Latency?

My original answer was wrong. I said "L2 is bigger so slower."

**The main reason:** L2/L3 are physically larger—longer wires and interconnects stretch the access pipeline. Size and wire delay dominate once you leave L1.

**But there's more to it.** Latency also comes from **tag comparison** and **way selection**.

When you access L2, hardware must:

1. Compare the address tag against _all ways_ in the set (parallel)
2. Select the matching way using a multiplexer

Higher associativity (more ways) = more parallel comparisons + bigger multiplexer = longer critical path.

**Why L2 is slower than L1:**

- L1: 4-8 ways (faster tag compare, shorter wires)
- L2: 16+ ways (more comparisons, longer wires)
- Physical distance dominates, but associativity adds overhead

**Real hardware nuance:** Modern CPUs mitigate associativity costs with banking and pipelining. In practice, size/wire delay and staging dominate L2/L3 latency; associativity is an important but secondary knob.

### Question 2: Same Size, Different Latency—Why?

**The real answer:** Different associativity.

Same capacity (`C = S * E * B`), different organizations:

- Cache A: 512 sets × 1 way (direct-mapped)
- Cache B: 64 sets × 8 ways (8-way associative)

Cache B is slower because:

- 8 parallel tag comparisons (vs 1 in Cache A)
- 8-input multiplexer (vs direct wire in Cache A)

**Trade-off:**

- Direct-mapped: Fast but conflict misses
- 8-way: Slower but fewer conflicts

**Real hardware nuance:** Modern CPUs narrow this gap using parallel tag+data access, way prediction, and banking. But higher associativity still tends to add latency while reducing conflict misses.

### Question 3: What If Associativity/Policy Changes?

**The hard truth:** My rb-tree optimization might not work everywhere.

On ARM big.LITTLE:

- Little cores: Smaller L1, lower associativity
  -> More conflict misses -> My path array advantage shrinks
- Big cores: Larger L1, higher associativity
  -> My optimization still wins

**Real hardware complexity:** Cache-sensitive optimizations are microarchitecture-dependent. Beyond capacity and associativity, replacement policy, prefetchers, line size, VIPT/TLB behavior, and LLC organization can flip results.

**What I learned from Stratum:**
You can't just benchmark on one machine and claim victory. Cache-sensitive code needs profiling across architectures. That's why I added Valgrind trace support—capture real workload patterns, then test against different cache configurations in Stratum.

**Best practice:** Always validate on multiple cores (ARM big.LITTLE, x86, RISC-V) with hardware counters and trace-driven simulation.

---

## Honest Evaluation of Stratum

**What Stratum Does Well:**

1. **Pre-Silicon Validation**: Test cache configurations before committing to RTL design
   - Example: Compare 2-level vs 3-level hierarchy trade-offs
   - Evidence-based decision making for SoC development

2. **Research and Education**:
   - Compare replacement policies (LRU vs FIFO vs Random) with real traces
   - Teach cache concepts with observable, measurable behavior
   - Sensitivity analysis for associativity and block size

3. **Workload Analysis**: Profile real applications via Valgrind traces
   - Identify cache-unfriendly access patterns in production code
   - Validate optimizations (like my rb-tree path array approach)

**What Stratum Doesn't Do:**

- **Mesh/NoC topologies**: Requires runtime routing, breaks compile-time binding
- **Non-inclusive/NUCA caches**: Complex invalidation protocols not modeled
- **Prefetchers**: Only demand-driven accesses supported
- **Multicore coherence**: No MESI/MOESI protocol simulation
- **Power modeling**: No energy consumption tracking

**Why These Limitations Are Acceptable:**

Stratum optimizes for **clarity** and **rapid experimentation**, not production-grade simulation. For detailed performance modeling, use gem5 or ZSim. For hardware verification, use RTL simulators.

**Design Pattern Applicability:**

This template-based hierarchy pattern isn't limited to CPU caches. The same approach applies to other memory hierarchies:

- **NPU/GPU memory**: L1 texture cache -> L2 cache -> HBM (High Bandwidth Memory) -> Host DRAM
- **Distributed systems**: Redis cache -> Local DB -> Remote DB -> Cold storage
- **CDN architecture**: Edge cache -> Regional cache -> Origin server
- **DMA transfers**: On-chip buffer -> L2 -> Main memory -> Peripheral device

**The key insight**: Any hierarchical lookup with fixed topology at "compile time" (or deployment time) can use this zero-overhead template approach. The abstraction of "check current level, on miss delegate to next level" is universal.

---

## Try It Yourself

**Quick Start (5 minutes):**

```bash
git clone https://github.com/TheCloudlet/Stratum.git
cd Stratum
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/bin/stratum  # Run default experiments
```

**Dependencies:** C++20 compiler (GCC 10+/Clang 11+/MSVC 2019+), CMake 3.20+

**Want to test your own traces?**

Visit [Stratum README](https://github.com/TheCloudlet/Stratum) for instructions on:

- Generating Valgrind memory traces from your programs
- Creating custom cache configurations
- Using the Racket code generator (optional)

**License:** MIT - Fork it, modify it, break it, learn from it.

---

## Conclusion: From Interview Failure to First Principles

That interview question—"What causes cache-miss latency?"—exposed a gap between **optimizing for cache behavior** and **understanding how caches actually work**. I could write cache-friendly code by intuition, but I couldn't explain why it worked or predict when it wouldn't.

Building Stratum closed that gap.

**What this project taught me:**

1. **Cache behavior is about access patterns, not just capacity**
   - My rb-tree optimization worked because the path array had **sequential access** (L1-friendly)
   - The old parent-pointer approach had **random heap access** (L1-hostile)
   - Conflict misses matter more than capacity misses (associativity isn't just a spec number)

2. **Template metaprogramming can mirror hardware constraints**
   - Zero-cost abstraction: cache hierarchy as types, not virtual dispatch
   - Compile-time binding mirrors hardware reality (topology is fixed at synthesis)
   - Design constraints become compiler guarantees

3. **Building tools teaches concepts better than reading alone**
   - Implementing LRU forced me to understand why timestamp arrays beat linked lists
   - Exposed why associativity directly impacts latency
   - Debugging Valgrind traces revealed access patterns I'd never noticed in profilers

**What I still don't understand:**

- How replacement policies map to hardware counters (e.g., tree-PLRU in Intel)
- Why real L1 caches use physical vs virtual indexing (TLB interactions)
- How MESI/MOESI states work in multi-core scenarios (cache coherence protocols)

**Next steps:**
Reading "A Primer on Memory Consistency and Cache Coherence" and implementing a MOESI simulator to close these gaps.

---

**Connect with me:**

- GitHub: [TheCloudlet/Stratum](https://github.com/TheCloudlet/Stratum)
- Questions/feedback: Open an issue or PR
- Interested in collaborating? Let's talk.
