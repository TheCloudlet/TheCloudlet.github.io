+++
title = "[WIP] RISC-V Compiler Backend Complete Reference"
description = "A comprehensive guide covering instruction selection, register allocation, and instruction scheduling for LLVM backend engineers"
author = "Yi-Ping Pan (Cloudlet)"
date = 2025-11-22
draft = true

[taxonomies]
tags = ["llvm", "compiler", "risc-v", "backend", "optimization"]
categories = ["compiler"]
+++

# [WIP] RISC-V Compiler Backend Complete Reference

**Disclaimer: This is WIP (work-in-progrsss) personal note.**

There are still a lot of points that might still need clarafacation. I'll use my free time to turn this note into better readible artitle.

## Why Specialized Compiler Teams Matter

### The Business Case

Modern SoC companies need compiler teams because **hardware differentiation requires software optimization**.

```
+----------------------+-------------------------+
| Open Source Backend  | Commercial Backend      |
+----------------------+-------------------------+
| Generic Hardware     | Specialized Hardware    |
| Reference Impl       | Company-Specific uArch  |
| Conservative Opts    | Aggressive & Targeted   |
| Public Specs         | Internal Design Details |
| Community-Driven     | Product Roadmap-Driven  |
+----------------------+-------------------------+
```

**Key Insight:** Open source optimizes for the **specification**, commercial optimizes for the **implementation**.

### The Compiler Engineer's Three Missions

```
           Compiler Engineer's Core Responsibilities
                           |
        +------------------+------------------+
        |                  |                  |
 Microarchitectural   Custom ISA        Performance
     Tuning          Extensions          Debugging
        |                  |                  |
  Pipeline/Cost       New Instr          Hotspot
  Latency Model      ISel Pattern        Analysis
```

**A. Microarchitectural Tuning**

Open source doesn't know your actual hardware:

- Pipeline depth and latencies
- Execution unit configuration
- Branch prediction penalties
- Cache hierarchy parameters

**Your Job:** Fill in the `TargetSubtarget` C++ file with real measured data from your hardware team.

```cpp
// RISCVSubtarget.cpp - The Source of Truth
unsigned RISCVSubtarget::getInstrLatency(unsigned Opcode) {
  switch (Opcode) {
  case RISCV::MUL:  return 3;  // Your HW: 3 cycles
  case RISCV::DIV:  return 20; // Your HW: 20 cycles
  case RISCV::LOAD: return 3;  // L1 hit: 3 cycles
  }
}
```

**B. Custom ISA Extensions**

RISC-V's extensibility allows competitive advantage through private instructions:

```
Standard RISC-V + Company Secret Sauce
      |                    |
   RV64GC            Custom Crypto/ML/DSP
                     Instructions
```

**C. Performance Debugging**

Bridge hardware and software:

1. Profile with `perf` → find hotspots
2. Examine assembly → identify root cause
3. Trace compiler passes → understand decisions
4. Implement fixes → ISel patterns, cost models, custom passes

---

## RISC-V Architecture Fundamentals

### Load-Store Architecture

```
+--------------------------------------------------------+
|                RISC Load-Store Architecture            |
|                                                        |
|   Memory             Registers              Memory     |
|     |                    |                    ^        |
|     v                    v                    |        |
|  +-------+           +----------+          +-------+   |
|  | LOAD  |---------->| COMPUTE  |--------->| STORE |   |
|  | lw/ld |           | add/mul  |          | sw/sd |   |
|  +-------+           +----------+          +-------+   |
|                                                        |
| Rule 1: ALL computation in REGISTERS ONLY              |
| Rule 2: ONLY load/store touch memory                   |
+--------------------------------------------------------+
```

### Instruction Formats

All base instructions are 32 bits:

```
R-Type (add rd, rs1, rs2):
 31      25|24  20|19  15|14 12|11   7|6     0
 +---------+------+------+-----+------+-------+
 | funct7  | rs2  | rs1  |func3|  rd  |opcode |
 +---------+------+------+-----+------+-------+

I-Type (addi rd, rs1, imm):
 31          20|19  15|14 12|11   7|6     0
 +-------------+------+-----+------+-------+
 |  imm[11:0]  | rs1  |func3|  rd  |opcode |
 +-------------+------+-----+------+-------+

S-Type (sw rs2, offset(rs1)):
 31      25|24  20|19  15|14 12|11   7|6     0
 +---------+------+------+-----+--------+-------+
 |imm[11:5]| rs2  | rs1  |func3|imm[4:0]|opcode |
 +---------+------+------+-----+--------+-------+
```

### Register ABI

| Reg    | ABI    | Saved By | Purpose     | Notes             |
| ------ | ------ | -------- | ----------- | ----------------- |
| x0     | zero   | ---      | Zero        | Hardwired to 0    |
| x1     | ra     | Caller   | Return addr | Link register     |
| x2     | sp     | Callee   | Stack ptr   | Must preserve     |
| x5-7   | t0-t2  | Caller   | Temporaries | Scratch           |
| x8     | s0/fp  | Callee   | Saved/Frame | Frame pointer     |
| x9     | s1     | Callee   | Saved       | Must preserve     |
| x10-11 | a0-a1  | Caller   | Args/Return | First 2 args/rets |
| x12-17 | a2-a7  | Caller   | Arguments   | Function args     |
| x18-27 | s2-s11 | Callee   | Saved       | Must preserve     |
| x28-31 | t3-t6  | Caller   | Temporaries | Scratch           |

