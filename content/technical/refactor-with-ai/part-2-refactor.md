+++
title = "Pinning Both Ends: Letting AI Rewrite 15k Lines of Test Tooling"
author = ["Yi-Ping Pan (Cloudlet)"]
description = "I pinned both ends of an old test generator, the parsed input and the golden output, and let the AI rewrite everything in between. The generator shrank from about 15,000 lines to about 3,500."
date = 2026-10-23
draft = false
[taxonomies]
  tags = ["python", "refactor", "ai", "refactor-with-ai", "tools", "testing"]
  categories = ["software-engineering"]
+++

Tool Y, an old test generator, shrank from about 15,000 lines to about 3,500 in
3.5 working days. Not one old golden file changed, except the ones the upstream
specification showed were wrong.

The method is the same as in [Part 1](@/technical/refactor-with-ai/part-1-deletion.md): pin both ends, then let the AI rewrite the
middle. The input end is the parsed data. The output end is the golden files,
byte for byte. The old tool itself was the check, and I read the AI's code after
every round.


## The problem {#the-problem}

Tool Y was one engineer's personal tool. It reads test specifications from
spreadsheets and writes golden files: generated test cases, kept as the
known-good set. Another flow, the downstream flow, runs those files as its
regression suite.

Nobody had maintained tool Y for a long time, so my manager asked me to take it
over. The first job was to upgrade it to a newer upstream specification version.
The upstream specification is an outside standard. It defines the element types
that every test case is built from.

Tool Y works, but nobody planned its structure. Every new need added a new
script, a new config, or a new copy of an old file. The tree, with names
changed:

<a id="org-example-block--tool-y-before-tree"></a>
```text
tool-y/
├── README.md                manual post-processing steps
├── config_main/             spreadsheets and JSON for the main CLI
│   ├── elements.xlsx
│   ├── sets.json            refers to spreadsheet row numbers
│   └── ...
├── gen/                     CLI entry point, plus a flag that acts as another
│   ├── main.py
│   ├── elements.py          one hand-written class per element type
│   ├── utils.py
│   └── golden_b.py          a second golden path
├── flow/                    mode dispatch, called back from gen/
├── post/                    4 scripts, chained through JSON files
├── config_b/
│   └── elements.xlsx        same file name as config_main/, different content
├── gen_b/                   generator B: its own entry point,
│   ├── main.py              and its own copies of elements.py and utils.py
│   ├── elements.py
│   └── utils.py
└── gen_c/                   generator C: reads a spreadsheet outside the repo
```

A test case can stand alone or combine several others. These are the modes.
Each target, one setup of the downstream flow, has its own generator.

What I found when I read the code:

-   **Copies that drifted.** Generator B started as a copy of the main helpers.
    Now the two differ by thousands of lines. A bug fix in one needs a manual
    check of the other.
-   **Generators that skip the main path.** Generators B and C never call the
    main generator, so a fix there does not reach them.
-   **Two golden paths.** The README names one command. A script makes golden
    files another way. From the code, I couldn't tell which one is current.
-   **Inputs outside git.** Generator B downloads its spreadsheets from a shared
    drive. Generator C reads a hard-coded path. A git tag alone can't rebuild
    their output.
-   **A manual release.** Four scripts pass data through JSON files, then a list
    of hand steps in the README.

The worst part was the spreadsheets themselves. Each specification version had
its own spreadsheet, and every element type had its own tab in it, far too
many to scroll through. The tabs sit along the bottom of the window. Scrolling right through the tabs, I could never reach the one I
wanted. Nobody could review a test case in there, let alone maintain one.

That scale also hides mistakes. Combined test cases point at spreadsheet rows
by number, and the tool checks only that the number is in range. So I tried
it. I inserted one valid row and ran the same command again. No warning. The
case had the same name, but the golden file was different.

The second problem was the generator itself. Every element type is a
hand-written class. The upstream specification already publishes
machine-readable definitions of its element types, but tool Y never reads
them. So a new specification version means editing the classes one by one,
by hand. And nothing checks that a class still matches the specification. The
upgrade I was asked to do was exactly this work.

