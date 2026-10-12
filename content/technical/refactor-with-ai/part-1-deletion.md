+++
title = "Deleting 19k Lines of Dead Compiler Code Without Trusting the LLM"
author = ["Yi-Ping Pan (Cloudlet)"]
description = "The AI colored the dependency graph, classified every node, and deleted most of the code. I reviewed every classification by hand. Every deletion step was small enough to review in one sitting."
date = 2026-10-16
draft = false
[taxonomies]
  tags = ["cpp", "refactor", "mlir", "compiler", "ai", "refactor-with-ai"]
  categories = ["software-engineering"]
+++

This is how I deleted ~19k lines of code in about a week. A month later: no
reverts, no fix-up commits.


## Why deletion gets skipped {#why-deletion-gets-skipped}

Code accumulates, and nobody removes it. A staff engineer at a previous job
advised me to leave coupled spaghetti alone, for two reasons. First, cleanup
didn't count as work: nobody saw it, and nobody rewarded it. Second, in his
experience these refactors ended in disaster, and someone eventually reverted
the code to where it started.

> If it works, don't touch it.

I disagree. Software follows the second law of thermodynamics: left alone, it
drifts toward disorder, and unless someone cleans it up, it becomes
unmaintainable. At that same company, I once spent 4 days working out what two
static linked lists did inside a member function full of side effects. A senior
engineer had named them `list1` and `list2`.

Module relationships need periodic redrawing: tangled code turned back into deep
modules, SICP's abstraction barriers kept intact. A barrier bounds what removing
a layer affects.

AI raises the cost of dead code. Tangled and retired code fills the context
window, and a model reads a retired pattern as a valid example and reproduces it
in new code. AI also lowers the cost of cleanup: understanding every dependency
before cutting, which used to take most of the effort, is now the part AI does
well.

My manager agreed. Once the successor flow had shipped and proved stable, he
assigned me to clean up the tech debt it left behind.


## The problem {#the-problem}

The retired flow, call it flow X, was controlled by a compiler option `--XYZ`.
Flow X was no longer on any default path, but its code was interleaved with
code still in production.

The task had two goals:

1.  **Complete removal.** No code, test, doc, or script for flow X or `--XYZ`
    remains.
2.  **No behavior change.** Every surviving flow produces the same output as it did
    before the removal.

The goals were clear, but the tech debt was too large for me to review alone. I
was new to this codebase, and cleaning it up by reading every dependency by hand
would have taken far longer than the time I had.


## Step 1: Defining the Scope {#step-1-defining-the-scope}

So the first question was not how to delete the code, but which code I had to
read at all. The codebase splits into two piles: code that depends on `--XYZ`,
which I must review, and everything else, which I can safely ignore. The work is
to draw that line precisely.

The starting point is where `--XYZ` is parsed and where it selects flow X. From
there, static analysis tools built on `compile_commands.json` trace every caller
and callee.

The LLM then marks each function it reaches with a comment, in one of two
colors:

-   RED: behavior depends on the flag's value
-   BLUE: prepares or forwards the flag's data

<!--listend-->

```cpp
// (unmarked) Produces options for every flag. Marking stops here.
Options parseCommandLine(int argc, char **argv);

// BLUE: forwards the flag's value into the pipeline config.
PipelineConfig buildConfig(const Options &opts) {
  PipelineConfig cfg;
  cfg.useFlowX = opts.xyz;
  return cfg;
}

// RED: the starting point. Behavior depends on the flag.
void buildPipeline(PassManager &pm, const PipelineConfig &cfg) {
  if (cfg.useFlowX)
    addFlowXPasses(pm);
  else
    addDefaultPasses(pm);
}

// RED: reached only through the flag's branch.
void addFlowXPasses(PassManager &pm);

// (unmarked) Belongs to the surviving path. Not affected.
void addDefaultPasses(PassManager &pm);
```

Propagation continues until nothing new gets marked.

The marking is checkable. Run a second call-graph tool from the same starting
point. If it reaches the same set of functions the marking colored, the marking
is complete for every edge the tool can see — no need to trust the AI.

One limit: MLIR registers passes and builds pipelines from strings, so the call
graph has dynamic edges clangd can't follow. "Nothing new gets marked" means
nothing new among the edges the tools can see.


## Step 2: Classify every node {#step-2-classify-every-node}

