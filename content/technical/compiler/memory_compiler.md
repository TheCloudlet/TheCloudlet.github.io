+++
title = """
  What "Memory Compiler" Actually Means: From Bitcells to GDS Tiling
  """
author = ["Yi-Ping Pan (Cloudlet)"]
description = "What does a memory compiler actually do? From T-diagrams and 6T bitcells to GDS tiling, LVS, and the symmetry between memory compiler tiling and ML compiler tiling."
date = 2026-05-29
draft = false
+++

> Most people see the name "memory compiler" and have no idea what it actually does.

---


## 1. Compiler Representation {#1-dot-compiler-representation}

The classical representation is the **[T-diagram](https://en.wikipedia.org/wiki/Tombstone_diagram)** (or Tombstone diagram). It characterizes a compiler by three languages: the source language it reads (A), the target language it emits (B), and the implementation language it is written in (C):

```text
┌───┬───┐
│ A → B │
└───┴───┘
    │ C
```

Read it as: "a program that translates A into B, written in C."

The textbook example is C → machine code. But the definition is broader than that:

-   Typical compiler: C / C++ → assembly / machine code
-   The compiler I work on at Synopsys: VHDL / Verilog RTL → simulation / debugging database
-   **Memory compiler**: design parameters (depth, width, port…) → all views needed to tape out a chip
-   Shader compiler: GLSL / HLSL → GPU machine code (e.g., Mesa's NIR pipeline, DXC)
-   Query compiler: SQL → a physical execution plan (e.g., PostgreSQL's planner/executor)
-   Bytecode compiler: Java source → JVM bytecode (javac), or JavaScript → V8 bytecode (Ignition)

---


## 2. The Raw Material: Inside a Bitcell {#2-dot-the-raw-material-inside-a-bitcell}

The fundamental building block of any [SRAM (Static Random-Access Memory)](https://en.wikipedia.org/wiki/Static_random-access_memory) is the **bitcell** — a tiny circuit that holds one bit. Hardware teams design and characterize these cells by hand; the memory compiler's job is to replicate them at scale.

The most common variant is the **6T bitcell** (six transistors). Three signal lines connect it to the outside world: `WL` (Word Line — selects a row), `BL` (Bit Line), and `BLB` (Bit Line Bar, the complementary signal):

```text
                WL
══════════════════╦══════════════════════════════╦════════
                  ║                              ║
            ┌─────╫──────────────────────────────╫─────┐
            │   [ M5 ]                         [ M6 ]  │
            │     │                              │     │
       BL ──┼─────●───── Q               Q' ─────●─────┼── BLB
            │            │               │             │
            │            │   ┌───────┐   │             │
            │            ├─►─┤ INV_R ├───┤             │
            │            │   │(M2,M4)│   │             │
            │            │   └───────┘   │             │
            │            │               │             │
            │            │   ┌───────┐   │             │
            │            ├───┤ INV_L ├─◄─┤             │
            │            │   │(M1,M3)│   │             │
            │            │   └───────┘   │             │
            │                                          │
            │                bitcell (6T)              │
            └──────────────────────────────────────────┘
```

Transistor count:

-   `INV_L`: PMOS M3 + NMOS M1 = 2
-   `INV_R`: PMOS M4 + NMOS M2 = 2
-   Access transistors: M5, M6 = 2
-   Total: 6 → "6T"


### Positive Feedback: How a Bit Gets Locked {#positive-feedback-how-a-bit-gets-locked}

Two inverters connected head-to-tail (**cross-coupled**):

1.  Assume `Q` = 1 (high, `Vdd`)
2.  `INV_R` receives 1, outputs 0 to `Q'`
3.  `INV_L` receives 0, outputs 1 back to `Q`
4.  `Q` stays 1 — a perfect closed loop

This is **positive feedback + bistability**. As long as `Vdd` is present, `Q` and `Q'` are locked at opposite voltages indefinitely. The stored bit is literally just the voltage sitting on those two nodes. SRAM is called "Static" because — unlike DRAM — it never needs to refresh.


### Three Operations {#three-operations}


#### Hold (Standby) {#hold--standby}

-   `WL` = 0, access transistors off
-   Cross-coupled inverters maintain state entirely on their own; only leakage current flows
-   Strictly speaking, Hold is a _state_, not an operation — but datasheets list it alongside Read/Write because designers need leakage current figures for power budgeting


#### Read {#read}

1.  Precharge `BL` and `BLB` to Vdd
2.  Assert `WL` high; M5 and M6 turn on
3.  The side storing 0 pulls its bitline down by ~100 mV
4.  Sense amplifier amplifies the small differential → 1 bit out

**Read Disturbance**: the moment `WL` turns on, the high-voltage `BLB` can pull up Q' (the node storing 0) slightly through M6. If it rises past the switching threshold of `INV_L`, the cell flips — a **Destructive Read**. The fix is making the pull-down NMOS M2 stronger (wider) than the access transistor M6. This strength ratio is the **Beta Ratio** (β = W_pull-down / W_access), typically required to be &gt; 1. This is why the six transistors in a standard bitcell are not all the same size.


#### Write {#write}

1.  Write driver forces `BL` and `BLB` to target values (one high, one low)
2.  Assert `WL` high
3.  Write driver strength overcomes the cell's pull-up → forces the cell to flip
4.  The sizing trade-off between these forces is called the **pull-up ratio**


### Beyond 6T: Other Bitcell Types {#beyond-6t-other-bitcell-types}

6T is not the only option. Different use cases demand different trade-offs:

| Cell | Transistors | Key property                        | Typical use               |
|------|-------------|-------------------------------------|---------------------------|
| 6T   | 6           | High density, standard read/write   | L2/L3 caches              |
| 8T   | 8           | Isolated read port, no read disturb | L1 caches, register files |
| 10T  | 10          | Ultra-low voltage operation         | Near-threshold designs    |

The 8T cell adds a dedicated read path (two extra transistors) so the read operation never touches the storage nodes — eliminating read disturbance entirely at the cost of ~33% more area.

---


## 3. Why a Memory Compiler Exists {#3-dot-why-a-memory-compiler-exists}

When a hardware team designs an [SoC (System on Chip)](https://en.wikipedia.org/wiki/System_on_a_chip), they need SRAM — lots of it, at many different sizes. The fundamental unit they work with is a **cell**: the smallest verified building block of an SRAM array. But a chip might need an SRAM of depth 512 × width 32 in one place, and depth 4096 × width 64 in another. Redesigning a new cell from scratch for every configuration is not feasible.

The solution is a **parameterized IP**: instead of a fixed design, you ship a tool that accepts parameters and generates the correct implementation automatically. That tool is the memory compiler. Given depth, width, port count, and a few other knobs, it produces a complete, tapeout-ready SRAM macro.

A memory compiler generates a complete, self-contained SRAM macro — the bitcell array plus all the peripheral circuitry needed to operate it: row/column decoders, sense amplifiers, write drivers, and self-timed control. What it does not generate is the memory controller — the system-level logic that decides what to read and write, handles arbitration and BIST sequencing, and lives in the SoC RTL outside the macro.

```text
Leaf cell views              ┌──────────────────────────────┐     Generated View
(from hardware team):        │        Memory Compiler       │
                             │                              │
 .gds / .oas (layout) ──────>│                              │───> .gds / .oas
 .lef        (abstract) ────>│                              │───> .lef
 .cdl / .sp  (netlist) ─────>│                              │───> .lib
 .lib        (timing)  ─────>│                              │───> .v  (Verilog)
                             │                              │───> .sp / .cdl
Parameters:                  │                              │───> .cpf / .upf
                             │                              │───> .pat  (ATPG/MBIST)
 depth            ──────────>│                              │───> .pdf  (Datasheet)
 width            ──────────>│                              │
 port             ──────────>│                              │
 mux factor       ──────────>│                              │
 corner (PVT)     ──────────>│                              │
                             └──────────────────────────────┘
```


### Output Views {#output-views}

| View       | Format                                                                                                                                      | Used by                                                                                                        |
|------------|---------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------|
| Layout     | [GDS](https://en.wikipedia.org/wiki/GDSII) / [OASIS](https://en.wikipedia.org/wiki/Open_Artwork_System_Interchange_Standard)                | Tapeout, sent to fab                                                                                           |
| Abstract   | [LEF](https://en.wikipedia.org/wiki/Library_Exchange_Format)                                                                                | [P&amp;R (Place and Route)](https://en.wikipedia.org/wiki/Place_and_route) — exposes pins + blockage only      |
| Timing     | `.lib` ([Liberty](https://en.wikipedia.org/wiki/Liberty_File_Format))                                                                       | [STA (Static Timing Analysis)](https://en.wikipedia.org/wiki/Static_timing_analysis) — setup/hold, access time |
| Behavioral | Verilog / SV                                                                                                                                | RTL simulation                                                                                                 |
| Netlist    | SPICE / [CDL](https://en.wikipedia.org/wiki/Circuit_description_language)                                                                   | SPICE simulation, [LVS](https://en.wikipedia.org/wiki/Layout_Versus_Schematic)                                 |
| Power      | `.lib` / [CPF](https://en.wikipedia.org/wiki/Common_Power_Format) / [UPF](https://en.wikipedia.org/wiki/Unified_Power_Format)               | Power analysis                                                                                                 |
| Test       | [ATPG](https://en.wikipedia.org/wiki/Automatic_test_pattern_generation) / [MBIST](https://en.wikipedia.org/wiki/Built-in_self-test) pattern | [DFT (Design for Testability)](https://en.wikipedia.org/wiki/Design_for_testing) / manufacturing test          |

---


## 4. Two Teams, One Boundary {#4-dot-two-teams-one-boundary}

A memory compiler sits at the intersection of two teams with very different jobs.


### The Hardware Team: Designing the Leaf Cell {#the-hardware-team-designing-the-leaf-cell}

The hardware team — circuit designers and layout engineers — designs and verifies the **leaf cell**: the smallest possible SRAM unit. Designing a single 6T bitcell involves resolving multiple interacting constraints:

-   Transistor sizing (Beta ratio, pull-up ratio) to balance read stability vs. write ability
-   Full-custom layout at the process node's design rules
-   Characterization across all PVT corners (dozens of SPICE simulations)
-   Sign-off: [DRC (Design Rule Check)](https://en.wikipedia.org/wiki/Design_rule_check), [LVS (Layout vs Schematic)](https://en.wikipedia.org/wiki/Layout_Versus_Schematic), antenna checks, electromigration

The hardware team delivers a small set of verified, hand-crafted files — GDS, CDL, LEF, `.lib` — for that one leaf cell. **Their job ends at the single-cell boundary.**


### The CAD Team: Building the Compiler {#the-cad-team-building-the-compiler}

The CAD team (or memory compiler team) takes those verified leaf cells and builds the automation that scales them to any size. Their job is to answer: given a leaf cell that works correctly in isolation, how do you tile it into an array of arbitrary depth × width while guaranteeing:

1.  **LVS passes** — GDS and netlist tiling must match exactly
2.  **DRC passes** — abutment boundaries must be clean at every process node's design rules
3.  **All output views are consistent** — the `.lib` timing model, the Verilog behavioral model, the SPICE netlist, and the GDS all describe the same circuit


### Why Not Just Write a Script? {#why-not-just-write-a-script}

A script-based flow (e.g., using Tcl or Python) is a common initial approach for structural assembly. While functional for simple cases, it introduces specific limitations as complexity scales:

| Problem                 | Why a script struggles                                                                                  |
|-------------------------|---------------------------------------------------------------------------------------------------------|
| Multiple output formats | Each format has different tiling logic; keeping them in sync manually is error-prone                    |
| LVS correctness         | A single off-by-one in row numbering silently produces an LVS mismatch across thousands of nets         |
| New configurations      | Adding a new mux ratio or port combination requires touching tiling logic in every format independently |
| Regression safety       | No shared data model means a fix in GDS tiling doesn't automatically propagate to netlist tiling        |
| Bitcell swap            | Changing the leaf cell requires hunting down every hardcoded assumption across every format script      |

The last point deserves emphasis. In a script-based flow, the bitcell's geometry and netlist structure leak into the tiling logic — net names, transistor counts, pin locations get hardcoded. Swap a 6T cell for an 8T cell, and the script breaks in multiple places simultaneously, across multiple files, in ways that may not be immediately obvious.

A memory compiler treats the bitcell views (GDS, CDL, `.lib`) as **inputs**, not assumptions baked into the code. The tiling engine doesn't know or care what's inside the cell — it only knows how to replicate and connect it. Swap the input files, and every output format updates automatically. Consistency is structural, not manual.

A memory compiler solves this by having **one data structure drive all emitters**. The tiling logic runs once; GDS, CDL, Verilog, and `.lib` are all derived outputs. This is the same architectural insight behind any compiler: separate the representation of intent from the multiple backends that render it.

---


## 5. The Parameter Space {#5-dot-the-parameter-space}


### depth × width — Array Shape {#depth-width-array-shape}

```text
     <──── width = 32 bits ────>
┌──┬──┬──┬──┬──┬──┬──┬── ... ──┐  ↑
│  │  │  │  │  │  │  │         │  │
├──┼──┼──┼──┼──┼──┼──┼── ... ──┤  │
│  │  │  │  │  │  │  │         │  depth = 1024 words
├──┼──┼──┼──┼──┼──┼──┼── ... ──┤  │
│  │  │  │  │  │  │  │         │  │
└──┴──┴──┴──┴──┴──┴──┴── ... ──┘  ↓
Total bits = 1024 × 32 = 32,768 bits
```


### port — Independent Access Channels {#port-independent-access-channels}

| Feature       | 1-Port (1P / 1RW) | Multi-Port (e.g., 2R1W)             |
|---------------|-------------------|-------------------------------------|
| Address buses | 1                 | 2+ (separate read addr, write addr) |
| Concurrency   | Read **or** Write | Read **and** Write simultaneously   |
| Bitcell       | Standard 6T       | 8T (isolated read port)             |
| Area          | High density      | ~1.5x–2.0x penalty                  |
| Applications  | L1/L2/L3 caches   | CPU register files, FIFOs           |

Register files require multi-port arrays to prevent pipeline stalls. Executing `ADD R1, R2, R3` requires reading R2 and R3 simultaneously while writing back a previous instruction's result into R1. A 1-port SRAM forces serial execution, breaking pipeline concurrency. Consequently, register files absorb the 8T area penalty to sustain throughput.


### mux factor — Column Multiplexer Ratio {#mux-factor-column-multiplexer-ratio}

Sense amplifiers are expensive in area. The mux factor decides how many bitline columns share one sense amp:

```text
 mux=1 (no mux):              mux=4:
 one SA per column             one SA per 4 columns
 ┌─┬─┬─┬─┐                   ┌─┬─┬─┬─┐
 │ │ │ │ │                   │ │ │ │ │
SA SA SA SA                  └─┴─┴─┴─┘
                                    SA
 fastest, widest layout        slower, narrower layout

 // SA = Sense Amplifier: detects the small voltage differential
 //      on BL/BLB and amplifies it to a full logic level
```

**An easy-to-miss point**: mux factor doesn't only affect area — it directly affects latency. Every cycle spent selecting which column connects to the sense amp is latency. Higher mux factor means longer bitlines, more capacitance, and a slower sense amp enable. **A significant portion of cache access latency is hiding inside the column mux** — this is a first-class trade-off knob in L1 microarchitecture design, not just a layout convenience.


### corner — PVT (Process, Voltage, Temperature) {#corner-pvt--process-voltage-temperature}

```text
Process:  TT (typical), SS (slow), FF (fast)
Voltage:  0.72V (low),  0.8V (nom),  0.88V (high)
Temp:     -40°C, 25°C, 125°C

SS + high temp + low voltage  → worst-case timing (setup check)
FF + low temp  + high voltage → best-case timing  (hold check)
```

The `.lib` file contains one timing table per corner. The memory compiler must pass Static Timing Analysis (STA) at every corner.


### Putting It Together: Full Array Structure {#putting-it-together-full-array-structure}

```text
                  BL_0  BL_1  BL_2  BL_3  BL_4  BL_5  BL_6  BL_7
                   │     │     │     │     │     │     │     │
addr[A-1:M]        ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼
(high bits)   ┌────────────────────────────────────────────────────┐
┌───────┐     │   ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐   │
│   R   │────►│   └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘   │◄─ WL_0
│   o   │     │   ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐   │
│   w   │────►│   └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘   │◄─ WL_1
│       │     │   ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐   │
│   D   │────►│   └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘   │◄─ WL_2
│   e   │     │   ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐   │
│   c   │────►│   └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘   │◄─ WL_3
└───────┘     │     6T bitcell array (depth rows × width cols)     │
              └────────────────────────────────────────────────────┘
                   │     │     │     │     │     │     │     │
                   ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼
              ┌────────────────────────────────────────────────────┐
              │         Sense Amplifiers (one per BL pair)         │
              └─────────────────────────┬──────────────────────────┘
                                        │  (mux=2: 8 cols → 4 sense amps → 4 outputs)
addr[M-1:0]                             ▼
(low bits)    ┌────────────────────────────────────────────────────┐
select col    │                Column MUX / Decoder                │
              └─────────────────────────┬──────────────────────────┘
                                        │
                                        ▼
                              Data I/O (width bits)
```

---


## 6. Cache Hierarchy and SRAM Selection {#6-dot-cache-hierarchy-and-sram-selection}

Different cache levels have different requirements, and those requirements directly determine which bitcell to use:

| Cache | Distance from CPU | Priority              | Cell choice                 | Reason                                                                                                                             |
|-------|-------------------|-----------------------|-----------------------------|------------------------------------------------------------------------------------------------------------------------------------|
| L1    | Nearest           | Speed, concurrent R/W | 6T or 8T (design-dependent) | Pipeline needs read + write in the same cycle; high-perf designs often use fast 6T, multi-port 8T is more common in register files |
| L2    | Middle            | Balance               | 6T 1-port                   | Speed matters, but so does density                                                                                                 |
| L3    | Farthest          | Capacity, low power   | 6T 1-port (dense)           | Area is the primary concern; PPA must hold                                                                                         |

L1 needs concurrent read and write because the pipeline demands it — hence 8T. But an 8T array is 1.5x–2x the area of 6T. At L3 scale (tens of megabytes), the area overhead of 8T becomes prohibitive, making it difficult to satisfy standard [PPA (Power, Performance, Area)](https://en.wikipedia.org/wiki/Power,_Performance,_Area) targets.

In SoC modeling, all of these decisions need to be captured together, ideally in a cycle-latency-accurate performance simulator, so different cache hierarchy configurations can be evaluated against actual performance targets. I built [Stratum](https://thecloudlet.github.io/technical/project/stratum/) for exactly this — a configurable cache simulator where hierarchy topology is bound at compile time, mirroring how memory systems are fixed at hardware synthesis.

---


## 7. How the Array Is Built: Tiling in Two Representations {#7-dot-how-the-array-is-built-tiling-in-two-representations}

How does a memory compiler go from a single leaf cell to a full array? **Tiling** — like laying floor tiles:

```text
leaf cell (6T)
┌──┐
│  │  ×  (depth rows × width cols)  →  complete bitcell array
└──┘
```

The critical constraint: the compiler must produce two representations simultaneously, and they must **match exactly**:

```text
GDS  --[extraction]--> netlist A --+
                                   +--> [LVS tool] --> PASS or FAIL
CDL / SPICE netlist B -------------+
```

This is **[LVS (Layout vs Schematic)](https://en.wikipedia.org/wiki/Layout_Versus_Schematic)**. An [EDA (Electronic Design Automation)](https://en.wikipedia.org/wiki/Electronic_design_automation) tool like Calibre reads the GDS polygons, infers transistors and connections, and compares the resulting netlist against the schematic netlist you generated. One mismatched net name, one missing transistor → LVS fails → tapeout blocked.


### GDS Tiling (layout layer) {#gds-tiling--layout-layer}

-   Operates on geometry: polygons, vias, metal layers
-   Places GDS sub-cells on a grid with abutment-aligned boundaries: power rails, BL, and WL must connect cleanly at every edge
-   **Boundary handling (abutment) is the hardest part**: the bitcell array must interface with the row decoder, column mux, sense amp, and control logic
-   Output: `.gds` / `.oas`


### Netlist Tiling (schematic layer) {#netlist-tiling--schematic-layer}

-   Operates on instances and nets
-   Follows the same tiling pattern to instantiate and wire SPICE/CDL sub-circuits
-   Output: `.sp` / `.cdl` / Verilog netlist

**Common LVS failures in a memory compiler:**

-   `BL_0` in the netlist is connected to `BL_1` in the GDS abutment
-   GDS tiling added one extra row of bitcells but the netlist wasn't updated
-   A missing via in GDS leaves two nets floating that should be shorted

This is why memory compilers demand extreme rigor: **GDS and netlist tiling logic must share a single source of truth** — one data structure drives both emitters. Any new feature (new mux ratio, new port combination) must not break LVS, and automated regression tests (pytest) are the only way to sleep at night.


### Cell Flipping: Mirrored Abutment {#cell-flipping-mirrored-abutment}

When tiling, adjacent rows of bitcells are not simply copied — they are **vertically mirrored** before being placed:

```text
WL0: normal orientation  → top: Vdd,  bottom: GND
WL1: flipped upside-down → top: GND,  bottom: Vdd

→ WL0's bottom GND and WL1's top GND overlap perfectly
→ two rows share a single GND rail; no extra DRC spacing needed
```

-   **Power rail sharing**: Vdd/GND rails are shared between adjacent rows, eliminating one full metal rail
-   **Bitline contact sharing**: access transistors in adjacent rows share the same BL contacts, cutting contact count in half
-   **N-Well / P-Well continuity**: PMOS transistors live in N-Well; mirrored placement lets adjacent N-Wells merge seamlessly, avoiding the large Well-to-Well isolation spacing penalty

---


## 8. What Makes It Production-Grade {#8-dot-what-makes-it-production-grade}


### EMA — A Post-Silicon Timing Knob {#ema-a-post-silicon-timing-knob}

Memory internal read/write timing is **asynchronous and self-timed**: dummy bitlines and delay cells decide when to fire the sense amp, independent of the external clock.

When process variation causes read failures or insufficient write margin, **EMA (Extra Margin Adjustment)** pins provide a post-fabrication fix:

-   **EMA**: adjusts `WL` pulse width and `SA` enable delay (read margin)
-   **EMAW**: adjusts timing margin for write operations

Increasing EMA gives the bitcell more time to pull down the bitline → larger differential voltage → better Read [SNM (Static Noise Margin)](https://en.wikipedia.org/wiki/Noise_margin) → better yield, at the cost of slightly longer access time. This is a three-way trade-off between area, speed, and yield.


### Low Power: VDDC vs VDDP Dual-Rail {#low-power-vddc-vs-vddp-dual-rail}

SRAM arrays are often the largest, leakiest structures on an SoC. Memory compilers must support power gating and generate corresponding `UPF~/~CPF` files:

| Rail | Supplies                              | Can be shut off? |
|------|---------------------------------------|------------------|
| VDDC | 6T bitcell array itself               | No (kills data)  |
| VDDP | Address decoders, sense amps, control | Yes              |

Three power states:

1.  **Light Sleep**: gate peripheral clocks, reduce dynamic switching power
2.  **Deep Sleep (Retention)**: shut off VDDP (periphery fully off), reduce VDDC voltage just enough to keep cross-coupled inverters locked — data retained
3.  **Shutdown**: both VDDC and VDDP off — all data lost


### Redundancy — Repairing Manufacturing Defects {#redundancy-repairing-manufacturing-defects}

Tiling millions of deep sub-micron transistors at maximum density means manufacturing defects are statistically unavoidable. Discarding a whole SoC for one dead bitcell would be economically catastrophic.

The solution is **built-in redundancy**:

1.  The compiler automatically generates spare redundant columns alongside the main array
2.  During manufacturing test, the **MBIST** engine identifies all failing addresses
3.  An **eFuse** is permanently blown, recording the bad column
4.  On every power-up, identical MUX logic redirects that column's I/O to the redundant spare
5.  The memory appears completely intact to the outside world

---


## 9. Two Directions of Tiling {#9-dot-two-directions-of-tiling}

The concept of "tiling" exists in both EDA and ML compiler domains, mapping to structurally opposite operations.


### Memory Compiler Tiling: Small → Large (Assembling) {#memory-compiler-tiling-small-large--assembling}

Memory compiler tiling takes a designed leaf cell and replicates it into a full array, like laying floor tiles:

```text
small leaf cell  →  tile into  →  large SRAM array

   ┌──┐                             ┌────────────┐
   │6T│  ×  (R rows × C cols)   →   │            │
   └──┘                             │   array    │
                                    │            │
                                    └────────────┘
```

Direction: **bottom-up, assembling**


### ML Compiler Tiling: Large → Small (Decomposing) {#ml-compiler-tiling-large-small--decomposing}

ML compiler tiling (e.g., [GEMM (General Matrix Multiplication)](https://en.wikipedia.org/wiki/General_matrix_multiply) on an [NPU (Neural Processing Unit)](https://en.wikipedia.org/wiki/AI_accelerator)) takes a large computation and cuts it into pieces that fit the hardware:

```text
full GEMM computation (M × N × K)  →  cut into  →  hardware-sized tiles

┌──────────────────┐                   ┌──┬──┬──┐
│                  │                   │  │  │  │
│   A (M×K)        │  →   tiling   →   ├──┼──┼──┤
│   × B (K×N)      │                   │  │  │  │
│                  │                   └──┴──┴──┘
└──────────────────┘             each tile fits in SRAM + systolic array
```

The constraint: an NPU's systolic array is a fixed size, and the on-chip SRAM is bounded. You can't feed the whole matrix at once. Tiling decomposes the computation into sizes that maximize hardware utilization and minimize memory bandwidth bubbles.

Direction: **top-down, decomposing**


### The Symmetry {#the-symmetry}

| Context             | Input → Output     | Direction     |
|---------------------|--------------------|---------------|
| **Memory Compiler** | leaf → array       | small → large |
| **ML Compiler**     | computation → tile | large → small |

---


## 10. Two Open Questions {#10-dot-two-open-questions}


### Chisel and the Memory Compiler Interface {#chisel-and-the-memory-compiler-interface}

Chisel treats memory as a first-class language primitive. When you write `SyncReadMem(1024, UInt(32.W))`, you are not instantiating a specific SRAM macro — you are declaring intent: _I need something that behaves like a 1024-entry synchronous-read memory._ The implementation is deliberately unspecified.

This abstraction breaks down at tapeout. Modern CAD tools cannot synthesize SRAM macros from an RTL description; without intervention, `FIRRTL` maps all `SeqMem` instances to flip-flop arrays, which are functionally correct but physically unroutable at scale. The fix is a `FIRRTL` transform called `ReplSeqMem`: it scans the design, converts every `SeqMem` above a size threshold into an external module reference (a black box with only pins visible), and outputs a `.conf` file listing every unique SRAM configuration the design requires.

That `.conf` file is then consumed by `MacroCompiler` (part of Chipyard's Tapeout-Tools). `MacroCompiler` is also given an `.mdf` file describing either the available vendor SRAM macros or the capabilities of the foundry's memory compiler. It matches the requested configurations against what is available and emits the technology-mapped Verilog — or, if no direct match exists, passes the request to the memory compiler itself to generate a new macro.

```text
Chisel SyncReadMem           FIRRTL ReplSeqMem          MacroCompiler
(abstract intent)   ─────►  (.conf: what is needed) ──► (maps to vendor SRAM or calls memory compiler)
```

Chisel does it at the language level; `ReplSeqMem` does it at the IR level; `MacroCompiler` does it at the physical level. The traditional memory compiler sits at the bottom of this stack, still responsible for generating actual GDS and netlists — but it is now invoked programmatically rather than by hand.

What remains unsettled is the interface. The `.conf` / `.mdf` format is UCB-specific and not an industry standard. As Chisel and `CIRCT` (the LLVM/MLIR-based `FIRRTL` compiler) gain adoption, this plumbing will need to standardize.

---


### Compute-In-Memory and the Storage/Compute Boundary {#compute-in-memory-and-the-storage-compute-boundary}

Throughout this article the memory macro has been pure storage: data in, data out, computation elsewhere. Compute-In-Memory (CIM) erases that separation.

The core idea is straightforward. In a standard read, a single `WL` is asserted and one row drives the bitlines. In analog CIM, _multiple WLs are asserted simultaneously_. Each active bitcell contributes a small current to the shared `BL` proportional to its stored bit. The total `BL` discharge becomes a current accumulation — a dot product, computed in the analog domain without ever moving data out of the array. An ADC at the column sense amp converts the result.

| Mode          | Operation                                                              |
|---------------|------------------------------------------------------------------------|
| Standard read | assert 1 `WL` → read 1 row                                             |
| Analog CIM    | assert \\(N\\) `WLs` → \\(I\_{BL} \propto \sum\_{i} w\_i \cdot x\_i\\) |

The column `BL` current accumulates a dot product in the analog domain:

\\[I\_{BL} \propto \sum\_{i=1}^{N} w\_i \cdot x\_i\\]

where \\(w\_i \in \\{0, 1\\}\\) is the stored bit in row \\(i\\) and \\(x\_i\\) is the input activation (encoded as `WL` drive strength).

The 6T cell's physics — the same physics that creates Read Disturbance and necessitates the Beta Ratio — becomes the compute primitive. The bitcell is not being repurposed; it is being used for something its physics already enables, just never intentionally.

Digital CIM (DCIM) takes a different path: it adds explicit logic gates alongside the bitcells so that computation is fully digital and deterministic, at the cost of area. Recent work (e.g., 12nm DCIM at 137 TOPS/W) fits this approach into foundry 8T bitcells, making it compatible with standard memory compiler flows.

Traditional memory compilers have a strict internal model: the array is storage, the periphery is control, and the two are generated separately. CIM breaks this model. The array now participates in computation; the sense amplifier periphery doubles as an ADC; power and timing budgets span both. A CIM-aware memory compiler cannot treat the array and its periphery as independent subsystems. Some researchers have noted that CIM macros are _amenable to automated design via memory compilers_, but what that actually requires — a compiler that co-generates storage geometry and compute periphery from a unified specification — does not yet exist in any standardized form.