<figure style="margin:2rem auto;max-width:480px">
<svg viewBox="0 0 400 480" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Before: a person reads the upstream specification and writes one class per element type, and nothing checks the classes. After: the generator and the validator both read the machine-readable definitions" style="width:100%;height:auto;color:inherit">
<defs>
<marker id="tyg-arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
<path d="M0,0L10,5L0,10z" fill="currentColor"/>
</marker>
<marker id="tyg-pin" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
<path d="M0,0L10,5L0,10z" fill="#d4688a"/>
</marker>
</defs>
<!-- Before -->
<text x="20" y="20" font-size="13" fill="currentColor" font-weight="600">Before</text>
<rect x="20" y="32" width="150" height="48" rx="8" fill="none" stroke="currentColor" stroke-width="1.6" stroke-dasharray="4 3"/>
<text x="95" y="52" text-anchor="middle" font-size="12" fill="currentColor">upstream</text>
<text x="95" y="68" text-anchor="middle" font-size="12" fill="currentColor">specification</text>
<line x1="170" y1="56" x2="228" y2="56" stroke="currentColor" stroke-width="1.5" marker-end="url(#tyg-arr)"/>
<rect x="230" y="32" width="150" height="48" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="305" y="52" text-anchor="middle" font-size="12" fill="currentColor">a person</text>
<text x="305" y="68" text-anchor="middle" font-size="12" fill="currentColor">reads it</text>
<line x1="305" y1="80" x2="305" y2="110" stroke="currentColor" stroke-width="1.5" marker-end="url(#tyg-arr)"/>
<!-- A stack of hand-written classes, no count shown -->
<rect x="246" y="128" width="134" height="48" rx="8" fill="none" stroke="currentColor" stroke-width="1.2" opacity="0.4"/>
<rect x="238" y="124" width="138" height="48" rx="8" fill="none" stroke="currentColor" stroke-width="1.3" opacity="0.65"/>
<rect x="230" y="120" width="142" height="48" rx="8" fill="currentColor" fill-opacity="0.04" stroke="currentColor" stroke-width="1.6"/>
<text x="301" y="140" text-anchor="middle" font-size="12" fill="currentColor">one class per</text>
<text x="301" y="156" text-anchor="middle" font-size="12" fill="currentColor">element type</text>
<text x="305" y="194" text-anchor="middle" font-size="11" fill="currentColor" opacity="0.7">written and edited by hand</text>
<line x1="230" y1="144" x2="172" y2="144" stroke="currentColor" stroke-width="1.5" marker-end="url(#tyg-arr)"/>
<rect x="20" y="120" width="150" height="48" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="95" y="148" text-anchor="middle" font-size="12" fill="currentColor">generator</text>
<text x="20" y="214" font-size="11" fill="currentColor" opacity="0.7">Nothing checks a class against the specification.</text>
<line x1="20" y1="230" x2="380" y2="230" stroke="currentColor" stroke-width="1" stroke-dasharray="2 4" opacity="0.5"/>
<!-- After -->
<text x="20" y="254" font-size="13" fill="currentColor" font-weight="600">After</text>
<rect x="20" y="266" width="360" height="48" rx="8" fill="none" stroke="currentColor" stroke-width="1.6" stroke-dasharray="4 3"/>
<text x="200" y="286" text-anchor="middle" font-size="12" fill="currentColor">machine-readable definitions</text>
<text x="200" y="302" text-anchor="middle" font-size="11" fill="currentColor" opacity="0.7">from the upstream specification</text>
<line x1="95" y1="314" x2="95" y2="346" stroke="currentColor" stroke-width="1.5" marker-end="url(#tyg-arr)"/>
<line x1="305" y1="314" x2="305" y2="346" stroke="#d4688a" stroke-width="2" marker-end="url(#tyg-pin)"/>
<rect x="20" y="348" width="150" height="58" rx="8" fill="none" stroke="currentColor" stroke-width="2"/>
<text x="95" y="370" text-anchor="middle" font-size="12" fill="currentColor" font-weight="600">generator</text>
<text x="95" y="386" text-anchor="middle" font-size="11" fill="currentColor" opacity="0.7">one generic path</text>
<text x="95" y="400" text-anchor="middle" font-size="11" fill="currentColor" opacity="0.7">+ a few handlers</text>
<rect x="230" y="348" width="150" height="58" rx="8" fill="none" stroke="#d4688a" stroke-width="2"/>
<text x="305" y="372" text-anchor="middle" font-size="12" fill="currentColor" font-weight="600">validator</text>
<text x="305" y="390" text-anchor="middle" font-size="11" fill="currentColor" opacity="0.7">checks every recipe</text>
<line x1="230" y1="377" x2="172" y2="377" stroke="currentColor" stroke-width="1.5" marker-end="url(#tyg-arr)"/>
<rect x="230" y="436" width="150" height="36" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="305" y="458" text-anchor="middle" font-size="12" fill="currentColor">recipes</text>
<line x1="305" y1="436" x2="305" y2="408" stroke="currentColor" stroke-width="1.5" marker-end="url(#tyg-arr)"/>
</svg>
<figcaption style="font-size:0.9rem;opacity:0.75;margin-top:0.6rem">Before: a person reads the upstream specification and writes one class per element type. Nothing checks the classes against it. After: the generator and the validator read the same machine-readable definitions, so a new specification version is a data change.</figcaption>
</figure>

