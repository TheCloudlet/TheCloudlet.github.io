+++
title = "Emacs Internal #04: Interval Trees — Balancing by Text Length, Not Node Count"
author = ["Yi-Ping Pan (Cloudlet)"]
description = "Why Emacs balances its property tree by total character count instead of node depth—a weight-balanced design that yields to the physical reality of text editing."
date = 2026-05-14
aliases = ["/blog/project/emacs-04/"]
draft = false
[taxonomies]
  tags = ["lisp-string", "interval-tree", "text-properties", "memory-layout"]
  categories = ["systems-programming"]
[extra]
  math = true
  math_auto_render = true
+++

It has been a while since my last update. Recently, I lost my job and stepped into the undefined space of looking for the next one. I didn't expect the friction of this state change to be so mentally taxing, but I'll try to [keep the blue side up](https://www.urbandictionary.com/define.php?term=Keep+the+blue+side+up%21)—observing the turbulence without fighting it too hard.

I had actually planned to write about Emacs' Interval Trees a couple of months ago. But I found my mental bandwidth caught in a bit of a loop: I realized my knowledge was limited, and I was uncomfortable with the idea of publishing something unless I was absolutely certain it was the flawless truth. So I kept studying more, burning cycles just to force a sense of perfect mastery.

At some point, I realized that this need for absolute certainty was just another exhausting compensation mechanism. So, I decided to just yield. I'll simply share what I've observed in the codebase, along with my personal speculations and guesses. I might be entirely wrong about some of the "whys", so please don't hesitate to correct my illusions by sending an email or filing a GitHub issue.


## 1. A Hidden Field in Lisp_String {#1-dot-a-hidden-field-in-lisp-string}

It all started from discovering something unnatural in how the string is implemented in Emacs Lisp (`Lisp_String`). There is an `INTERVAL` field inside `Lisp_String`.

In most programming languages, a primitive string is strictly a contiguous stream of bytes accompanied by its length. However, the definition of `struct Lisp_String` in `src/lisp.h` explicitly embeds an `INTERVAL` pointer alongside the standard byte arrays (`data`, `size`, and `size_byte`).

The definition of `struct Lisp_String` in `src/lisp.h`.

```c
// Source: src/lisp.h
struct Lisp_String
{
  union
  {
    struct
    {
      /* Number of characters in string; MSB is used as the mark bit.  */
      ptrdiff_t size;
      /* If nonnegative, number of bytes in the string (which is multibyte).
         If negative, the string is unibyte:
         -1 for data normally allocated
         -2 for data in rodata (C string constants)
         -3 for data that must be immovable (used for bytecode)  */
      ptrdiff_t size_byte;

      INTERVAL intervals;  /* Text properties in this string.  */
      /* The data is always followed by a NUL, not included in size or
         size_byte, for C interoperability, but may also contain NULs
         itself.  */
      unsigned char *data;
    } s;
    struct Lisp_String *next;
    GCALIGNED_UNION_MEMBER
  } u;
};
static_assert (GCALIGNED (struct Lisp_String));
```

This `INTERVAL` field points to a tree structure that maps metadata—such as font size, weight, colors, or custom Lisp objects—directly to specific index ranges within the text.

My speculation is that, because Emacs Lisp evolved specifically to serve as the runtime for a text editor, separating the raw characters from their visual properties would create an unnecessary disconnect. If a `Lisp_String` is passed around through various functions, and the rendering metadata is stored in some external hash table or array, the system would constantly have to pay for keeping those two states synchronized.

I guess the developers realized that enforcing strict boundaries between "data" and "presentation" here would just introduce friction. By embedding the `INTERVAL` tree directly inside the primitive string struct, the text and its formatting become a single, self-contained entity. It yields to the reality of text editing: the system isn't just passing abstract bytes around; it is moving physical text that inherently remembers its own shape and color.


### 1.1 The Interval Struct {#1-dot-1-the-interval-struct}

```c
// Source: src/intervals.h
struct interval
{
  /* The first group of entries deal with the tree structure.  */
  ptrdiff_t total_length;       /* Length of myself and both children.  */
  ptrdiff_t position;           /* Cache of interval's character position.  */
                                /* This field is valid in the final
                                   target interval returned by
                                   find_interval, next_interval,
                                   previous_interval and
                                   update_interval.  It cannot be
                                   depended upon in any intermediate
                                   intervals traversed by these
                                   functions, or any other
                                   interval. */
  struct interval *left;        /* Intervals which precede me.  */
  struct interval *right;       /* Intervals which succeed me.  */

  /* Parent in the tree, or the Lisp_Object containing this interval tree.  */
  union
  {
    struct interval *interval;
    Lisp_Object obj;
  } up;
  bool_bf up_obj : 1;

  bool_bf gcmarkbit : 1;

  /* The remaining components are `properties' of the interval.
     The first four are duplicates for things which can be on the list,
     for purposes of speed.  */

  bool_bf write_protect : 1;  /* True means can't modify.  */
  bool_bf visible : 1;        /* False means don't display.  */
  bool_bf front_sticky : 1;   /* True means text inserted just
                                 before this interval goes into it.  */
  bool_bf rear_sticky : 1;    /* Likewise for just after it.  */
  Lisp_Object plist;          /* Other properties.  */
};
```


### 1.2 High Coupling by Design {#1-dot-2-high-coupling-by-design}

The interval structure is a pervasive data structure within the Emacs C architecture. A review of the source code reveals its primary consumers:

-   **`xdisp.c` (~70 places)**: The display engine. It queries the tree during redisplay to determine each character's face, display, invisible, fontified, or cursor properties. It is the primary consumer.

-   **`textprop.c` (~25 places)**: The C implementation of Elisp-level APIs such as `get-text-property`, `put-text-property`, and `add-text-properties`.

-   **`editfns.c` (~17 places)**: Handles point movement and queries property change boundaries.

-   **`insdel.c` (~12 places)**: Maintains the tree structure during buffer modifications by calling functions like `adjust_intervals_for_insertion` and `offset_intervals`.

-   **`keyboard.c` (~6 places)**: Checks for keymap text properties at the point, enabling links and buttons to have custom keyboard behaviors.

-   **`indent.c`, `syntax.c`, `xfaces.c`**: Utilizes the tree for calculating column widths, checking syntax tables, and parsing faces.

-   **`alloc.c`**: The Garbage Collector. Traverses the tree to mark and sweep interval nodes.

Looking at this distribution, my personal speculation is that it reveals something interesting about Emacs' design philosophy. In modern software architecture, there is often a strong urge to build strict boundaries—to completely decouple the display engine (`xdisp.c`) from the garbage collector (`alloc.c`) or the input handler (`keyboard.c`).

But instead of forcing layers of abstraction to keep everything perfectly isolated, it seems the developers just yielded to the physical reality of a text editor: the characters, their visual representation, and their interactive behaviors are inextricably bound together. I suspect they realized that fighting this reality by creating separate, synchronized subsystems would just tax the CPU unnecessarily. So, they simply let this single `INTERVAL` tree quietly permeate the entire runtime. It feels less like a rigidly decoupled architecture and more like organic tissue. I might be entirely wrong, but at least, that's my interpretation when reading these access patterns.


## 2. The Problem with Absolute Coordinates {#2-dot-the-problem-with-absolute-coordinates}

When I encounter the term **interval tree**, my instinct is to default to traditional implementations that store absolute `[begin, end)` ranges. The Linux kernel, for instance, implements interval trees ([`struct interval_tree_node`](https://github.com/torvalds/linux/blob/master/include/linux/interval_tree.h)) on top of red-black trees, and LLVM uses a highly optimized B+-tree-like interval map ([`llvm::IntervalMap`](https://github.com/llvm/llvm-project/blob/main/llvm/include/llvm/ADT/IntervalMap.h)) to track variable _live-ranges_ during register allocation. In these classical architectures, the structure is built to efficiently query overlapping intervals.

While both store intervals, the Linux structure optimizes for overlap detection across many intervals, while Emacs needs a point lookup at a single character position. This query difference, as much as the coordinate choice, shapes the design.

However, the Emacs `Lisp_String` saves the length instead of absolute coordinates.

Consider a string with three distinct text properties: "Hello, world!". The segment "Hello, " is red, "world" is green, and "!" is blue and bold.

If these properties were saved in a flat, indexed array, the memory layout would be:

```text
// Example: Properties saved in a flat indexed array