Caller-Saved: Free to clobber, caller must save if needed
Callee-Saved: MUST preserve if used (requires prolog/epilog)

**Critical for RegAlloc:**

- **Caller-saved (t0-t6, a0-a7):** Free in leaf functions, don't survive calls
- **Callee-saved (s0-s11):** Survive calls, but EXPENSIVE (prolog/epilog overhead)

---

## LLVM Backend Pipeline

### The Seven-Stage Pipeline

```
+------------------------------------------------------------+
|                LLVM Backend 7-Stage Pipeline               |
+------------------------------------------------------------+
| LLVM IR (target-independent)                               |
|    |                                                       |
|    v                                                       |
| +------------------------------------------------------+   |
| | 1. Instruction Selection (ISel)                      |   |
| |    - DAG pattern matching                            |   |
| |    - IR -> MachineIR with virtual registers          |   |
| +------------------------------------------------------+   |
|    |                                                       |
|    v                                                       |
| +------------------------------------------------------+   |
| | 2. Pre-RA Scheduling                                 |   |
| |    - Hide latencies                                  |   |
| |    - Minimize register pressure                      |   |
| +------------------------------------------------------+   |
|    |                                                       |
|    v                                                       |
| +------------------------------------------------------+   |
| | 3. SSA-based Machine Optimizations                   |   |
| |    - Machine CSE, LICM                               |   |
| |    - Target-independent optimizations                |   |
| +------------------------------------------------------+   |
|    |                                                       |
|    v                                                       |
| +------------------------------------------------------+   |
| | 4. Register Allocation                               |   |
| |    - Map virtual -> physical registers               |   |
| |    - Graph coloring                                  |   |
| |    - Spilling if necessary                           |   |
| |    - PHI elimination                                 |   |
| +------------------------------------------------------+   |
|    |                                                       |
|    v                                                       |
| +------------------------------------------------------+   |
| | 5. Prolog/Epilog Insertion (PEI)                     |   |
| |    - Generate function entry/exit                    |   |
| |    - Save/restore callee-saved registers             |   |
| +------------------------------------------------------+   |
|    |                                                       |
|    v                                                       |
| +------------------------------------------------------+   |
| | 6. Post-RA Optimizations                             |   |
| |    - Peephole optimization (redundant moves)         |   |
| |    - Branch optimization (folding, inversion)        |   |
| |    - Dead code elimination (unused instructions)     |   |
| +------------------------------------------------------+   |
|    |                                                       |
|    v                                                       |
| +------------------------------------------------------+   |
| | 7. Code Emission                                     |   |
| +------------------------------------------------------+   |
|    |                                                       |
|    v                                                       |
| Machine Code (RISC-V binary)                               |
+------------------------------------------------------------+
```

### Stage I/O

```
+----------+---------------------------+---------------------------+
| Stage    | Input                     | Output                    |
+----------+---------------------------+---------------------------+
| ISel     | LLVM IR                   | MachineIR (virtual regs)  |
|          | %1 = add i32 %a, %b       | %vr1 = ADD %vr2, %vr3     |
+----------+---------------------------+---------------------------+
| Sched    | Unordered MachineIR       | Optimally ordered         |
+----------+---------------------------+---------------------------+
| RegAlloc | INFINITE virtual regs     | FINITE physical regs      |
|          | %vr1 = ADD %vr2, %vr3     | a0 = ADD a1, a2           |
+----------+---------------------------+---------------------------+
| PEI      | Function body (no frame)  | Complete with frame       |
|          | ADD a0, a1, a2            | addi sp, sp, -16          |
|          | RET                       | sw ra, 12(sp)             |
|          |                           | ADD a0, a1, a2            |
|          |                           | lw ra, 12(sp)             |
|          |                           | addi sp, sp, 16           |
|          |                           | RET                       |
+----------+---------------------------+---------------------------+
| Post-RA  | Unoptimized physical regs | Optimized physical regs   |
|          | mv a0, a1                 | (redundant move removed)  |
|          | mv a2, a0                 | beq a1, zero, .L1         |
|          | beq a2, zero, .L1         | (branch optimized)        |
+----------+---------------------------+---------------------------+
```

### Why This Order?

```
ISel first: Need target instructions before scheduling
  |
  v
Pre-RA Sched: Good schedule reduces register pressure
  |          -> Shorter live ranges = easier coloring
  v
RegAlloc: THE CRISIS POINT
  |      -> Unlimited virtuals to limited physicals
  |      -> May need spilling (expensive!)
  v
PEI after RegAlloc: Needs to know which regs were used
  |               -> Cannot determine frame size before
  v
Post-RA opts: Clean up redundancies
```

---

## STAGE 1: Instruction Selection

### The Problem

Transform target-independent IR into target-specific instructions.

**Challenge:** One IR operation → many possible instruction sequences.

```
Example: Load constant 12345

LLVM IR: %1 = i32 12345

Option A (if fits in 12 bits):
  addi a0, zero, 12345    # 1 instruction

Option B (large immediate):
  lui  a0, 0x3            # 2 instructions
  addi a0, a0, 0x39

Option C (from memory):
  lw a0, .LCPI0_0         # 1 instr + memory access

Which to choose? Depends on COST MODEL!
```

### DAG Tiling Theory