Patching one script at a time would leave the next owner the same problem. So
I rewrote it, under three rules I couldn't break:

1.  **Old test cases stay the same, byte for byte.** The only exceptions are test
    cases that were already wrong.
2.  **Every output is valid input for the downstream flow.**
3.  **The downstream flow doesn't change.** Same files, same format, same place.

The goal: all inputs in git, one parser, one validator, and one generator
that reads the upstream specification's machine-readable definitions. Then a
new specification version is a data change, and a new test case is a recipe,
not code.


## How I did it {#how-i-did-it}

<figure style="margin:2rem 0">
<svg viewBox="0 0 720 330" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Old and new tool side by side: three old parsers feed tangled generators, the new tool has one parser, validator, and generator; parsed data and golden files must match at both ends" style="width:100%;height:auto;color:inherit">
<defs>
<marker id="tyh-arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
<path d="M0,0L10,5L0,10z" fill="currentColor"/>
</marker>
<marker id="tyh-pin" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
<path d="M0,0L10,5L0,10z" fill="#d4688a"/>
</marker>
</defs>
<!-- Old: three inputs, three parsers -->
<text x="20" y="24" font-size="12" fill="currentColor" font-weight="600">Old</text>
<rect x="20" y="40" width="120" height="40" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="80" y="64" text-anchor="middle" font-size="11" fill="currentColor">spreadsheets A</text>
<rect x="20" y="92" width="120" height="40" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="80" y="116" text-anchor="middle" font-size="11" fill="currentColor">spreadsheets B</text>
<rect x="20" y="144" width="120" height="40" rx="8" fill="none" stroke="currentColor" stroke-width="1.6" stroke-dasharray="4 3"/>
<text x="80" y="168" text-anchor="middle" font-size="11" fill="currentColor">spreadsheet C</text>
<line x1="140" y1="60" x2="178" y2="60" stroke="currentColor" stroke-width="1.5" marker-end="url(#tyh-arr)"/>
<line x1="140" y1="112" x2="178" y2="112" stroke="currentColor" stroke-width="1.5" marker-end="url(#tyh-arr)"/>
<line x1="140" y1="164" x2="178" y2="164" stroke="currentColor" stroke-width="1.5" marker-end="url(#tyh-arr)"/>
<rect x="180" y="40" width="100" height="40" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="230" y="64" text-anchor="middle" font-size="11" fill="currentColor">parser A</text>
<rect x="180" y="92" width="100" height="40" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="230" y="116" text-anchor="middle" font-size="11" fill="currentColor">parser B</text>
<rect x="180" y="144" width="100" height="40" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="230" y="168" text-anchor="middle" font-size="11" fill="currentColor">parser C</text>
<!-- Old: tangled generators -->
<path d="M280 60 C340 160 380 20 430 120 S 500 60 556 106" fill="none" stroke="currentColor" stroke-width="1.4" marker-end="url(#tyh-arr)"/>
<path d="M280 112 C330 40 400 190 450 70 S 520 150 556 112" fill="none" stroke="currentColor" stroke-width="1.4" marker-end="url(#tyh-arr)"/>
<path d="M280 164 C360 120 360 30 420 90 S 480 200 556 118" fill="none" stroke="currentColor" stroke-width="1.4" marker-end="url(#tyh-arr)"/>
<text x="420" y="206" text-anchor="middle" font-size="9.5" fill="currentColor" opacity="0.7">old generators</text>
<rect x="560" y="90" width="140" height="44" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="630" y="116" text-anchor="middle" font-size="11" fill="currentColor">golden files</text>
<!-- New row -->
<text x="20" y="244" font-size="12" fill="currentColor" font-weight="600">New</text>
<rect x="20" y="260" width="120" height="44" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="80" y="286" text-anchor="middle" font-size="11" fill="currentColor">recipes</text>
<line x1="140" y1="282" x2="178" y2="282" stroke="currentColor" stroke-width="1.5" marker-end="url(#tyh-arr)"/>
<rect x="180" y="260" width="100" height="44" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="230" y="286" text-anchor="middle" font-size="11" fill="currentColor">parser</text>
<line x1="280" y1="282" x2="318" y2="282" stroke="currentColor" stroke-width="1.5" marker-end="url(#tyh-arr)"/>
<rect x="320" y="260" width="90" height="44" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="365" y="286" text-anchor="middle" font-size="11" fill="currentColor">validator</text>
<line x1="410" y1="282" x2="428" y2="282" stroke="currentColor" stroke-width="1.5" marker-end="url(#tyh-arr)"/>
<rect x="430" y="260" width="90" height="44" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="475" y="286" text-anchor="middle" font-size="11" fill="currentColor">generator</text>
<line x1="520" y1="282" x2="558" y2="282" stroke="currentColor" stroke-width="1.5" marker-end="url(#tyh-arr)"/>
<rect x="560" y="260" width="140" height="44" rx="8" fill="none" stroke="currentColor" stroke-width="1.6"/>
<text x="630" y="286" text-anchor="middle" font-size="11" fill="currentColor">golden files</text>
<!-- The rewritten middle -->
<path d="M320 252 V246 H520 V252" fill="none" stroke="currentColor" stroke-width="1" opacity="0.6"/>
<text x="420" y="238" text-anchor="middle" font-size="9.5" fill="currentColor" opacity="0.7">rewritten freely</text>
<!-- The two pins -->
<rect x="174" y="34" width="112" height="156" rx="10" fill="none" stroke="#d4688a" stroke-width="1.5" stroke-dasharray="6 4"/>
<line x1="230" y1="192" x2="230" y2="258" stroke="#d4688a" stroke-width="3" stroke-dasharray="6 4" marker-start="url(#tyh-pin)" marker-end="url(#tyh-pin)"/>
<text x="240" y="228" font-size="11" fill="currentColor" font-weight="600">same parsed data</text>
<line x1="630" y1="136" x2="630" y2="258" stroke="#d4688a" stroke-width="3" stroke-dasharray="6 4" marker-start="url(#tyh-pin)" marker-end="url(#tyh-pin)"/>
<text x="622" y="200" text-anchor="end" font-size="11" fill="currentColor" font-weight="600">same bytes</text>
</svg>
<figcaption style="font-size:0.9rem;opacity:0.75;margin-top:0.6rem">Transforming tool Y. Three parsers and their tangled generators become one parser, one validator, and one generator. Both ends stay pinned: the same parsed data going in, the same golden files coming out.</figcaption>
</figure>