Text:      "H e l l o , W o r l d  !"
Position:  0 1 2 3 4 5 6 7 8 9 10 11
Color:     R R R R R R G G G G G  B
Bold:      0 0 0 0 0 0 0 0 0 0 0  1
```

Storing metadata for every single character is highly inefficient. A more compact representation utilizes `[start, end)` intervals:

```text
// Example: Compact representation using absolute intervals

[0, 6)   Color R
[6, 11)  Color G
[11, 12) Color B
[11, 12) Weight Bold
```

This reduces the memory footprint and enables the attachment of custom properties.

Editing the string, however, invalidates subsequent absolute intervals. If a single character is inserted into the buffer, every `[start, end)` interval positioned after the insertion point must be recalculated and updated. In a text editor, where typing happens continuously, this \\(O(N)\\) shifting operation creates unacceptable latency.

```text
// Problem: Adding '&' requires updating all subsequent absolute intervals

Text:      "H e l l o , & W o r l d !"

[0, 6)           Color R     (Unchanged)
[6 + 1, 11 + 1)  Color G     (Start and end shifted)
[11 + 1, 12 + 1) Color B     (Start and end shifted)
[11 + 1, 12 + 1) Weight Bold (Start and end shifted)
```


## 3. The Emacs Solution {#3-dot-the-emacs-solution}

Emacs circumvents this \\(O(N)\\) penalty by storing relative lengths within the tree structure instead of absolute boundaries.

> Instead of saving absolute start and end positions, what if we only save the length of each interval segment?

```text
// Emacs: Relative length representation

