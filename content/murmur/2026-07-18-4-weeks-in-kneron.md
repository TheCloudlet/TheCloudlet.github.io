+++
title = "Work as Play; 4 weeks onboarding."
author = ["Yi-Ping Pan (Cloudlet)"]
description = "Reflections on finding work that feels like play, long-term games, and the texture"
date = 2026-07-19
draft = false
[taxonomies]
  tags = ["driving", "clouds", "career"]
  categories = ["murmur"]
[extra]
  math = true
  math_auto_render = true
+++

## The First Few Weeks {#the-first-few-weeks}

This Friday, I suddenly realized I hadn’t opened League of Legends for several days. Normally I would queue one or two ARAM games almost every evening, but instead I just lay on the living room floor, staring at the ceiling and spacing out. It felt strange — and strangely peaceful.

For the first few days, I threw myself into setting up the environment. Thanks to [GNU Stow](https://www.gnu.org/software/stow/), I managed to get my entire workflow — bash, zsh, Emacs, tmux, and even mail — up and running within two hours on the first day. That part felt almost too smooth.

Even though I had set up my personal environment very quickly, the actual codebase was another story. The next two days were spent wrestling with Docker and a huge Git super-repo that had many undocumented build requirements. Coming from a Perforce background, I had to relearn how to navigate and build in this new system, and it took quite a bit of trial and error before things started to make sense. At the same time, I also went through the existing documentation and made some updates, partly because I knew how frustrating it could be to onboard without clear instructions. After getting the environment stable, I spent another day trying to grasp the bigger picture of the compiler pipeline and how regressions were being handled.

By the end of my first week, I unexpectedly ran into a precision conversion problem that looked serious enough to affect production models. After cross-referencing with LLVM’s APFloat and GCC’s implementation, I decided to raise it with my manager. I ended up spending the next day rewriting that module, and managed to land the change before the week ended. It wasn’t something I had planned, but being able to make a real contribution so early on gave me a small sense of relief amid the pressure I had been putting on myself.

In the second week, I started working on an NPU runtime performance issue related to MLIR dialect lowering in PReLU, and nailed it.


## An unexpected call {#an-unexpected-call}

In my third week at Kneron, I took a sick day. I was running a fever and spent most of the afternoon lying in bed. Sometime after lunch, my phone rang with an unknown number. I didn’t pick up.

A short while later, an email arrived from a recruiter at a prestigious local IC design company. The message was polite, but one sentence stood out:

> "Unfortunately, we have been unable to reach you by phone on several occasions."

I paused at that line. As far as I could remember, there had only been one missed call that day. Still, I replied with clear windows of availability over the next two days, assuming we would connect soon.

We didn’t. No confirmation came. No call arrived during the times I had offered.

The following week, she replied — not to my availability email, but to an earlier message in the thread. Once again, the framing was familiar: she was following up because it had been difficult to reach me. It felt as if the previous exchange had simply been reset.

Looking back, the entire process had already stretched much longer than originally suggested. When I first entered the interview pipeline in mid-April, I was told the role was high priority and that they would run an accelerated process. The expectation at the time was that an offer could come within roughly three weeks if things went well. In reality, the technical interviews continued into early June. After the final round on June 3, I was told that a written offer could be ready within a week. The next message I received was on July 9.

By that point, my initial interest in the role had started to cool. On paper the opportunity was still strong. But the way the final stage was handled left me with a clear impression: if communication could already feel this careless before I even joined, it was hard to believe the internal culture would treat people very differently.

I found myself asking a simple question. If this was how they managed the last step of a long interview process, what would day-to-day collaboration feel like?


## Work as Play {#work-as-play}

It was not an easy choice to make. I asked a few close friends, and most of them thought I should take the offer. In the middle of that uncertainty, two lines from Naval Ravikant kept returning to me:

> "What feels like play to you, but looks like work to others?"

and,

> "Play long-term games with long-term people."

After three weeks, the compiler work at Kneron already felt closer to play than anything else I had done in a while. I was fast and smooth. Even though I didn’t have a solid understanding of all the details yet, I had a strong intuition that some patterns and designs felt fishy and dangerous. Catching and fixing them didn’t drain me; it was genuinely fun.

Space came first. My desk sits behind my manager's — unusual in many Taiwanese companies, where managers often sit at the back so they can watch the team. Sitting the other way around felt like a small, physical statement: nobody here needed to watch me work.

Time came next. Official hours are 9-to-6, yet the culture is flexible enough that I can arrive around 7 and leave at 4 without friction. A colleague on the same compiler team took six months of unpaid leave to go backpacking shortly after I joined — and simply returned to his desk when it was over.

And then there was how people asked for things. Questions were treated as normal, not interruptions. People would just walk over and ask when they needed something, instead of scheduling a formal discussion first.

Three different things — space, time, and how people talk to each other — pointed at the same underlying choice: this was a place that trusted people first, and controlled them only when it had to.

I’m genuinely thankful for the people and the space I’ve found here.

I still notice the length of the drive (160 km per day). Some mornings the traffic is exhausting. On clear days the sky opens up; on typhoon days the same road turns into a slow crawl.

![Typical sunny morning on the drive to work](/images/2026-07-19-sunny.webp)
_Typical sunny morning_

![Typhoon day traffic on the same road](/images/2026-07-19-typhoon.webp)
_Typhoon day traffic_

At the same time, those hours in the car have become a quiet buffer — time to look at the sky, to think, or to do nothing in particular. Leaving at four also means I often catch the late afternoon light on the way home.

![Late afternoon light, leaving at 4](/images/2026-07-19-leave-at-4.webp)
_Leaving at 4_

![Clouds from the road](/images/2026-07-19-clouds.webp)
_Amazing clouds_

I didn’t expect that part to feel valuable.

In the end, I declined the other offer. Not because it was a bad opportunity, but because I could already tell which environment let me work in a way that felt sustainable. I would rather keep building depth in an area I genuinely enjoy than optimize for prestige or proximity.

4 weeks is still early. But so far, I feel good.