```
Step 1: Build SelectionDAG

IR:  %result = add (mul %a, %b), %c

DAG:      add
        /     \
      mul      c
     /   \
    a     b

Step 2: Tile with instruction patterns

Pattern 1: Simple (3 instructions)
      [add]           <- ADD instruction
     /     \
   [mul]   [c]        <- MUL instruction
   /   \
  [a] [b]

Generated: MUL t0, a, b
           ADD result, t0, c

Pattern 2: Fused (1 instruction, if available)
      [madd]          <- MADD (multiply-add)
     /  |   \
    a   b    c

Generated: MADD result, a, b, c

ISel picks Pattern 2 if: Cost(MADD) < Cost(MUL) + Cost(ADD)
```

### TableGen Implementation

```cpp
// Define instruction encoding
class RVInstR<bits<7> funct7, bits<3> funct3, bits<7> opcode> {
  bits<5> rd;
  bits<5> rs1;
  bits<5> rs2;

  let Inst{31-25} = funct7;
  let Inst{24-20} = rs2;
  let Inst{19-15} = rs1;
  let Inst{14-12} = funct3;
  let Inst{11-7}  = rd;
  let Inst{6-0}   = opcode;
}

// Define ADD instruction
def ADD : RVInstR<0b0000000, 0b000, 0b0110011>,
          Sched<[WriteIALU, ReadIALU, ReadIALU]> {
  let AsmString = "add\t$rd, $rs1, $rs2";
}

// Define ISel pattern
def : Pat<(add GPR:$rs1, GPR:$rs2),
          (ADD GPR:$rs1, GPR:$rs2)>;

// Pattern with immediate
def : Pat<(add GPR:$rs1, simm12:$imm),
          (ADDI GPR:$rs1, simm12:$imm)>;
```

### Cost Model

```
Default: Estimated cycles from TargetSubtarget

Example:
  Pattern A: MUL + ADD
    Cost = Latency(MUL) + Latency(ADD) = 3 + 1 = 4 cycles

  Pattern B: MADD (fused)
    Cost = Latency(MADD) = 3 cycles

  ISel chooses Pattern B (lower cost)

For -Os (size): Use instruction byte count instead
```

### References