Text:      "H e l l o , W o r l d !"
           |1----------|2--------|3|

Interval 1: Length 6 - (Color R)
Interval 2: Length 5 - (Color G)
Interval 3: Length 1 - (Color B) + (Weight Bold)
```

Inserting a '&amp;' into the green section only requires incrementing the length of Interval 2. The absolute positions of all subsequent intervals are implicitly shifted without any explicit updates to their nodes. This structural design amortizes to \\(O(\log W)\\) updates (where \\(W\\) is the total text length in characters, distinct from \\(N\\) used later for node count; §5 examines when this breaks down).

When I finally grasped this, it actually shifted my perspective a bit. Maintaining absolute coordinates is essentially an exhausting attempt to exert rigid, global control over a system. Every time a tiny, localized change happens, the system pays for updating the entire map just to maintain the appearance of absolute correctness.

My speculation is that the developers chose relative lengths because it simply yields to the physical reality of a text buffer. It doesn't fight the continuous, localized nature of human typing. When typing in the middle of a colored word in Emacs, the color is automatically inherited because the physical gap of that specific node is simply expanded. The architecture doesn't panic and defensively shift thousands of downstream pointers; it just quietly lets the node absorb the new input. It feels like a profoundly relaxed way to manage state.

This leads to the following structure:

```text
             ┌─────────────────────┐
             │ Interval 2 (root)   │
             │ total_length = 13   │
             │ LENGTH = 5          │  ← "world"
             │ plist = green       │
             └─────┬─────────┬─────┘
                   │         │
                 (left)    (right)
                   ▼         ▼
┌─────────────────────┐   ┌─────────────────────┐
│ Interval 1          │   │ Interval 3          │
│ total_length = 7    │   │ total_length = 1    │
│ LENGTH = 7          │   │ LENGTH = 1          │
│ plist = red         │   │ plist = blue+bold   │
└─────┬─────────┬─────┘   └─────┬─────────┬─────┘
      │         │               │         │
    (left)    (right)         (left)    (right)
      ▼         ▼               ▼         ▼
    NULL       NULL           NULL       NULL
  ("Hello, ")                      ("!")
```


## 4. Observing the Tree {#4-dot-observing-the-tree}

This behavior can be observed by evaluating the following block in the `*scratch*` buffer:

_(Please jump to if you need a guide on how to compile a debug build of Emacs.)_

```lisp
;; 1. Evaluate this block (C-x C-e at the end)
(progn
  (setq my-str (copy-sequence "Hello, world!"))

  (put-text-property 0 7 'font-lock-face '(:foreground "red") my-str)
  (put-text-property 7 12 'font-lock-face '(:foreground "green") my-str)
  (put-text-property 12 13 'font-lock-face '(:foreground "blue" :weight bold) my-str)

  (insert "\n" my-str))

