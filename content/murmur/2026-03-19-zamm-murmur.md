+++
title = "Plane Spotting, Non-Euclidean Geometry, and Cultural Runtimes"
author = ["Yi-Ping Pan (Cloudlet)"]
date = 2026-03-19
draft = false
[taxonomies]
  tags = ["murmur"]
  categories = ["murmur"]
[extra]
  math = true
  math_auto_render = true
+++

[Plane spotting at the airport](/images/2026-03-19-plane.jpg)

> Just watching the metal birds take-off. Sorry for the grainy photo.

Whenever I feel emotionally tired, I decide to go to the airport for some plane spotting. I love planes, for no reason. Watching a big chunk of metal carrying people around just satisfies me. Today, I went to the local airport, watched planes alongside the approach air traffic control, and had some reflections in the back of my head.


## Starting a habit of reading blog post {#starting-a-habit-of-reading-blog-post}

This week, I picked up a habit of subscribing to people's posts and reading them. I realized that when I use my Elfeed to read my subscribed feeds and blogs, I feel a sense of peace and joy. Some blog posts are technical, some are about life struggles, and I can feel more connected with the author.

This made me think: what is the difference between reading blog posts and watching YouTube channels? Both are streams of data, but this is what feels real to me.

First, reading blog posts using Elfeed with eww, transfers all fancy webpages into plain text, forcing myself fucusing on the context itself by ripping out all the distractions.

[Elfeed in Emacs](/images/2026-03-19-Elfeed.png)

Also, most posts I subscribe to are not aimed at profit; some authors are already successful in various areas. Blog posts have true authenticity, and the words don't feel forced—I don't feel like the author is trying to convince or sell concepts to me. On the contrary, reading things on LinkedIn is such a pain where people are screaming, "LOOK AT ME, I'M GOOD." Every sentence looks like they are using SCREAMING_CASE to emphasize their points.

For my own preference of reading other's posts, I try to do the same on my own writing. I try to avoid this "forcing" or "pushing" way and just share what I've explored. It might not be accurate or 100% correct, but hey, it might be fun to record the process as a growing engineer, and a growing _Homo sapiens_. I decided to start this category - murmur, without any specific goal, just to record my thoughts and having fun.


## Thoughts on book ZAMM {#thoughts-on-book-zamm}

Today, I was reading the book _Zen And the Art of Motorcycle Maintenance_. At Chapter 26, there is a intersting take about the Fifth Postulate of Euclidean geometry and the crisis of absolute truth.

> 1.  That, if a straight line falling on two straight lines make the interior angles on the same side less than two right angles, the two straight lines, if produced indefinitely, meet on that side on which are the angles less than the two right angles.

For over two thousand years, humanity treated Euclidean geometry as the absolute, unquestionable hardware architecture of the universe. The axioms were the foundational source code. But the Fifth Postulate (the parallel postulate) always felt a bit off—like a lingering "code smell" that developers just accepted because the system still compiled.

Then, mathematicians like Lobachevsky and Riemann did something incredibly hacker-like. They asked: What if we just comment out this line of code and replace it with its exact opposite? Will the system crash?

It didn't. Instead of throwing a logical exception or a contradiction, it successfully compiled an entirely new, non-Euclidean reality (hyperbolic and spherical geometries). It proved that mathematics wasn't the absolute "Truth" of the universe, but rather a system of logical deductions based on arbitrarily chosen axioms.

[What's the Deal with Euclid's Vth Postulate?](https://www.youtube.com/watch?v=pmGDea9ZQ4U)

This reminds me of the recent video I watched [This Theory of Everything Could Actually Work: Wolfram's Hypergraphs](https://www.youtube.com/watch?v=-yzdjziS-bo)

My personal summary of Wolframs' work is:

1.  **Space** is just a connectivity graph: The universe isn't a pre-existing, empty box. It is modeled simply as a massive hypergraph. There is nothing but nodes and their relations.

2.  **Gravity** is just node density: Gravity isn't some magical fundamental force. It emerges naturally wherever lots of dots (nodes) are clustered together. This massive density of connections computationally "bends" the space around it.

3.  **Quantum** mechanics is multi-threading: Because the graph's updating rules can be applied in different orders, the exact same starting condition can branch out into dramatically different results. Yet, every single branch is a perfectly valid state of the system. This elegantly simulates quantum superposition and parallel universes.

Back to everyday life. I think these two scientific "truths" show that there is no absolute truth. Just like the philosophies in SICP, some rules are just like human interaction protocols.

If you ask for an opinion in Finland, they will give you exactly what they really think. Sugarcoating, exaggerating, or giving a "polite opinion" to save face is often viewed by Finns as suspicious or an inefficient use of bandwidth. (The direct words really shocked and hurt me when I first studied in a class full of Finns, but I've gotten used to it and now I love it.) However, if you output that same raw payload in Taiwan, you are considered unsocialized or ill-mannered. Neither protocol is universally "correct"; they are just different runtime environments expecting different APIs.

So, if someone is struggling in a specific environment—whether it's the corporate world, a relationship, or whatever—it's probably not because they are insufficient or broken. Maybe it's just that they are not in a suitable environment, and their evaluation through that specific interpreter will simply always throw a `TypeMismatchException`.
