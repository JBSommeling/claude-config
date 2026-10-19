---
description: Conduct a five-axis code review — correctness, readability, architecture, security, performance
---

Invoke the code-review skill.

Review the current changes (staged or recent commits) across all five axes:

1. **Correctness** — Does it match the spec? Edge cases handled? Tests adequate?
2. **Readability** — Clear names? Straightforward logic? Well-organized?
3. **Architecture** — Follows existing patterns? Clean boundaries? Right abstraction level?
4. **Security** — Input validated? Secrets safe? Auth checked? (See security-and-hardening skill)
5. **Performance** — No N+1 queries? No unbounded ops? (Check for performance issues)

If the diff touches motion code, also invoke the `review-animations` skill on those files (it uses STANDARDS-RN.md for React Native code). Motion code means — React Native: imports from `react-native-reanimated`, `react-native-gesture-handler`, `moti`, or `Animated` from `react-native`; web: `motion`/`framer-motion`, or CSS `transition`, `animation`, `@keyframes`, WAAPI `element.animate`. Report its findings under a separate "Motion" section, using the same Critical / Important / Suggestion severities.

Categorize findings as Critical, Important, or Suggestion.
Output a structured review with specific file:line references and fix recommendations.