;; 2. Attach a debugger (LLDB/GDB) to the Emacs process.
;;    (The detailed setup is in the appendix)
;; 3. Set a breakpoint on the C function `Fobject_intervals`.
;; 4. Evaluate the line below (C-x C-e) to trigger the breakpoint.
(object-intervals my-str)
```

Output:

The `my-str` structure:

```text
(lldb) expr struct Lisp_String *$my_str = (struct Lisp_String *) XSTRING(object)
(lldb) p *$my_str
(struct Lisp_String) {
  u = {
    s = {
      size = 13
      size_byte = -1
      intervals = 0x0000000b93298780
      data = 0x0000000b92dcff08 "Hello, world!"
    }
    next = 0x000000000000000d
    gcaligned = '\r'
  }
}
```

Checking the intervals:

```text
(lldb) p *intervals
(interval) {
  total_length = 13  // <-- Correct
  position = 0
  left = NULL
  right = 0x0000000b93298748
  up = {
    interval = 0x0000000b932539e4
    obj = (i = 0x0000000b932539e4)
  }
  up_obj = true
  gcmarkbit = false
  write_protect = false
  visible = false
  front_sticky = false
  rear_sticky = false
  plist = (i = 0x0000000b928c71f3)
}

(lldb) p *intervals->right
(interval) {
  total_length = 6
  position = 7
  left = NULL
  right = 0x0000000b932987b8
  up = {
    interval = 0x0000000b93298780
    obj = (i = 0x0000000b93298780)
  }
  up_obj = false
  gcmarkbit = false
  write_protect = false
  visible = false
  front_sticky = false
  rear_sticky = false
  plist = (i = 0x0000000b928c71d3)
}

(lldb) p *intervals->right->right
(interval) {
  total_length = 1
  position = 12
  left = NULL
  right = NULL
  up = {
    interval = 0x0000000b93298748
    obj = (i = 0x0000000b93298748)
  }
  up_obj = false
  gcmarkbit = false
  write_protect = false
  visible = false
  front_sticky = false
  rear_sticky = false
  plist = (i = 0x0000000b928c71b3)
}
```

Calling `(lldb) expr debug_print(XXX)` safely extracts `Lisp_Object~s, and the information is printed in the ~src/emacs` buffer:

```text
(lldb) expression -- debug_print(intervals->up.obj)
emacs > #("Hello, world!" 0 7 (font-lock-face (:foreground "red")) 7 12 (font-lock-face (:foreground "green")) 12 13 (font-lock-face (:foreground "blue" :weight bold)))

(lldb) expression --  debug_print(intervals->plist)
emacs > (font-lock-face (:foreground "red"))

(lldb) expression --  debug_print(intervals->right->plist)
emacs > (font-lock-face (:foreground "green"))

(lldb) expression --  debug_print(intervals->right->right->plist)
emacs > (font-lock-face (:foreground "blue" :weight bold))
```

The debugger output reveals a deviation from classical expectations. The actual tree structure is not strictly balanced:

```text
// Diagram: Expected Balanced Tree (Initial Assumption)

               ┌─────────────────────┐
               │ Interval 2 (root)   │
               │ total_length = 13   │
               │ LENGTH = 5          │  ← "world"
               │ plist = green       │
               └─────┬─────────┬─────┘
                     │         │
                   (left)    (right)
                     ▼         ▼
  ┌─────────────────────┐   ┌─────────────────────┐
  │ Interval 1          │   │ Interval 3          │
  │ total_length = 7    │   │ total_length = 1    │
  │ LENGTH = 7          │   │ LENGTH = 1          │
  │ plist = red         │   │ plist = blue+bold   │
  └─────┬─────────┬─────┘   └─────┬─────────┬─────┘
        │         │               │         │
      (left)    (right)         (left)    (right)
        ▼         ▼               ▼         ▼
      NULL       NULL           NULL       NULL
    ("Hello, ")                      ("!")
