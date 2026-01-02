<!-- markdownlint-disable MD041 -->

+++ title = "Stratum: FIXME"
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

> So, what is the main cause if cache-miss latency by the cache?

Well, I replied. (Also from my cache.) Well, if we cannot find the data from the address we query in L1, we will fallback to find the address in L2 cache. Also, L2 cache is usaully bigger than L1, so finding a address from L2 cache is slower from L1 cache.

Seems rational is it?

The interviewer then asked?

> So if the L2 size is exacly the same size of L1, what does the latency comes from? \

I replyed.

> Physical latency, from CPU to L1 cache and to L2 cache.

This is definately a wrong anwer. And the interviewer kept on asking.

> Also, for your benchmark for red-black tree implementation, if you are not running on a x86 host but running on a SoC chip powered by ARM big.LITTLE cores? \
> what if the associative of the caches changes? \
> Or what if the replace polocy has changed

Okay, that is the time that I know: I have no understanding of what the F is a cache, or memory hierarchy.

## FIXME