### Step 1: Lock the golden output {#step-1-lock-the-golden-output}

Before I touched any code, I ran the old tool once in every mode and kept the
output. These are the old golden files. The new tool has to reproduce them
byte for byte.

Generators B and C still read inputs from outside git. I ran them as they
were, then moved those inputs into git, so every later run starts from the
same files.

Then I wrote a small compare tool. It takes two output trees and reports every
file that differs, down to the field value. CI runs it on every change.


### Step 2: Pin the input end {#step-2-pin-the-input-end}

First, the spreadsheets needed a replacement. The recipe format had to be easy
to read for both a human and a parser, and keep the reason for a case next to
the case. And no new dependency just to read a config file. I looked at six:

| Format            | Comments | Clean git diff | Parser         | Catch                                 |
|:------------------|:--------:|:--------------:|:---------------|:--------------------------------------|
| Spreadsheet (old) | no       | no             | third-party    | binary file, references by row number |
| JSON              | no       | yes            | stdlib         | no comments, so no "why"              |
| YAML              | yes      | yes            | third-party    | guesses types, e.g. `1.10` → `1.1`    |
| Python as config  | yes      | yes            | it's code      | a recipe becomes a program            |
| Racket DSL        | yes      | yes            | easy to write  | few engineers read Racket             |
| TOML              | yes      | yes            | stdlib (3.11+) | deep nesting gets awkward             |