```

Instead, it is skewed to the right:

```text
// Diagram: Skewed Interval Tree (Hello, world! testcase)

  ┌─────────────────────┐
  │ Interval 1 (root)   │
  │ total_length = 13   │
  │ LENGTH = 7          │  ← "Hello, "
  │ plist = red         │
  └─────┬─────────┬─────┘
        │         │
      (left)    (right)
        ▼         ▼
      NULL      ┌─────────────────────┐
                │ Interval 2          │
                │ total_length = 6    │
                │ LENGTH = 5          │  ← "world"
                │ plist = green       │
                └─────┬─────────┬─────┘
                      │         │
                    (left)    (right)
                      ▼         ▼
                    NULL      ┌─────────────────────┐
                              │ Interval 3          │
                              │ total_length = 1    │
                              │ LENGTH = 1          │  ← "!"
                              │ plist = blue+bold   │
                              └─────┬─────────┬─────┘
                                    │         │
                                  (left)    (right)
                                    ▼         ▼
                                  NULL       NULL
```

To understand more about the rebalance mechanism, I read the source code defined in `src/intervals.c`.

```c
// Source: src/intervals.c
/* Balance an interval tree with the assumption that the subtrees
   themselves are already balanced.  */

static INTERVAL
balance_an_interval (INTERVAL i)
{
  register ptrdiff_t old_diff, new_diff;

  eassert (LENGTH (i) > 0);
  eassert (TOTAL_LENGTH (i) >= LENGTH (i));

  while (1)
    {
      old_diff = LEFT_TOTAL_LENGTH (i) - RIGHT_TOTAL_LENGTH (i);
      if (old_diff > 0)
        {
          /* Since the left child is longer, there must be one.  */
          new_diff = i->total_length - i->left->total_length
            + RIGHT_TOTAL_LENGTH (i->left) - LEFT_TOTAL_LENGTH (i->left);
          if (eabs (new_diff) >= old_diff)
            break;  /* Abort if text-weight balance does not strictly improve */
          i = rotate_right (i);
          balance_an_interval (i->right);
        }
      else if (old_diff < 0)
        {
          /* Since the right child is longer, there must be one.  */
          new_diff = i->total_length - i->right->total_length
            + LEFT_TOTAL_LENGTH (i->right) - RIGHT_TOTAL_LENGTH (i->right);
          if (eabs (new_diff) >= -old_diff)
            break;  /* Abort if text-weight balance does not strictly improve */
          i = rotate_left (i);
          balance_an_interval (i->left);
        }
      else
        break;
    }
  return i;
}
```

The `balance_an_interval` function explains the right-skewed behavior. Emacs utilizes a unique definition of "balance":

1.  **Weight by Text Length, not Node Depth**: Unlike traditional AVL or Red-Black trees that calculate balance factors based on tree height or node count, Emacs evaluates text length (`total_length`). The difference is calculated as: `diff = LEFT_TOTAL_LENGTH(i) - RIGHT_TOTAL_LENGTH(i)`.
2.  **Length-Driven Rotation**: When modified, the system checks if one subtree covers significantly more text characters than the other. If so, it evaluates a potential AVL-like rotation (`rotate_left` or `rotate_right`).
3.  **The Abort Condition**: The rotation is executed only if it strictly improves the text-length balance. If a simulated rotation results in a worse or equal difference (`eabs(new_diff) >= eabs(old_diff)`), the process immediately aborts.

Calculating the balance for the test case (`"Hello, "` = 7, `"world"` = 5, `"!"` = 1):

If the tree remains **right-skewed** (the actual state):

-   Root (`"Hello,"`): Left text length = `0`, Right text length = `5 + 1 = 6`.
-   Absolute difference = `|0 - 6| = 6`.

If the tree were rotated into a strictly **node-balanced** shape:

-   Root (`"world"`): Left text length = `7`, Right text length = `1`.
-   Absolute difference = `|7 - 1| = 6`.

Because `|new_diff| >= |old_diff|` (`6 >= 6`), the rotation condition fails. The heuristic aborts, leaving the tree in its right-skewed state.

Watching the system deliberately skip this rotation was an interesting moment of reflection. My instinct as an engineer is usually to force a clean, symmetrical structure. But the code explicitly dictates that if a structural change doesn't yield a tangible reduction in text-weight imbalance, it just stops. It refuses to burn CPU cycles purely for the sake of aesthetic perfection.

To verify this logic, a second test case with much larger string lengths can be used to intentionally trigger the rebalancing mechanism:

```lisp
(progn
  (setq my-str-2 (copy-sequence (make-string 100 ?x)))   ; 100 'x's

  (put-text-property 0 50 'font-lock-face '(:foreground "red") my-str)
  (put-text-property 50 99 'font-lock-face '(:foreground "green") my-str)
  (put-text-property 99 100 'font-lock-face '(:foreground "blue") my-str)

  (insert "\n" my-str))

