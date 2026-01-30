+++
title = "fixme"
description = "fixme"
author = "Yi-Ping Pan (Cloudlet)"
date = 2026-01-30
draft = true

[taxonomies]
tags = ["fixme"]
categories = ["cpp"]
+++

## Structure thinking

- Intro, why, coverity (CL: 6463213)
  - Expalin: Handling mutiple types int, long, char* printing when debugging
    std::swtringstream ss;; return string

- What I did?
  - Lambda function (3 kinds)
  - result - no more `ss << "\txxx - " << value` and weird if else checking string null

- It is just like Haskell / Lisp show ...
  so maybe we should use the same way in cpp, when defining a struct, think how to print it.

- how does << handles print value?
  need to google? if every struct or data has good toString(), printing will be super easy.