YAML reads `version: 1.10` as the number `1.1`. I don't want the format to
guess. I really wanted Racket, but the next owner would have to maintain my
interpreter. So I chose TOML: comments, explicit types, and a parser in the
Python standard library. A recipe is one TOML block per test case:

<a id="code-snippet--tool-y-recipe-example"></a>
```toml
# Recipes for upstream specification version "1.10".
spec_version = "1.10"  # a string, so it stays "1.10"

[[case]]
name = "case_001"
test_intent = "<one line: why this case exists>"
kind = "alpha"
mode = "A"
size = 4
strict = true
```

I had the AI write a one-time converter. Each spreadsheet row became a recipe,
and every reference by row number became a reference by name.

Then I had the AI write the input pin: parse the same test cases with the old
code and the new parser, and check that both give the same data. A small
adapter turns the new shape into the old one first. Once it passed, I deleted
the converter.

The validator defines valid input. It also checks each case against the
upstream's machine-readable definitions. That is the only check a new
specification version gets, because it has no old golden files. It shows the
case is legal. It does not show the case tests the right thing.

This check also found old bugs. Some old test cases failed the upstream
definitions. Copying them would only keep the bugs. So I fixed them or dropped
them, and took them out of the comparison.


### Step 3: Move one element type, then two, then batches {#step-3-move-one-element-type-then-two-then-batches}

I moved one element type first, to see whether the AI builds this structure:
`parser → validator → generator → golden files`. Then two. Then batches of 5,
then 10, until every element type had moved and every check was green.

The AI did get things wrong. But the check went red, and the AI fixed its own
work before it ever reached me. The pinned ends weren't only my safety net. They
were the AI's feedback loop.

After each round, I read the code by eye before I let the next round grow. I
also checked that the change touched none of the pins: the old golden files, the
compare tool, or the parse test. That review was the only guard. No tool stopped
the AI from editing the pins. Next time, I will make them read-only with chmod,
so an accidental edit fails. CI will also check their hashes against a list kept
outside the agent's workspace, because an agent with a shell can run chmod too.

The pins do not check design. For the first element type, I read the design and
decided where each part goes. I dictated the internal functions and the structs
by hand. I still don't have a good method for that. If anyone has one, <a
href="#contact">please let me know</a>.


### Step 4: Delete the old paths {#step-4-delete-the-old-paths}

Only after every mode matched byte for byte did I delete anything. The old
generators went, the second golden path went, and the spreadsheets went.

Then the scaffolding went too: the adapter and the migration tests. Same as
Part 1. If it stayed, it would test code that no longer exists. The validator
tests and the generator unit tests stay.


## Results {#results}

| What                             | Before  | After    |
|:---------------------------------|--------:|---------:|
| Generator code (lines)           | ~15,000 | ~3,500   |
| Time spent (working days)        | -       | 3.5      |
| Old golden files changed (bytes) | -       | 0\*      |
| Entry points                     | 4       | 1        |
| Inputs outside git               | 2       | 0        |
| Upstream versions                | 1       | multiple |

\*Every mode and every target, including generators B and C. Old test cases that
failed the upstream definitions were fixed or dropped, and left out of the
comparison.

The upgrade I was first asked to do is done, and the downstream flow uses its
output.

The AI did most of the typing again. The pins caught its mistakes, and I read
every round. Next time, the pins get a guard of their own.