(object-intervals my-str)
```

The interval tree is now successfully balanced!

```text
// Diagram: Balanced Interval Tree (100 'x's testcase)

               ┌─────────────────────┐
               │ Interval 2 (root)   │
               │ total_length = 100  │
               │ LENGTH = 49         │  ← 49 'x's
               │ plist = green       │
               └─────┬─────────┬─────┘
                     │         │
                   (left)    (right)
                     ▼         ▼
  ┌─────────────────────┐   ┌─────────────────────┐
  │ Interval 1          │   │ Interval 3          │
  │ total_length = 50   │   │ total_length = 1    │
  │ LENGTH = 50         │   │ LENGTH = 1          │
  │ plist = red         │   │ plist = blue        │
  └─────┬─────────┬─────┘   └─────┬─────────┬─────┘
        │         │               │         │
      (left)    (right)         (left)    (right)
        ▼         ▼               ▼         ▼
      NULL       NULL           NULL       NULL
     (50 'x's)                       (1 'x')
```

Calculating the balance for this augmented test case:

If it had remained **right-skewed**:

-   Root (`red` interval): Left text length = `0`, Right text length = `49 + 1 = 50`.
-   Absolute difference = `|0 - 50| = 50`.

If it performs a left rotation to become **node-balanced**:

-   Root (`green` interval): Left text length = `50` (`red`), Right text length = `1` (`blue`).
-   Absolute difference = `|50 - 1| = 49`.

Because `|new_diff| < |old_diff|` (`49 < 50`), the rotation actively improves the text-weight balance. The heuristic detects this optimization and executes the rotation.


## 5. Weight-Balanced vs. Depth-Balanced {#5-dot-weight-balanced-vs-dot-depth-balanced}

If Emacs' balancing heuristic is based purely on text length, does it have a flaw?

Consider an extreme edge case: there is one massive property interval covering `[1, 1000)`, followed by a hundred tiny intervals like `[1000, 1001)`, `[1001, 1002)`, and so on to `[1099, 1100)`. Because the left side holds 1,000 characters and the right side holds 100 characters (distributed among 100 nodes), Emacs will see the text "weight" as relatively balanced and refuse to rotate. The tree will degenerate into a deeply skewed linked list on the right side!

I try to answer this question by reading some papers on related topics. Please correct me if I'm wrong.


### 5.1 The Coordinate Problem: Searching by Node vs. Searching by Index {#5-dot-1-the-coordinate-problem-searching-by-node-vs-dot-searching-by-index}

A tree must be balanced by its search unit.

When a generic, node-count-balanced Red-Black tree is used as a keyed associative container (think `std::map<int, T>` looking up by integer key), the system searches for a specific key. Because depth-balancing ensures the left and right subtrees have roughly the same number of nodes, stepping left mathematically guarantees eliminating exactly half of the remaining nodes.

A text rendering engine, however, queries by index (e.g., character 15,000).

If such an unaugmented, node-balanced tree has 1,000 nodes, stepping left eliminates 500 nodes. But if those 500 nodes on the left only contain 1 character each, while the remaining 500 nodes on the right contain 100,000 characters, half the nodes are eliminated, but almost zero progress is made in cutting down the text length. The query cost is misaligned with the search unit: the tree was balanced for node count, but the query is by character position.

In a text editor, "text length" is the physical spatial coordinate. By ensuring the `total_length` of the left and right subtrees are roughly equal (a concept rooted in Nievergelt and Reingold's 1973 BB[α] trees&nbsp;[^fn:1] and later popularized by the Rope data structure&nbsp;[^fn:2]), Emacs guarantees that every time it steps left or right, it eliminates half of the remaining text length. This relative, length-based navigation achieves optimal \\(O(\log W)\\) traversal speed (where \\(W\\) is the total text weight), regardless of how wildly disproportionate the metadata nodes are.


### 5.2 Amortized Cost and Lazy Rebalancing {#5-dot-2-amortized-cost-and-lazy-rebalancing}

This raises an obvious architectural question: _why not just deploy an augmented Red-Black tree that caches subtree weights in each node?_

An augmented RB tree handles position lookups in \\(O(\log N)\\) perfectly—it solves exactly the query-cost misalignment described above. But it demands a heavy price: structural perfection at all times. It pays a strict invariant cost on every single insertion and deletion. To me, that feels like an exhausting systemic loop—spending CPU budget just to maintain the appearance of flawless balance, even when it isn't strictly necessary for the immediate task.

Emacs's weight-balanced tree, on the other hand, consciously relaxes. It accepts imbalance as a feature, not a bug. As Sleator and Tarjan demonstrated with Self-Adjusting Binary Search Trees&nbsp;[^fn:3], amortized, lazy rebalancing can match the asymptotic performance of eager rebalancing by fundamentally reframing what 'balanced' actually means.

Forcing a tree rotation on every single keystroke is a non-trivial cost that Emacs deliberately avoids. My speculation is that Emacs chooses to rotate only when doing so actively relieves pressure (when it strictly improves the text-weight balance). For the rest, it just lets the imbalance amortize. It is a design that stops fighting the chaos of text editing and simply accommodates it.

And there is a safety net the online heuristic does not have to provide: every garbage collection cycle, `balance_intervals` runs a full post-order rebalance over every live string and buffer (`src/alloc.c`). Whatever imbalance the lazy path tolerated between collections gets swept clean. The online walk stays cheap; the worst-case skewed tree lives at most one GC cycle.


### 5.3 Interval Tree and Gap Buffer Synergy {#5-dot-3-interval-tree-and-gap-buffer-synergy}

The Interval Tree design must be considered alongside Emacs' core text storage mechanism: the Gap Buffer.

A gap buffer is a dynamic array designed to allow highly efficient insertion and deletion operations clustered near a specific location. Unlike a standard array where reserved empty space is kept at the very end, a gap buffer places its unused memory (the "gap") directly in the middle of the data. In a text editor, this gap physically tracks the position of the cursor. The text is divided into two contiguous segments: one holding the content before the cursor, and the other holding the content after the cursor.

-   **Moving the Cursor**: The editor simply copies characters from one side of the gap to the other.
-   **Inserting and Deleting**: During typing, characters are written directly into the gap, naturally shrinking it. During deletion, the gap simply expands.

As Charles Crowley notes in his 1998 survey&nbsp;[^fn:4], this data structure is highly optimized for text editors because human typing exhibits extreme spatial locality. Keystrokes rarely jump randomly across a document to insert single characters; most changes to the text occur at or near the current location of the cursor. The gap buffer turns this localized sequential typing into an incredibly fast, amortized \\(O(1)\\) memory operation.

This operational reality perfectly explains the Interval Tree's balancing heuristic. Because Emacs uses a gap buffer, normal, continuous typing does not create new interval nodes. Characters are simply inserted into the gap, which expands the `total_length` of the current interval node at the cursor.

Since typical editing barely increases the total number of nodes, enforcing a strict node-depth balance (like an augmented Red-Black tree) optimizes for an edge case while heavily taxing the CPU on every keystroke. A "weight balance" based on text length is the only design that respects the underlying mechanics of the gap buffer and the physical reality of how humans type.


## 6. Conclusion {#6-dot-conclusion}

The `Lisp_String` interval tree is not a flawed implementation of a binary search tree. It is a specialized structure that deliberately abandons strict depth-balancing to perfectly complement the memory mechanics of the gap buffer. By accepting relative text lengths and lazy rotations, it achieves optimal low-latency text editing.

Reading this codebase, I kept noticing the same instinct repeated at every level: stop fighting the physical reality of text editing; accommodate it. The interval tree does not impose a rigid, globally consistent coordinate system. The gap buffer does not pretend insertions are uniformly distributed. Even the GC rebalance pass runs offline, not on every keystroke. Each layer yields where it can, and the result is a system that stays responsive under continuous human input.

There are two threads left deliberately unresolved. The first is the contrasting design choices behind external implementations—the Linux kernel's `struct interval_tree_node` and LLVM's `llvm::IntervalMap`, both of which choose absolute `[begin, end)` coordinates. The second is closer to home: Emacs itself ships a second interval tree in `src/itree.c`, added in 2017 for overlays, using an augmented red-black tree instead of weight balance. Two coexisting trees in the same codebase, each picking a different invariant for a different query pattern. That comparison deserves its own investigation.

---

Emacs Internal Series:

-   \#01: [Emacs is a Lisp Runtime in C, Not an Editor](@/technical/project/emacs-01.md)
-   \#02: [Data First — Deconstructing Lisp_Object in C](@/technical/project/emacs-02.md)
-   \#03: [Tagged Union, Tagged Pointer, and Poor Man's Inheritance](@/technical/project/emacs-03.md)
-   \#04: Interval Trees — Balancing by Text Length, Not Node Count

---


## 7. Appendix: Debugging Emacs with LLDB {#7-dot-appendix-debugging-emacs-with-lldb}


### 7.1. Build Emacs from Source {#7-dot-1-dot-build-emacs-from-source}

```bash
git clone https://github.com/emacs-mirror/emacs
cd emacs

