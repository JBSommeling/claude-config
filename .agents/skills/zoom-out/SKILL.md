---
name: zoom-out
description: Tell the agent to zoom out and give broader context or a higher-level perspective. Use when you're unfamiliar with a section of code or need to understand how it fits into the bigger picture.
disable-model-invocation: true
---

I don't know this area of code well. Go up a layer of abstraction. Give me a map of all the relevant modules and callers, using the project's domain glossary vocabulary.

Then compare it to the norm:

- **How it's built here** — the actual structure, data flow, and key decisions in this code.
- **How it's usually done** — the conventional or idiomatic approach for this kind of problem in this language, framework, and ecosystem.
- **Where they diverge** — each departure from that norm, and the likely reason (deliberate constraint, performance, legacy, or accident).
- **Verdict per divergence** — call it good practice, an acceptable trade-off, or a smell. Say which, and why.

Rules:

- Ground every claim about this code in a `file:line` reference. Do not infer structure you have not read.
- Distinguish "this is unusual" from "this is wrong" — unusual is not automatically bad.
- If you do not know the conventional approach for this stack, say so rather than inventing one.
- Do not propose a refactor. This is read-only orientation, not a review: name the smell and stop.
