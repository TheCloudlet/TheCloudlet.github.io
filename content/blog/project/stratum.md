+++
title = "Stratum: FIXME"
description = "TODO"
author = "Yi-Ping Pan (Cloudlet)"
date = 2026-01-02
draft = true

[taxonomies]
tags = ["c", "cpp", "template", "cache", "simulation", "dsl"]
categories = ["cpp", "project"]
+++

## FIXME

True story.

The story starts from an interview. When the interviewer asked about my open-source contribution in [rv32emu](https://github.com/sysprog21/rv32emu), specifically how I achieved the 52% find and 35% insert performance improvement ([commit](https://github.com/sysprog21/rv32emu/commit/434c46660f67c78d9a4f587e05d2d59ec2102dc0)), my brain immediately started searching for the answer from memory. (Yes, memory, excuse for my poor humor)

Since I'd already answered this question a few times before, the explanation just came out pretty naturally. All the following text just flows through, I must have already cached this:

The key insight? Memory layout. Since all the `map_node` structures are stored in a memory pool, the more compact we pack them, the better our cache performance. Simple as that.

```C
// Old node structure
struct map_node {
    void *key, *data;

    // 3 tree navigation pointers
    unsigned long parent_color;  // parent pointer + color
    struct map_node *left, *right;
};

// New node structure
struct map_node {
    void *key, *data;

    // two tree navigation pointers
    struct map_node *left, *right_red;  // right pointer + color
};
```

By eliminating the parent pointer, we shave off 8 bytes per node. That's a 20% reduction in node size—which translates directly to fewer cache misses.

But without parent pointers, how do you traverse back up the tree during insertions and deletions? That's where jemalloc's approach comes in. Instead of storing parent pointers in every node, I maintain a path array on the stack during traversal:

```C
// Insert: single pass with path tracking
rb_path_entry_t path[RB_MAX_DEPTH];
for (pathp = path; pathp->node; pathp++) {
    // Store comparison result and navigate down
    pathp->cmp = (rb->comparator)(node->key, pathp->node->key);
}
// Unwind and fix colors in single pass going back up
for (pathp--; (uintptr_t) pathp >= (uintptr_t) path; pathp--) {
    // Fix colors going back up
}
```

The path array is stack-allocated and accessed sequentially—basically, it stays hot in L1 cache the entire time. Compare that to the old approach: following parent pointers through random locations scattered across the heap, causing cache misses at every step.

That's essentially how the speedup happened.

At that time, If there were a camera rolling, I must have a pretty confident smile on my face, but the interviewer asked the next question?

> So, what is the main cause of cache-miss latency in the cache?

Well, I replied. (Also from my cache.) Well, if we cannot find the data from the address we query in L1, we will fallback to find the address in L2 cache. Also, L2 cache is usually bigger than L1, so finding an address from L2 cache is slower than L1 cache.

Seems rational, right?

The interviewer then asked?

> So if the L2 size is exactly the same size as L1, where does the latency come from?

I replied.

> Physical latency, from CPU to L1 cache and to L2 cache.

This is definitely a wrong answer. And the interviewer kept on asking.

> Also, for your benchmark for red-black tree implementation, if you are not running on an x86 host but running on a SoC chip powered by ARM big.LITTLE cores?
> What if the associativity of the caches changes?
> Or what if the replacement policy has changed?

Okay, that is the time that I know: I have no understanding of what the F is a cache, or memory hierarchy.

## Back to the basics: Study Cache in a Software Engineer's Perspective

(This section is my notes, if you understan cache, please consider skip this section)

When studing how cache really worked. I look up via one of the "Golden" books discussing Cache is Computer Systems: A Programmer's Perspective (CS:APP) from Carnegie Mellon University.

The contents are available

- [Book](https://www.cs.sfu.ca/~ashriram/Courses/CS295/assets/books/CSAPP_2016.pdf)
- [Course Video](https://www.youtube.com/watch?v=vusQa4pfTFU)

In brief, Ch6.1 explained differnt storage technologies, from disk, DRAM, SRAM, SSD.

Ch6.2 explain the core fundamental of writing fast code -- locality. To be more specific. time locality and spacial locality.

Ch6.3 The memory hierarchy

```
+---------------------------------+
|  Regs (register file)           |
+---------------------------------+    ^
|  L1 cache (SRAM)                |    | Smaller, fast,
+---------------------------------+    | and expensive
|  L2 cache (SRAM)                |    | (per byte)
+---------------------------------+    |
|  L3 cache (SRAM)                |
+---------------------------------+
|  Main Memory (DRAM)             |    | Larger, slower
+---------------------------------+    | and cheaper
|  Local secondary storage (SSD)  |    | (per byte)
+---------------------------------+    v
|  Remote secondary storage       |
|  (Distributed FS, Web Server)   |
+---------------------------------+
```

| Type           | What cached            | Where cached          | Latency (cycles) | Managed by          |
|----------------|------------------------|-----------------------|------------------|---------------------|
| CPU registers  | 4-byte or 8-byte words | On-chip CPU registers | 0                | Compiler            |
| TLB            | Address translations   | On-chip TLB           | 0                | Hardware MMU        |
| L1 cache       | 64-byte blocks         | On-chip L1 cache      | 4                | Hardware            |
| L2 cache       | 64-byte blocks         | On-chip L2 cache      | 10               | Hardware            |
| L3 cache       | 64-byte blocks         | On-chip L3 cache      | 50               | Hardware            |
| Virtual memory | 4-KB pages             | Main memory           | 200              | Hardware + OS       |
| Buffer cache   | Parts of files         | Main memory           | 200              | OS                  |
| Disk cache     | Disk sectors           | Disk controller       | 100,000          | Controller firmware |
| Network cache  | Parts of files         | Local disk            | 10,000,000       | NFS client          |
| Browser cache  | Web pages              | Local disk            | 10,000,000       | Web browser         |
| Web cache      | Web pages              | Remote server disks   | 1,000,000,000    | Web proxy server    |

*Table: The ubiquity of caching in modern computer systems (adapted from CS:APP Figure 6.23)*

Ch4 explain how data is functionally saved in cache. First an address is splitted into three parts:

```
Address:
+------------------+------------------+------------------+
|      t bits      |      s bits      |      b bits      |
+------------------+------------------+------------------+
        Tag             Set index         Block offset

Where:
  - Tag (t bits):        Identifies which block within a set
  - Set index (s bits):  Selects which set in the cache
  - Block offset (b bits): Selects byte within the block

Example: 32-bit address, 64-byte blocks, 256 sets, 8-way cache
  - Block offset: 6 bits  (log2(64) = 6)
  - Set index:    8 bits  (log2(256) = 8)
  - Tag:         18 bits  (32 - 6 - 8 = 18)
```

The hardware cache is organized as a 2D array of **sets** and **ways** (associativity). Each cache line stores three components: a valid bit, a tag, and the actual data block.

```
          1 valid bit   t tag bits      B = 2^b bytes
          per line      per line        per cache block
          +-------+------------------+---+---+-----+-----+
  Set 0:  | Valid |       Tag        | 0 | 1 | ... | B-1 |
          +-------+------------------+---+---+-----+-----+   E lines per set
          | Valid |       Tag        | 0 | 1 | ... | B-1 |
          +-------+------------------+---+---+-----+-----+

          +-------+------------------+---+---+-----+-----+
  Set 1:  | Valid |       Tag        | 0 | 1 | ... | B-1 |
          +-------+------------------+---+---+-----+-----+   E lines per set
          | Valid |       Tag        | 0 | 1 | ... | B-1 |
          +-------+------------------+---+---+-----+-----+
                            .
                            .
                            .
          +-------+------------------+---+---+-----+-----+
Set S-1:  | Valid |       Tag        | 0 | 1 | ... | B-1 |
          +-------+------------------+---+---+-----+-----+   E lines per set
          | Valid |       Tag        | 0 | 1 | ... | B-1 |
          +-------+------------------+---+---+-----+-----+

Cache size:  C = S × E × B data bytes
```

**What is Associativity?**

Associativity (E-way) determines how many cache lines in a set can hold data for the same set index. It's a trade-off between conflict misses and hardware complexity.

**Three types:**

1. **Direct-mapped (E=1, 1-way)**:
   - Each memory block maps to exactly ONE cache line
   - Fastest (no way selection needed)
   - Most conflict misses (two blocks with same set index fight for one slot)

2. **N-way set-associative (E=N)**:
   - Each memory block can go into any of N cache lines in the set
   - Reduces conflict misses (more choices)
   - Requires parallel tag comparison across N ways + multiplexer

3. **Fully-associative (E=S, only 1 set)**:
   - Any memory block can go anywhere in the cache
   - No conflict misses (maximum flexibility)
   - Slowest and most expensive (compare against ALL cache lines)

**Example: 8-way set-associative cache**
- S = 256 sets, E = 8 ways per set
- A memory block maps to one of 256 sets (determined by set_index)
- Within that set, it can occupy any of the 8 cache lines
- Hardware checks all 8 tags in parallel to find a match

**Why higher associativity in L2/L3?**
- L1: Speed critical -> lower associativity (4-8 way)
- L2/L3: Miss penalty dominates -> higher associativity (16-way) to reduce conflict misses

When caching data (writing to cache), we

**Cache Write Process (storing data):**

1. **Select which set** according to the address:

   $$\text{set\_index} = \left\lfloor \frac{\text{address}}{B} \right\rfloor \bmod S$$

   Where:
   - $B = 2^b$ (block size in bytes)
   - $S = 2^s$ (number of sets)

   Or using bit operations (hardware implementation):

   ```cpp
   set_index = (address >> b) & (S - 1)
   ```

2. **Choose a cache line** within the set to replace (according to line replacement policy: LRU, FIFO, Random)

3. **Write the data** into the selected cache line:
   - Set valid bit = 1
   - Store tag = `address >> (b + s)`
   - Store data block

**Cache Read Process (retrieving data):**

1. **Select the set** using the same set_index calculation

2. **Check all ways** in the set:
   - Compare the address tag with each cache line's stored tag
   - Check if valid bit = 1

3. **Handle the result:**
   - **Cache hit**: Tag matches and valid -> return data from cache line
   - **Cache miss**: Tag not found -> fetch from next level (L2, L3, or DRAM), then store in current cache

Okay, to be honest, this looks like a recursive process to me. Learned from SICP Ch1.2.1 [Book (pdf)](https://web.mit.edu/6.001/6.037/sicp.pdf). So maybe let's try to using SICP's perspective to write our simulator.

Other resources:

Let's just explaining Ch6.5 writing cache-friendly code and Ch6.6 the memory mountain, I believe this is trivial and an experience engineer often does this without thinking.


### Just more references

- [What Every Programmer Should Know About Memory](https://people.freebsd.org/~lstewart/articles/cpumemory.pdf) by Ulrich Drepper, recommend to read 3.1 CPU Caches in the Big Picture.

## Building from the Ground **DOWN**

> What are you talking about? From Grounds Down?

This is just a niche humor. There is a long-standing Canadian aviation ground school textbook called "From the Ground Up" first released in 1941. Obvious enough, from teaching how to fly from ground school.

FIXME: SVG Stratum

And so, in here, I mean from "Ground Down." If we look from compiler's perspective (or more specifically, compiler backend's perspective), the load instruction means go dig underground to find the data from the memory. From RISC-V's terminorlogy, `lw` for load word, `lb` for load byte... But how long does the data ready? Where can we find our data hidden under the abstraction ground. It depends on which stratum the data is at. So this project is named "Stratum" (FIXME: add github link).

So, the upper graphs, illustrates my thinking process.

1. The cpu only cares 2 things: Load or store to the memeroy hierarchy.
2. Every cache has its own charastics (Sets, Ways, BlockSize, Policy)
3. We can chain all stratums together as an abstraction of memroy hierarchy
4. Every interction between different layer of cache can be view as "recusive process"
5. We can assume that we can get the data from main memory (since this is a cache simulator)

So, everything is deterministic in compile time.

And the building blocks are:

- Test data (input)
- Memory hierarchy setup
  - Sets
  - Ways
  - BlockSize
  - Policy
  - latency
  - next cache
- Procedures
  - Load
  - Store
  - Hit
  - Miss
- Report (output)

Looks very simple, sounds simple in Haskell using type alias. But I really struggle implementing this using C++20 recursive template. It is quite impressive from a language's perspective that such an impeative C++ can adapt to this functional way to declare any cache as a type, then chain them all together.

```cpp
using MemType = MainMemory<"MainMemory">;
using L2Type = Cache<"L2", MemType, 512,  8, 64, LRUPolicy,    10>;
using L1Type = Cache<"L1",  L2Type,  64,  8, 64, LRUPolicy,    4>;
//                     ^     ^       ^    ^   ^         ^      ^
//                  Name NextLayer Sets Ways BlockSize Policy HitLatency
```

This advantage of this design is:
1. Significat faster than OOP design (no vtable overhead)
2. Very simple configuation

Disadvantage:
1. Painful debugging experience implementing C++ template
2. If you want to test another combination of cache configuation you need to re-compile

Disadvantage (1) might be worth for the faster execution time. But we need to solve disadvantage (2) to be useful for teams that need real data to choose the correct hierarchy policy. So I decided a weird way - writing my own Domain Specific Language (DSL) configuration file in LISP (racket) to generate tons of `main.cpp` and Makefile according to policy people config.

## Building a Domain Specific Language Configuation

Since we don't want to manually change the configuation and recompile, why not we configure once, creating a lot of excutable?

User can config the cache like the following.

```racket
;; Compare 3-level vs 2-level hierarchy
(case_001
  (L1 64 8 4 LRUPolicy L2)
  (L2 512 8 64 LRUPolicy L3)
  (L3 8192 16 64 LRUPolicy MainMemory))

(case_002
  (L1 64 8 4 LRUPolicy L2)
  (L2 512 8 64 LRUPolicy MainMemory))  ;; Skip L3
```

Then build using cmake, we can have all different reports of executable ready to compare.

```bash
racket scripts/config.rkt  # Regenerate C++ code
cmake --build build
./build/bin/case_001 > results_3level.txt
./build/bin/case_002 > results_2level.txt
diff results_3level.txt results_2level.txt
```

Run result.

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

It sounds super fancy, but it's just converting configuration to create =case_xxx.cpp= then compiles to executable.

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

## Building Stratum: Answering the Questions I Couldn't

After studying CS:APP and building [Stratum](https://github.com/TheCloudlet/Stratum), I can now properly answer those interview questions. More importantly, I understand *why* my rb-tree optimization worked—and when it might not.

### Question 1: What Causes Cache-Miss Latency?

### Question 2: Same Size, Different Latency—Why?

### Question 3: What If Associativity/Policy Changes?

## Conclusion: What I Learned (and What's Missing)

**What this project taught me:**
- Cache behavior is about **access patterns**, not just capacity
  - My rb-tree optimization worked because of sequential path array access
  - Conflict misses matter more than you'd think (associativity isn't just a spec number)
- Template metaprogramming can eliminate runtime overhead
  - Zero-cost abstraction: cache hierarchy as types, not virtual dispatch
  - Compile-time binding mirrors hardware reality (topology is fixed at synthesis)
- Building tools teaches concepts better than reading alone
  - Implementing LRU forced me to understand why timestamp arrays beat linked lists
  - Writing the simulator exposed gaps my "reading comprehension" missed

**What I still don't understand:**
- How replacement policies map to hardware counters (e.g., tree-PLRU in Intel)
- Why real L1 caches use physical vs virtual indexing
- How MESI/MOESI states work in multi-core scenarios

**Future Work:**
Reading "A Primer on Memory Consistency and Cache Coherence" and implementing a MOESI simulator to close these gaps.