- **LLVM SelectionDAG**: `llvm/include/llvm/CodeGen/SelectionDAG.h`
- **TableGen Backend**: `llvm/utils/TableGen/CodeGenDAGPatterns.cpp`
- **RISC-V ISel**: `llvm/lib/Target/RISCV/RISCVISelLowering.cpp`
- **Pattern Matching**: `llvm/lib/CodeGen/SelectionDAG/SelectionDAGISel.cpp`
- **LLVM Documentation**: [Instruction Selection](https://llvm.org/docs/CodeGenerator.html#instruction-selection)

---

## STAGE 2: Instruction Scheduling

### The Dual Mission

```
+------------------------------------------------------------+
|        Instruction Scheduling: The Dual Mandate            |
+------------------------------------------------------------+
| Job 1: Hide Hardware Latencies                             |
|   Goal: Keep pipeline FULL                                 |
|   Method: Reorder to fill bubbles                          |
|                                                            |
| Job 2: Minimize Register Pressure                          |
|   Goal: Make RegAlloc EASIER                               |
|   Method: Shorten live ranges                              |
|                                                            |
|                    THE TENSION                             |
| +---------------------------------------------------------+|
| | Job 1 wants: Space out dependent instructions           ||
| |              (needs more registers alive)               ||
| |                                                         ||
| | Job 2 wants: Kill values ASAP                           ||
| |              (fewer registers alive)                    ||
| +---------------------------------------------------------+|
|                                                            |
| Scheduler must balance these competing goals!              |
+------------------------------------------------------------+
```

### Job 1: Hiding Latency

```
Bad Schedule (stalls):
  lw  a0, 0(sp)    # Cycle 0: Issue load (3-cycle latency)
  add a1, a0, a2   # Cycle 1: STALL (a0 not ready)
                   # Cycle 2: STALL
                   # Cycle 3: Add executes

Good Schedule (hide latency):
  lw  a0, 0(sp)    # Cycle 0: Issue load
  add a3, a4, a5   # Cycle 1: Unrelated work
  sub a6, a7, t0   # Cycle 2: More unrelated work
  add a1, a0, a2   # Cycle 3: Now a0 is ready!
```

**List Scheduling Algorithm:**

```
1. Build dependency DAG (nodes=instrs, edges=dependencies)
2. Compute priorities (= longest path to exit)
3. Greedy schedule:
   While (ready set not empty):
     Pick highest priority instruction
     Schedule at earliest legal cycle
     Update ready set
```

### Job 2: Minimizing Register Pressure

```
Live Range = span from definition to last use

Bad Schedule (long ranges):
  Instruction  | v1 | v2 | v3 | Pressure
  -------------+----+----+----+---------
  def v1       | ██ |    |    |    1
  def v2       | ██ | ██ |    |    2
  def v3       | ██ | ██ | ██ |    3 ← Peak!
  use v1       |    | ██ | ██ |    2
  use v2       |    |    | ██ |    1
  use v3       |    |    |    |    0

Interference: v1--v2, v2--v3
Need at least 2 colors (registers)

Good Schedule (short ranges):
  Instruction  | v1 | v2 | v3 | Pressure
  -------------+----+----+----+---------
  def v1       | ██ |    |    |    1
  use v1       |    |    |    |    0 ← v1 dies!
  def v2       |    | ██ |    |    1
  use v2       |    |    |    |    0 ← v2 dies!
  def v3       |    |    | ██ |    1
  use v3       |    |    |    |    0 ← v3 dies!

Interference: NONE!
Need only 1 color - can reuse same register!
```

**Heuristic:** Prefer instructions that:

1. Use OLD values (defined long ago) → kills them early
2. Don't define NEW values → delays new live ranges

### References

- **LLVM Scheduler**: `llvm/include/llvm/CodeGen/ScheduleDAG.h`
- **List Scheduling**: `llvm/lib/CodeGen/ScheduleDAGInstrs.cpp`
- **Machine Scheduler**: `llvm/lib/CodeGen/MachineScheduler.cpp`
- **RISC-V Scheduling**: `llvm/lib/Target/RISCV/RISCVSchedule*.td`
- **LLVM Documentation**: [Machine Instruction Scheduler](https://llvm.org/docs/MIRLangRef.html#scheduling)

### Pre-RA vs Post-RA Scheduling

```
+--------+---------------------------+-------------------------+
|        | Pre-RA                    | Post-RA                 |
+--------+---------------------------+-------------------------+
| When   | BEFORE RegAlloc           | AFTER RegAlloc          |
| Regs   | Virtual (unlimited)       | Physical (fixed)        |
| Goal   | Minimize register pressure| Hide latencies          |
| Freedom| HIGH (can reorder freely) | LOW (register deps)     |
+--------+---------------------------+-------------------------+
```

---

## STAGE 3: SSA-based Machine Optimizations

### Overview

Machine-level optimizations operate on MachineIR (target-specific instructions with virtual registers) but before register allocation. These passes are target-independent and work across all architectures.

**Key passes:**

- **MachineCSE** (Common Subexpression Elimination): Removes redundant computations
- **MachineLICM** (Loop Invariant Code Motion): Moves loop-invariant operations outside loops
- **Machine Copy Propagation**: Eliminates unnecessary register copies
- **Dead Machine Instruction Elimination**: Removes unused instructions

**To write:**

- Detailed analysis of MachineCSE algorithm
- MachineLICM heuristics and profitability analysis
- Interaction with earlier and later passes
- Target-specific customization hooks

**Reference:** See LLVM's `MachineCSE.cpp`, `MachineLICM.cpp`, and related passes in `llvm/lib/CodeGen/`.

---

## STAGE 4: Register Allocation

### The Core Problem

```
+------------------------------------------------------------+
|            The Register Allocation Crisis                  |
+------------------------------------------------------------+
| INPUT: Program with INFINITE virtual registers             |
|   %vreg0 = add %vreg1, %vreg2                              |
|   %vreg3 = mul %vreg0, %vreg4                              |
|   ... (thousands more)                                     |
|                                                            |
| CONSTRAINT: Only K physical registers (K=28 for RISC-V)    |
|                                                            |
| OUTPUT: Map every virtual to a physical register           |
|   a0 = add a1, a2                                          |
|   a3 = mul a0, a4                                          |
|   a0 = add a3, a1    <- Reusing a0!                        |
|                                                            |
| SUCCESS IF: No conflicts                                   |
| FAILURE IF: Not enough registers -> SPILLING               |
+------------------------------------------------------------+
```

### Graph Coloring

```
Step 1: Build Interference Graph

Nodes = virtual registers
Edges = interference (overlapping live ranges)

Example:
  v1 = load ...  ]
  v2 = load ...  ] v1, v2 both alive
  v3 = add v1, v2]
  v4 = mul v3, v1  <- v1, v3, v4 all alive

Interference Graph:
    v1 ---- v2
     |       |
     |       |
    v3 ---- v4

Step 2: K-Color the Graph

Try to assign K colors (registers) such that
adjacent nodes get different colors.

    v1[a0] -- v2[a1]
     |          |
     |          |
    v3[a2] -- v4[a3]

SUCCESS! Used 4 colors for 4-clique.

Step 3: If K-coloring fails -> SPILLING
```

### The Spilling Disaster

```
+------------------------------------------------------------+
|                    Spilling Process                        |
+------------------------------------------------------------+
| 1. Detect Failure: Cannot K-color this graph               |
|                                                            |
| 2. Choose Victim: Pick register to SPILL                   |
|    Heuristic: Minimize spill cost                          |
|    Cost = Σ (use_count × loop_depth_weight)                |
|                                                            |
| 3. Insert Spill Code:                                      |
|    BEFORE: v1 = add v2, v3                                 |
|            v4 = mul v1, v5                                 |
|            v6 = sub v1, v7                                 |
|                                                            |
|    AFTER:  v1 = add v2, v3                                 |
|            sw v1, 4(sp)        <- SPILL to stack           |
|            v4 = mul v1, v5                                 |
|            lw v1, 4(sp)        <- RELOAD from stack        |
|            v6 = sub v1, v7                                 |
|                                                            |
| 4. Try Again: Re-run RegAlloc on modified program          |
|                                                            |
| Performance Impact:                                        |
|   - sw/lw: ~6-10 cycles per spill (L1 cache)              |
|   - In tight loop: 2X slowdown possible!                   |
+------------------------------------------------------------+
```

### LLVM Register Allocators

```
+----------------+----------------------+------------------------+
| Allocator      | Algorithm            | Use Case               |
+----------------+----------------------+------------------------+
| -regalloc=fast | Linear scan (greedy) | Debug builds           |
| -regalloc=     | Iterative graph      | DEFAULT (-O2)          |
|   greedy       | coloring w/ splitting| Good quality           |
| -regalloc=pbqp | Boolean QP           | Research/extreme opt   |
+----------------+----------------------+------------------------+
```

### References

- **Register Allocation**: `llvm/lib/CodeGen/RegAllocGreedy.cpp`
- **Live Intervals**: `llvm/include/llvm/CodeGen/LiveInterval.h`
- **Spilling**: `llvm/lib/CodeGen/InlineSpiller.cpp`
- **Virtual Registers**: `llvm/include/llvm/CodeGen/VirtRegMap.h`
- **LLVM Documentation**: [Register Allocation](https://llvm.org/docs/CodeGenerator.html#register-allocation)
- **Research Paper**: "Iterated Register Coalescing" by George & Appel

---

## STAGE 5: Prolog/Epilog Insertion

### When and Why

```
+------------------------------------------------------------+
|              Prolog/Epilog Insertion (PEI)                 |
+------------------------------------------------------------+
| TIMING: Runs AFTER Register Allocation                     |
|                                                            |
| WHY: RegAlloc provides the "closing report":               |
|   1. Which callee-saved registers were used?               |
|   2. How much stack space for spills?                      |
|   3. Need to save ra? (function makes calls?)              |
|                                                            |
| BEFORE PEI:                                                |
|   add  a0, a1, a2    # Function body                       |
|   mul  s0, a0, a3    # Uses s0 (callee-saved!)            |
|   sw   s1, 4(sp)     # Spill                               |
|   ret                                                       |
|                                                            |
| AFTER PEI:                                                 |
|   addi sp, sp, -16   # PROLOG: Allocate frame             |
|   sw   ra, 12(sp)    #         Save ra                     |
|   sw   s0, 8(sp)     #         Save s0                     |
|   sw   s1, 4(sp)     #         Save s1                     |
|                                                            |
|   add  a0, a1, a2    # Function body (unchanged)           |
|   mul  s0, a0, a3                                          |
|   sw   s1, 4(sp)     # Spill                               |
|                                                            |
|   lw   s1, 4(sp)     # EPILOG: Restore s1                  |
|   lw   s0, 8(sp)     #         Restore s0                  |
|   lw   ra, 12(sp)    #         Restore ra                  |
|   addi sp, sp, 16    #         Deallocate frame            |
|   ret                                                       |
+------------------------------------------------------------+
```

### Stack Frame Layout

```
        High Address
        +------------------+
        | Caller's Frame   |
        +------------------+ <- sp (before call)
        | Return Addr (ra) | \
        +------------------+  |
        | Saved s0 (fp)    |  |
        +------------------+  | Callee-saved
        | Saved s1         |  | registers
        +------------------+  |
        | ...              |  |
        +------------------+  |
        | Saved s11        | /
        +------------------+
        | Spill Slot 0     | \
        +------------------+  | Spill area
        | Spill Slot 1     |  | (from RegAlloc)
        +------------------+  |
        | ...              | /
        +------------------+
        | Local Variables  |
        +------------------+
        | Outgoing Args    | (if calls others)
        +------------------+ <- sp (after prolog)
        | Callee's Frame   |
        +------------------+
        Low Address

Frame Size = callee_saved_space + spill_space +
             locals_space + outgoing_args_space +
             alignment_padding (align to 16 bytes)
```

### PEI Algorithm

```
1. Gather Information
   - Scan function for used callee-saved registers
   - Get spill space size from RegAlloc
   - Check if function makes calls (need ra)

2. Compute Frame Size
   frame_size = 0
   IF uses_ra OR makes_calls:
     frame_size += 8
   FOR each used callee-saved reg:
     frame_size += 8
   frame_size += spill_area_size
   frame_size = ALIGN(frame_size, 16)

3. Insert Prolog (at function entry)
   emit: addi sp, sp, -frame_size
   FOR each used callee-saved reg r:
     emit: sw r, offset(sp)

4. Insert Epilog (before each return)
   FOR each used callee-saved reg r:
     emit: lw r, offset(sp)
   emit: addi sp, sp, frame_size
```

### References

- **Prolog/Epilog Insertion**: `llvm/lib/CodeGen/PrologEpilogInserter.cpp`
- **Frame Lowering**: `llvm/include/llvm/CodeGen/TargetFrameLowering.h`
- **RISC-V Frame Lowering**: `llvm/lib/Target/RISCV/RISCVFrameLowering.cpp`
- **Stack Frame Layout**: `llvm/lib/CodeGen/MachineFrameInfo.cpp`
- **Calling Conventions**: `llvm/lib/Target/RISCV/RISCVCallingConv.td`
- **RISC-V ABI Spec**: [RISC-V Calling Convention](https://github.com/riscv-non-isa/riscv-elf-psabi-doc)

---

## STAGE 6: Post-RA Optimizations & Phi Elimination

### Overview

After register allocation, several optimization passes clean up the generated code by removing redundancies and improving instruction sequences. This stage includes both phi elimination (covered here) and other post-RA optimizations.

**Covered in this section:**

- ✅ **Phi Elimination** - How SSA phi nodes are removed (detailed below)

**To write:**

- **Peephole optimization** - Removing redundant move instructions
- **Branch optimization** - Branch folding, inversion, and simplification
- **Dead code elimination** - Removing unused instructions after register allocation
- **Block placement** - Optimal basic block ordering for better cache performance

---

### Phi Elimination

#### What is Phi?

```
Non-SSA:
  int x;
  if (cond) {
    x = 10;      <- x assigned
  } else {
    x = 20;      <- x assigned again
  }
  return x * 2;

SSA form:
  if (cond) {
    x1 = 10;     <- x1 assigned once
  } else {
    x2 = 20;     <- x2 assigned once
  }
  x3 = phi(x1, x2)  <- Phi "merges" x1 and x2
  return x3 * 2;

Phi semantics:
  x3 = phi [x1, %then], [x2, %else]

  IF control from %then: x3 = x1
  ELSE IF control from %else: x3 = x2
```

### The Problem

**Real CPUs have NO phi instruction!** RegAlloc must eliminate it.

### Case A: Register Coalescing (Good Ending)

```
+------------------------------------------------------------+
|             Phi Elimination: The Good Ending               |
+------------------------------------------------------------+
| Condition: Source and dest DO NOT interfere                |
| Strategy: Assign to SAME physical register                 |
|                                                            |
| LLVM IR:                                                   |
|   then:                                                    |
|     x1 = 10                                                |
|   else:                                                    |
|     x2 = 20                                                |
|   join:                                                    |
|     x3 = phi [x1, then], [x2, else]                        |
|                                                            |
| RegAlloc: x1 -> a0, x2 -> a0, x3 -> a0 (ALL same!)        |
|                                                            |
| Generated Assembly:                                        |
|   then:                                                    |
|     li  a0, 10        # x1 = 10                            |
|     j   join                                               |
|   else:                                                    |
|     li  a0, 20        # x2 = 20                            |
|   join:                                                    |
|     # x3 already in a0 - PHI DISAPPEARED!                  |
|     li  a1, 2                                              |
|     mul a0, a0, a1                                         |
|                                                            |
| COST: ZERO! Phi eliminated for free!                       |
+------------------------------------------------------------+
```

### Case B: Copy Insertion (Bad Ending)

```
+------------------------------------------------------------+
|             Phi Elimination: The Bad Ending                |
+------------------------------------------------------------+
| Condition: High register pressure -> DIFFERENT registers   |
| Strategy: Insert MOVE instructions                         |
|                                                            |
| LLVM IR: (same as above)                                   |
|                                                            |
| RegAlloc: x1 -> a1, x2 -> a2, x3 -> a0 (all different!)   |
|                                                            |
| Generated Assembly:                                        |
|   then:                                                    |
|     ... compute x1 in a1 ...                               |
|     mv  a0, a1        # COPY: a0 = a1 (x3 = x1)           |
|     j   join                                               |
|   else:                                                    |
|     ... compute x2 in a2 ...                               |
|     mv  a0, a2        # COPY: a0 = a2 (x3 = x2)           |
|   join:                                                    |
|     li  t0, 2                                              |
|     mul a0, a0, t0                                         |
|                                                            |
| COST: 2 extra MV instructions!                             |
|       In hot loop -> per-iteration overhead!               |
|       + Those copies USE MORE REGISTERS                    |
|       -> INCREASES register pressure                       |
|       -> May trigger MORE SPILLING                         |
|       -> VICIOUS CYCLE!                                    |
+------------------------------------------------------------+
```

### Optimization Strategies

```
Goal: Make coalescing succeed as often as possible

1. Improve Pre-RA Scheduling
   - Shorten live ranges -> reduce interference

2. Loop Rotation
   - Transform loops to reduce phi nodes in hot paths

3. Tune Spill Cost Heuristics
   - Deprioritize spilling phi-related values

4. Critical Edge Splitting
   - Insert empty blocks to simplify phi placement
```

### References

- **PHI Elimination**: `llvm/lib/CodeGen/PHIElimination.cpp`
- **Register Coalescing**: `llvm/lib/CodeGen/RegisterCoalescer.cpp`
- **Two-Address Instructions**: `llvm/lib/CodeGen/TwoAddressInstructionPass.cpp`
- **Critical Edge Splitting**: `llvm/lib/CodeGen/MachineBasicBlock.cpp`
- **LLVM Documentation**: [SSA-based Machine Code Optimizations](https://llvm.org/docs/CodeGenerator.html#ssa-based-machine-code-optimizations)

---

## STAGE 7: Code Emission

### Overview

Code emission is the final stage where MachineIR (machine instructions with physical registers) is converted to actual machine code in object file format (ELF, Mach-O, COFF).

**Key components:**

- **MCStreamer**: Abstract interface for emitting directives and instructions
- **MCCodeEmitter**: Encodes instructions to binary format
- **MCAsmBackend**: Handles relocations and fixups
- **MCObjectWriter**: Writes final object file format

**Process:**

1. **Lowering**: Convert MachineInstr to MCInst (more detailed representation)
2. **Relaxation**: Adjust instruction encoding (e.g., short vs. long branches)
3. **Encoding**: Convert MCInst to byte sequences
4. **Symbol resolution**: Handle labels, relocations, and external references
5. **Section emission**: Write code, data, and metadata sections

**To write:**

- Detailed MCStreamer API and usage patterns
- Instruction encoding specifics for RISC-V
- Relocation types and linker interaction
- Debug information emission (DWARF)
- Assembly printer vs. object file emission
- Target-specific hooks and customization

**Reference:** See LLVM's `MC/` directory, `MCStreamer.h`, `MCCodeEmitter.h`, and target-specific implementations.

---

## Performance Analysis

### Tool Comparison

```
+------------------+------------------+-------------------------+
| Tool             | Type             | Use Case                |
+------------------+------------------+-------------------------+
| Compiler         | Code Inspector   | Quick experiments       |
| Explorer         |                  | "What asm is generated?"|
| (Godbolt)        |                  |                         |
+------------------+------------------+-------------------------+
| Valgrind/        | Simulator        | Detailed instr counts   |
| Callgrind        | (CPU emulator)   | 100% accurate (slow)    |
+------------------+------------------+-------------------------+
| perf             | Hardware Sampler | GROUND TRUTH            |
| (Linux)          | (PMU counters)   | Real CPU performance    |
|                  |                  | Low overhead (~1%)      |
+------------------+------------------+-------------------------+
```

### perf: The Hardware Truth

```bash
# Record performance data
perf record -F 99 ./myprogram

# View report
perf report

# Count specific events
perf stat -e cycles,instructions,cache-misses ./myprogram

# Annotate hot instructions
perf record -F 999 -g ./myprogram
perf annotate --stdio

# Output example:
#  25.3% | lw  a0, 0(a1)   <- 25% of samples here!
#  15.7% | add a2, a2, a0
#   0.1% | addi a1, a1, 4
#   8.2% | bne a1, a3, .loop
```

**Why perf is essential:** Only real hardware reveals cache effects, branch mispredictions, out-of-order execution, etc.

### The Debugging Loop

```
+------------------------------------------------------------+
|         Performance Debugging Workflow                     |
+------------------------------------------------------------+
| STEP 1: Identify Symptom                                   |
|   perf: "30% of time at address 0x40051C"                  |
|                                                            |
| STEP 2: Diagnose                                           |
|   objdump: "40051C: lw s0, 24(sp)  <- RELOAD!"            |
|   Red Flag: Expensive memory load in hot path              |
|                                                            |
| STEP 3: Form Hypothesis                                    |
|   "This is a Register Spill! WHY?"                         |
|   - Too much register pressure?                            |
|   - Bad scheduling lengthened live ranges?                 |
|   - ISel chose wrong instructions?                         |
|                                                            |
| STEP 4: Investigate Compiler                               |
|   Recompile with: -debug-only=regalloc                     |
|   Trace: Which virtual reg was spilled? Why?               |
|                                                            |
| STEP 5: Implement Fix                                      |
|   - Modify ISel patterns (.td files)                       |
|   - Tune scheduling heuristics                             |
|   - Write custom optimization pass                         |
|                                                            |
| STEP 6: Verify                                             |
|   Re-measure with perf, confirm hotspot eliminated         |
+------------------------------------------------------------+
```

### LLVM Debug Flags

```bash
# View ISel decisions
llc -march=riscv64 -debug-only=isel input.ll

# View RegAlloc decisions
llc -march=riscv64 -debug-only=regalloc input.ll

# Print MachineIR after each pass
llc -march=riscv64 -print-after-all input.ll

# Print after specific pass
llc -march=riscv64 -print-after=prologepilog input.ll

# View SelectionDAG
llc -march=riscv64 -view-dag-combine1-dags input.ll

# Verify correctness
llc -march=riscv64 -verify-machineinstrs input.ll

# Time each pass
llc -march=riscv64 -time-passes input.ll
```

---

## Practical Optimization Cases

### Case 1: Eliminating Spills in Loop

**Problem:** Hot loop with excessive spilling

```c
int dotproduct(int *a, int *b, int n) {
  int sum = 0;
  for (int i = 0; i < n; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}
```

**Bad Assembly (with spills):**

```asm
dotproduct:
  addi sp, sp, -32    # Prolog
  sw   ra, 28(sp)
  sw   s0, 24(sp)     # Save s0-s5
  sw   s1, 20(sp)
  sw   s2, 16(sp)
  sw   s3, 12(sp)

  li   s0, 0          # sum
  li   s1, 0          # i
.loop:
  slli s2, s1, 2
  add  s3, a0, s2
  lw   s3, 0(s3)      # a[i]

  sw   s3, 0(sp)      # SPILL s3 !!!

  add  s2, a1, s2
  lw   s2, 0(s2)      # b[i]

  lw   s3, 0(sp)      # RELOAD s3 !!!

  mul  s3, s3, s2
  add  s0, s0, s3
  addi s1, s1, 1
  blt  s1, a2, .loop

  mv   a0, s0
  # Epilog ...
  ret
```

**Root Cause:**

- Uses 7 virtual registers
- Only 6 callee-saved regs available
- Must spill 1 register
- Callee-saved registers require prolog/epilog

**Solution: Use caller-saved registers**

```c
int dotproduct_opt(int *a, int *b, int n) {
  int sum = 0;
  int *end = a + n;
  while (a < end) {
    sum += (*a++) * (*b++);
  }
  return sum;
}
```

**Good Assembly (no spills):**

```asm
dotproduct_opt:
  li   a4, 0          # sum (use a4, caller-saved!)
  slli a2, a2, 2
  add  a2, a0, a2     # end = a + n
.loop:
  lw   a3, 0(a0)      # *a
  lw   a5, 0(a1)      # *b
  mul  a3, a3, a5
  add  a4, a4, a3     # sum += ...
  addi a0, a0, 4      # a++
  addi a1, a1, 4      # b++
  blt  a0, a2, .loop
.exit:
  mv   a0, a4
  ret                 # NO PROLOG/EPILOG!
```

**Results:**

- Before: 7 vregs, 1 spill/reload, 12 cycles/iter
- After: 5 vregs, 0 spills, 7 cycles/iter
- **Speedup: 1.7x**

**Lessons:**

1. Caller-saved registers are FREE in leaf functions
2. Shorter live ranges = less interference
3. Sometimes algorithm change > compiler tricks

---

### Case 2: Custom ISel Pattern

**Scenario:** Your CPU has custom multiply-accumulate instruction

```cpp
// Define custom instruction
def MACC : RVInstR4<0b1000011, 0b000, OPC_CUSTOM_0,
                    (outs GPR:$rd),
                    (ins GPR:$rs1, GPR:$rs2, GPR:$rs3),
                    "macc", "$rd, $rs1, $rs2, $rs3"> {
  let Latency = 3;  // 3-cycle latency
}

// ISel pattern: match (a * b) + c
def : Pat<(add (mul GPR:$rs1, GPR:$rs2), GPR:$rs3),
          (MACC GPR:$rs1, GPR:$rs2, GPR:$rs3)>;
```

**Test:**

```c
int mac(int a, int b, int c) {
  return (a * b) + c;
}
```

**Generated Assembly:**

```asm
mac:
  macc a0, a0, a1, a2    # MACC instruction used!
  ret
```

**Performance:**

- Without MACC: MUL (3 cyc) + ADD (1 cyc) = 4-5 cycles
- With MACC: 3 cycles
- **Speedup: 1.3x for this pattern**

---

### Case 3: Loop Unrolling vs Register Pressure

**Problem:** Aggressive unrolling causes spilling

```c
void vector_add(float *a, float *b, float *c, int n) {
  for (int i = 0; i < n; i++) {
    c[i] = a[i] + b[i];
  }
}
```

**Unroll 8X:** Uses 26 virtual registers → tight pressure → spilling

**Unroll 2X:** Uses 9 virtual registers → no spilling

**Results:**

- Unroll 8 with spills: 100 cycles/iter
- Unroll 2 without spills: 60 cycles/iter
- **Speedup: 1.67x by REDUCING unrolling!**

**Lesson:** More unrolling ≠ better performance. Must balance ILP vs register pressure.

---

## Appendix: Quick Reference

### Common RISC-V Instructions

```
ADD   rd, rs1, rs2       rd = rs1 + rs2
SUB   rd, rs1, rs2       rd = rs1 - rs2
ADDI  rd, rs1, imm       rd = rs1 + imm
MUL   rd, rs1, rs2       rd = rs1 * rs2
DIV   rd, rs1, rs2       rd = rs1 / rs2
LW    rd, offset(rs1)    rd = Mem[rs1 + offset]
SW    rs2, offset(rs1)   Mem[rs1 + offset] = rs2
BEQ   rs1, rs2, label    if (rs1 == rs2) goto label
BNE   rs1, rs2, label    if (rs1 != rs2) goto label
JAL   rd, label          rd = PC+4; goto label
LUI   rd, imm            rd = imm << 12
```

---

## Conclusion

**Key Takeaways:**

1. Backend engineering = **hardware-software tradeoffs**
2. **Three Pillars** (ISel, RegAlloc, Scheduling) are interconnected
3. **Register pressure** is the ultimate bottleneck
4. **Profile with real hardware** (perf) - simulators can't see everything
5. **TableGen** = declarative hardware description
6. **TargetSubtarget** = source of truth for performance

**Success requires:**

- Deep understanding of hardware AND software
- Assembly reading fluency
- Systematic debugging methodology
- LLVM source code diving skills
- Performance engineering mindset

**Remember:** The best backend engineers understand the entire stack from silicon to software and optimize the bridge between them.

---

## Additional Resources

### LLVM Core Documentation

- [LLVM Code Generator](https://llvm.org/docs/CodeGenerator.html)
- [TableGen Language Reference](https://llvm.org/docs/TableGen/index.html)
- [Writing an LLVM Backend](https://llvm.org/docs/WritingAnLLVMBackend.html)
- [LLVM Language Reference](https://llvm.org/docs/LangRef.html)

### RISC-V Resources

- [RISC-V Foundation](https://riscv.org/)
- [RISC-V Software Repository](https://github.com/riscv)
- [RISC-V Toolchain Documentation](https://github.com/riscv-collab/riscv-gnu-toolchain)

### Research Papers

- "A Retargetable Compiler for ANSI C" - Fraser & Hanson
- "Engineering a Compiler" - Cooper & Torczon
- "Modern Compiler Implementation in C" - Appel
- "Superoptimizer: A Look at the Smallest Program" - Massalin

### Source Code Study

- RISC-V Backend: `llvm/lib/Target/RISCV/`
- CodeGen Infrastructure: `llvm/lib/CodeGen/`
- Target-Independent SelectionDAG: `llvm/lib/CodeGen/SelectionDAG/`
- Machine IR: `llvm/include/llvm/CodeGen/Machine*.h`
