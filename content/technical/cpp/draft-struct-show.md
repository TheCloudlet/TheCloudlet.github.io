+++
title = "fixme"
author = ["Yi-Ping Pan (Cloudlet)"]
description = "fixme"
date = 2026-01-30
draft = true
[taxonomies]
  tags = ["data-serialization", "debugging", "string-formatting"]
  categories = ["systems-programming"]
+++

## Structure thinking {#structure-thinking}

-   Intro, why, coverity (CL: 6463213)
    -   Expalin: Handling mutiple types int, long, char\* printing when debugging
        std::swtringstream ss;; return string

-   What I did?
    -   Lambda function (3 kinds)
    -   result - no more `ss << "\txxx - " << value` and weird if else checking string null

-   It is just like Haskell / Lisp show ...
    so maybe we should use the same way in cpp, when defining a struct, think how to print it.

-   how does &lt;&lt; handles print value?
    need to google? if every struct or data has good toString(), printing will be super easy.


## Code {#code}

```cpp
struct my_struct {
  int int_value;
  long long_value;
  char* x_name;
  char* y_name;
  char* z_name;
}

std::string debugStruct(struct my_struct* ps) {
  if (!ps) {
    return std::string();
  }

  std::stringstream ss;

  ss << "my_stuct: {" << std::endl;

  if (ps->x_name) {
    ss << "\tx_name: " << ps->x_name << std::endl;
  } else {
    ss << "\tx_name: null" << std::endl;
  }

  if (ps->y_name) {
    ss << "\ty_name: " << ps->y_name << std::endl;
  } else {
    ss << "\ty_name: null" << std::endl;
  }

  if (ps->z_name) {
    ss << "\tz_name: " << ps->z_name << std::endl;
  } else {
    ss << "\tz_name: null" << std::endl;
  }

  ss << "int_value: " << ps->int_value << std::endl;
  ss << "long_value: " << ps->long_value << std::endl;

  ss << "}" << std::endl;

  return ss.str();
}
```


## Thinking about the writing flow {#thinking-about-the-writing-flow}

1.  Tell the story and show the code
2.  Give ppl minutes to think what might be weird to me
3.  Pinpoint out the weird parts
    -   stringstream
    -   not having a correct way to output a struct (Haskell, Ractect)
4.  what are the possible solution and what I chose

---


## It all started from a fixing a static analysis issue {#it-all-started-from-a-fixing-a-static-analysis-issue}
