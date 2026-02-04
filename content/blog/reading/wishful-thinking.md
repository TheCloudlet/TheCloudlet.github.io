+++
title = "Wishful Thinking from SICP, Practically"
description = "A practical exploration of SICP’s wishful thinking as a design principle for both programming and life—using abstraction, trust, and lazy evaluation to move forward without demanding complete certainty upfront."
author = "Yi-Ping Pan (Cloudlet)"
date = 2026-02-04

[taxonomies]
tags = ["thinking", "reading", "sicp"]
categories = ["thinking", "cpp"]
+++

This is **not** a pure technical blog post. It is an attempt to connect engineering principles to real life.

I've been trying to understand my anxiety and self-doubt through engineering principles. [Structure and Interpretation of Computer Programs (SICP)](https://web.mit.edu/6.001/6.037/sicp.pdf) wishful thinking gave me a framework to think about this. But I'm learning that understanding a pattern intellectually doesn't mean I've solved it emotionally. This post is about what I'm learning—not what I've figured out.

## What is Wishful Thinking?

In Chapter 2 of SICP, the authors introduce a powerful strategy for building abstractions: wishful thinking. The idea is simple but profound: **write code as if the pieces you need already exist.** Define the interface you wish you had, then trust that the implementation details can be filled in later.

When explaining this concept, the authors write:

> We are using here a powerful strategy of synthesis: wishful thinking.
> We haven’t yet said how a rational number is represented, or how the
> procedures `numer`, `denom`, and `make-rat` should be implemented. Even
> so, if we did have these three procedures, we could then `add`, `subtract`,
> `multiply`, `divide`, and test `equality` ...

To make this concrete, here's the same concept in C++ without OOP. Notice how we **use functions that don't exist yet**, and we haven't defined how the **Rational** data type is represented—that's wishful thinking:

```cpp
int numer(const Rational& r);
int denom(const Rational& r);
Rational make_rat(int numerator, int denominator);

// Now we can write high-level operations using our "wished" interface
Rational add_rat(const Rational& x, const Rational& y) {
  return make_rat(numer(x) * denom(y) + numer(y) * denom(x),
                  denom(x) * denom(y));
}

Rational sub_rat(const Rational& x, const Rational& y) {
  return make_rat(numer(x) * denom(y) - numer(y) * denom(x),
                  denom(x) * denom(y));
}

Rational mul_rat(const Rational& x, const Rational& y) {
  return make_rat(numer(x) * numer(y),
                  denom(x) * denom(y));
}

Rational div_rat(const Rational& x, const Rational& y) {
  return make_rat(numer(x) * denom(y),
                  denom(x) * numer(y));
}

bool equal_rat(const Rational& x, const Rational& y) {
  return numer(x) * denom(y) == numer(y) * denom(x);
}
```


Now, the rest of the missing pieces tend to emerge naturally, almost effortlessly.

This way of thinking gave me a way to stop reacting blindly to every signal, and instead design my next step deliberately. In that sense, wishful thinking wasn’t just a programming technique for me—it became a survival tool.

---

## How I Apply Wishful Thinking to My Life

How do I actually use _wishful thinking_ in my life?

I follow these steps:

1. **Define the outcome**

   Specify the mental state or concrete achievement you are aiming for.

2. **Identify the procedures**

   Define the procedures that would contribute to achieving that outcome, without worrying about their implementation yet.

3. **Lazy evaluation**

   Defer thinking and decision‑making until action is actually required.
   Avoid premature optimization, over‑planning, or the urge to make everything perfect upfront.

For example, I define my perfect day like this:

```racket
(define (a-great-day)
  (let ([breakfast (with-hot-coffee)]
        [commute-to-work (listen-to-good-music)]
        [work (perform-meaningful-contribution)]
        [family (initiate-a-warm-hug)]
        [growth (learn-1-simple-thing-today)])))
```

Or my ideal life:

```racket
(define (my-ideal-life)
  (let ([mind (inner-peace)]
        [body (healthy-body)]
        [family (cherish-everyday)]
        [interaction (spread-warmth-and-kindness)])))
```

The following are my own reminders:

### 01. Define the Goal

A gentle reminder from Naval Ravikant: “Desire is a contract you make with yourself to be unhappy until you get what you want.” That quote forces me to define my “good day” and “ideal life” with extreme restraint.

I often catch myself chasing things that society rewards—status, recognition, external validation. But pursuing those metrics usually leads to anxiety and dissatisfaction, which is the opposite of what I actually want. The irony is obvious: I was optimizing for the wrong objective function.

> Clarity is not motivation; it is a filter.

When the end state is not clearly defined, every option feels equally important. Everything competes for attention, and motion feels like progress—but nothing converges.

Once the end state is clear, most options fall away naturally. What looked like luck was just knowing where I was heading.

Effortless doesn't mean easy. It means the system knows where it's going.

### 02. Find the Procedures

> Always work top-down, not bottom-up. Think recursive.

I've been struggling at work for three years. I ship solid technical work—optimizations, stable regressions—but I struggle with communication and office dynamics. When my senior colleague consistently rejects my code reviews, I get defensive. I speak too directly. I miss social cues. The mismatch is real: this environment needs both technical skills and political awareness. I have the former, I'm learning the latter is not my strength. This hurts to admit.

I'm trying to distinguish between useful feedback and noise. But I notice I sometimes filter out painful truths by labeling them 'not aligned with growth.' When someone points out I'm too aggressive in code reviews, I want to dismiss it. But maybe that's exactly the feedback I need. I'm still learning where the line is between protecting myself from toxic criticism and avoiding uncomfortable growth.

> Not all feedback is input; some of it is noise.

### 03. Lazy Evaluation

This is the most important part.

1. **Before execution, don’t panic.**

   Avoid catastrophizing the future. Trust that when execution starts, the next required step will naturally become clearer. Just like a lazy evaluator, clarity is produced only when demanded.

2. **Execute lazily. Live at runtime.**

   This idea maps surprisingly well to Zen thinking. Zen does not ask you to stop thinking—it asks you to stop precomputing.
   
   When I execute a task, I try to stay fully inside the current stack frame. I am only here, only now. In that sense, I am a single-threaded system. 
   
   Humans are not compilers running with `-O3`. We don't need to speculate every branch, unroll every loop, or pipeline every future scenario. Multitasking looks powerful, but for human brains it often results in cache stalls, context switching, and mental thrashing.

3. **Meaning emerges during execution, not before it.**

   Zen has a quiet reminder:

   > The path appears where the feet land.

   In engineering terms, many insights are late-bound. They cannot be derived at design time—they emerge only when the system runs. Wishful thinking lets me defer unnecessary decisions. Zen teaches me to stay present enough to recognize the right one when it finally arrives.

## Conclusion

I found wishful thinking when I was looking for answers. I was struggling—with self-doubt, with not knowing my worth, with trying to prove something I couldn't name. Systematic thinking felt like solid ground in uncertain terrain.

But here's what I'm learning: I use frameworks to feel in control when I'm actually scared. When life feels chaotic, I reach for structure. When I'm hurt, I intellectualize. This isn't wrong—it's how my mind works. But it has limits. Some wounds don't need better architecture. They need time, and rest, and the courage to admit I don't have it figured out.

SICP taught me wishful thinking as engineering practice. Life is teaching me it's also about wishing for peace while not knowing how to get there—and learning that's okay. Some days I remember this. Most days I forget and try to optimize my way out of uncertainty. That's where I am: somewhere between understanding and living, between the wish and the trust.

I'm still learning.

---

## Other Reference

- [Applicative-Order vs Normal-Order Evaluation](https://sookocheff.com/post/fp/evaluating-lambda-expressions/)
- [Thunk (Haskell)](https://wiki.haskell.org/Thunk)
- [The Lazy Method](https://www.youtube.com/watch?v=G6YZSyoShBE), by Josh Brindley.
