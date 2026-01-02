+++
title = "Memory Systems Interview Prep Checklist"
description = "A quick checklist for understanding memory systems in computer architecture"
author = "Yi-Ping Pan (Cloudlet)"
date = 2025-12-07
[taxonomies]
tags = ["computer-systems", "memory", "cache", "virtual-memory", "interview-prep"]
categories = ["Computer Architecture", "System Programming"]
+++

# Memory Systems Interview Prep

Based on CSAPP Chapter 6: The Memory Hierarchy

## Week 1 Day 1-2: Memory Hierarchy

**CSAPP 6.1-6.2: Storage Technologies & Locality**

1. Why do we need a memory hierarchy? What problems would we have if we only used one type of memory?
2. What is temporal locality? Give a concrete code example.
3. What is spatial locality? Give a concrete code example.
4. What are the typical speed differences between CPU registers, L1 cache, L2 cache, L3 cache, DRAM, and Disk? (Order of magnitude is fine, no need for exact numbers)
5. Why are smaller caches faster? Why can't we make all caches as fast as L1?
6. What kind of programs have good locality? What kind of programs have poor locality?

other:

1. What is firmware?
2. Can you draw CPU, bus interface, I/O bridge, memory bus, I/O bus, memory archetructure graph?

To ask

1. what is memory mapped io?
2. why rom (ssd) cannot modify one byte only?
3.

## Week 1 Day 3-4: Cache Basics

**CSAPP 6.4: Cache Memories**

1. What is a cache line? Why does cache operate on lines instead of individual bytes?
2. What is a direct-mapped cache? What are its advantages and disadvantages?
3. What is a set-associative cache? How does it differ from direct-mapped cache?
4. Given a 32-bit address, cache line size = 64 bytes, and 256 sets, how do you divide the address into tag, index, and offset?
5. What's the difference between write-through and write-back? What are the pros and cons of each?
6. What's the difference between cold miss, conflict miss, and capacity miss? Give an example of each.
7. Why is this code slow?

```c
int sum = 0;
for (int j = 0; j < N; j++)
    for (int i = 0; i < N; i++)
        sum += arr[i][j]; // assume row-major
```

8. What is loop blocking (tiling)? Why does it improve cache performance?

## Week 1 Day 5-6: Virtual Memory Part 1

**CSAPP 9.1-9.3: Physical and Virtual Addressing, Address Spaces, VM as a Tool for Caching**

1. Why do we need virtual memory? List at least 3 reasons.
2. What's the difference between virtual address and physical address?
3. What is a page? What's a typical page size?
4. What is a page table? Where is it stored?
5. Draw the translation flow from virtual address to physical address (VPN → PPN)
6. What is a page fault? What does the OS do when it happens?
7. Why does each process have its own page table?
8. If page size = 4KB and virtual address is 32-bit, how many bits for VPN? How many bits for offset?

## Week 1 Day 7: Virtual Memory Part 2 + TLB

**CSAPP 9.6: Address Translation**

1. What is a TLB? Why do we need it?
2. What's the difference between a TLB miss and a page fault?
3. Is it possible to have a TLB hit but a page fault?
4. Is it possible to have a page fault but a TLB hit?
5. Why is a multi-level page table better than a single-level page table?
6. Why don't we need to actually access the page table for most memory accesses?
7. Why is sequential access much faster than random access? (Explain from virtual memory perspective)