The scope told me where not to look. But the remaining code was still too large
to read line by line. Not every marked function, or node, carries the same risk.
So each node gets a category and a matching treatment. A deleted whole function
takes seconds to review. Other nodes need real surgery: remove the tumor without
damage to the healthy tissue around it. Some nodes need a bypass, so the blood
continues to flow to code another team owns while our code changes.

I defined four categories and asked the AI to put each node into one:

1.  **Mechanical deletion.** The whole function or block is unreachable once the
    flag is gone, and no live code depends on it. Remove it entirely.
2.  **Cross-ownership.** Another team owns the code, or the code is interleaved
    with code they own. Changes here need negotiation, and the other team might
    refuse them. I mark these for separate handling.
3.  **Side effects.** The code mutates shared state. A typical compiler example is
    a global stack added as a performance specialization. The marking assumes
    that data moves through parameters and return values. Side effects move data
    through channels that static analysis cannot follow. I handle these by hand.
4.  **Surgery.** The semantics may change, and the code is entangled with logic
    that stays. I separate it one piece at a time: excise what has to go, then
    suture the remaining code back together.

Classification is a narrow, repetitive judgment. A general-purpose LLM is more
than the job needs. A small classifier model such as TypeSafe Jev would likely
do it with far fewer tokens. I used the one LLM that my company approved.

Each node then carries its color and its category:

```cpp
// RED, MECHANICAL-DELETION: reached only through the flag's branch.
void addFlowXPasses(PassManager &pm);

// RED, SURGERY: keep the default branch, excise the flow X branch.
void buildPipeline(PassManager &pm, const PipelineConfig &cfg);
```

Manually checking one label on one node is a much smaller job than reviewing the
whole codebase. The AI mislabeled only a few nodes and each mistake was easy to
spot. The mistakes were all whole-file deletions that turned out to register a
pass. No C++ code called the file, so the call graph showed nothing alive. But
the file registered a pass under a string name, and a pipeline string or a
command line could still invoke that pass by name. Deleting the file changed an
interface, so it was not mechanical. The fix was always the same: move the node
to a riskier category. Every mislabel I found sent a node to riskier handling.


## Step 3: Scaffolding {#step-3-scaffolding}

Each goal needs a test that fails when the goal is not met.

Goal 1, complete removal, is the hard one. In my experience, an LLM told to
"remove this flag" misses sites. The test suite does not catch the misses,
because leftover dead code breaks nothing. It only confuses the next reader,
human or model. So someone has to write the missing check.

Goal 2, no behavior change, is what the existing regression tests already
protect. Surgery puts this goal at the most risk, so surgery gets the strictest
test.

Each category gets a test that matches its risk:

| Category        | Handling                        | Test                                                   |
|-----------------|---------------------------------|--------------------------------------------------------|
| Mechanical      | Remove entirely                 | Deletion test: fails before removal, passes after      |
| Cross-ownership | Adapter Pattern at the boundary | Interface tests on the adapter                         |
| Side effects    | Handled by hand                 | Reviewed and tested one by one                         |
| Surgery         | Excise and suture               | Surgical functional test: behavior identical to before |

**The deletion test checks goal 1.** It asserts that the removed thing is gone.
The retired option is rejected, and the old artifacts are no longer produced. I
write this test first. It fails before the deletion and passes after. A
forgotten site keeps its test red.

**The surgical functional test checks goal 2.** For every site that the excision
touched, the observable behavior after the change must match the behavior
before it. Where a unit test cannot isolate the site, regression tests on real
inputs cover it. There are enough of them to exercise each path through the
site.

Most of these tests are scaffolding. They check internal details, such as the
absence of an internal symbol. Those details stop existing once the work is
done. Like scaffolding on a building, these tests are removed when the work is
finished. If they stayed in the repo, they would test code that no longer
exists.


## Step 4: True deletion and surgery {#step-4-true-deletion-and-surgery}

The AI performs the edits, category by category, over several rounds. A subagent
reviews each round first. Then I review it. This phase has one goal: remove flow
X and keep every surviving behavior correct.

Code quality is out of scope here. Redundant design and shallow modules stay as
they are for now. The next phase fixes them.


## Step 5: Post-op cleanup {#step-5-post-op-cleanup}