./autogen.sh

./configure \
  --with-ns \
  --without-native-compilation \
  --enable-checking='yes,glyphs' \
  --enable-check-lisp-object-type \
  CFLAGS='-O0 -g3 -fno-omit-frame-pointer'
```

As officially recommended in Emacs's own `etc/DEBUG` documentation, compiling with these specific flags is critical for a smooth debugging experience:

-   `--enable-checking` and `--enable-check-lisp-object-type`: These turn on internal C assertions (like `eassert`) and enforce strict compile-time type checking for `Lisp_Object`. This immediately catches type errors and internal logic violations.
-   `-O0 -g3`: The `-O0` flag disables compiler optimizations (ensuring variables aren't optimized away while stepping through code in LLDB), while `-g3` ensures that C macros are included in the debug symbols. Since Emacs's source code relies heavily on macros, `-g3` is indispensable.
-   `-fno-omit-frame-pointer`: Guarantees reliable and readable stack traces.
-   `--with-ns` and `--without-native-compilation`: These build the native macOS GUI and disable Ahead-Of-Time Lisp compilation, keeping the build process fast and the debug environment predictable. **Note**: `--with-ns` is macOS-specific (NeXTSTEP/Cocoa). On Linux, use `--with-x` or `--without-x` depending on whether a GUI build is desired.


### 7.2. Run Emacs {#7-dot-2-dot-run-emacs}

Open a terminal and start Emacs:

```bash
./src/emacs -Q -nw
```

-   `-Q`: Equivalent to `-q --no-site-file --no-splash`. Disables loading user initialization files and splash screen.
-   `-nw`: Tells Emacs to run in the terminal instead of creating a graphical UI frame.


### 7.3. Attach with LLDB {#7-dot-3-dot-attach-with-lldb}

Create a new file called `setup.lldb` to configure breakpoints and settings:

```text
breakpoint set -n Fobject_intervals

settings set stop-line-count-before 10
settings set stop-line-count-after 10

process handle SIGTTIN --stop false --pass true --notify false
```

Open a second terminal and attach LLDB to the running Emacs process:

```bash
# Attach by process name (or use `lldb -p <pid>`)
$ lldb -p $(pgrep -f "src/emacs")

# Inside LLDB, load the configuration:
(lldb) command source setup.lldb
(lldb) continue
```

[^fn:1]: J. Nievergelt and E. M. Reingold (1973). "Binary Search Trees of Bounded Balance". _SIAM Journal on Computing_.
[^fn:2]: Hans-J. Boehm, Russ Atkinson, and Michael Plass (1995). "Ropes: an Alternative to Strings". _Software: Practice and Experience_.
[^fn:3]: Daniel D. Sleator and Robert E. Tarjan (1985). "Self-Adjusting Binary Search Trees". _Journal of the ACM_.
[^fn:4]: Charles Crowley (1998). "Data Structures for Text Sequences". _University of New Mexico Technical Report_.