Steps 1–4 left code shaped around modes that no longer exist. Interfaces still
wrap logic that now has one caller. Types still encode a choice that nobody
makes. So this step asks one question of every remaining piece: is this still a
deep module?

One hard rule bounds the work: I only touch code that steps 1–4 already touched.
This is cleanup of the surgical site, not a rewrite. The scope from step 1
bounds this step too.

Typical findings:

-   **Scattered shared state.** Three functions all read and write the same handful
    of variables. I bundle them into one struct passed in and one struct returned.
-   **Types with only one case left.** A `std::variant` now has a single
    alternative, or a `std::expected` has an error path that only the retired mode
    used. I collapse them to plain types, after I confirm that the error path
    really is unreachable.
-   **Routing with one route left.** Dispatch logic used to choose between modes.
    With one mode left, it reduces to a direct call.

The tests from step 3 continue to guard this step.

For example, after step 4 removed flow X, the pipeline code still looked like
this:

```cpp
// After step 4: correct, but still shaped for two modes.
enum class PipelineMode { Default };  // FlowX was removed in step 4.

struct PipelineConfig {
  PipelineMode mode = PipelineMode::Default;
};

std::expected<void, std::string>
buildPipeline(PassManager &pm, const PipelineConfig &cfg) {
  switch (cfg.mode) {
  case PipelineMode::Default:
    addDefaultPasses(pm);
    return {};
  }
  return std::unexpected("unknown pipeline mode");  // Unreachable now.
}
```

The enum has one value, the switch has one case, and the error path can no
longer fire. Every caller still checks a result that cannot fail. After step 5:

```cpp
// After step 5: one mode, one path, no choice left to encode.
void buildPipeline(PassManager &pm) { addDefaultPasses(pm); }
```

The enum, the config field, the switch, and the error handling at every call
site are gone. The interface now says what the function does.


## Results {#results}

In about a week, the compiler lost ~19k lines of code and over 50 MB of binary
size. A month later, there were no reverts and no fix-up commits for this
change. Careful review covered only about 12% of the deleted lines. The
classification told me which 12%.

| What                              | Value             |
|-----------------------------------|-------------------|
| Compiler binary size              | -50+ MB           |
| Code lines deleted / added        | ~19k / ~130       |
| Test lines deleted / added        | ~1.5k / &lt;10    |
| Doc lines deleted / added         | ~1.9k / &lt;10    |
| Whole code files deleted          | ~30 (~17k lines)  |
| Code files modified               | ~35 (~2.3k lines) |
| Flag-name occurrences outside C++ | 13                |
| Reverts or fix-up commits since   | 0                 |

The classification decided where my review time went. Most of the deleted code
was in whole files, and I reviewed those files by their file list. Before I
deleted a whole file, I grepped it for pass registrations and pipeline names.
Any hit moved the file out of the mechanical category. I read the ~35 modified
files line by line. These files hold about 12% of what was deleted.

The commit history follows the steps. An illustrative version, oldest first:

```text
a1c3e09 Add REFACTOR(retire-xyz) annotations: scope and categories
4f7b2d1 Add deletion tests for --XYZ (expected to fail)
9e0a6c3 Add surgical functional tests for buildPipeline
c28d5f4 Remove flow X pass files (mechanical)
7b19e8a Remove flow X helpers in Conversion/ (mechanical)
e5402bb Remove --XYZ from lit RUN lines and scripts (mechanical)
3d8f1a7 Excise flow X branch from buildPipeline (surgery)
b60c4e2 Move global pass stack out of flow X path (side effects)
0f9a7d5 Reject retired option --XYZ with a clear error
8a2e3c6 Collapse single-mode PipelineConfig into direct call (cleanup)
d47b9f0 Remove std::expected from buildPipeline (cleanup)
61e0c8b Remove scaffolding tests and REFACTOR annotations
```

Each commit belongs to one category and is small enough to review in one
sitting. Whole-file deletions were reviewed by file list.


## Takeaway {#takeaway}

The AI did most of the work, and I trusted none of it. These two facts do not
conflict. Every change site got a verifier before anyone touched it: a color, a
category, and a test. My job was to check each verifier, not to do the work
again.


## Next {#next}

This post covered deletion. The next post covers replacement: the rewrite of an
outdated tool. That job had no single map to draw. It was a chain of small
steps. Each step was small enough that a problem was easy to see.
