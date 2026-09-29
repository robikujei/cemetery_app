---
name: coding-standards
description: Apply coding conventions when implementing, refactoring, or reviewing TypeScript and JavaScript, including React, Node.js, and Supabase Edge Functions. Use for explicit coding-standards reviews; follow project-specific standards for other languages.
metadata:
  original-author: affaan-m
  original-version: "1.0"
---

# Coding standards for Codex

Adapted from the user-provided coding-standards skill. Preserve the requested task scope and follow applicable AGENTS.md instructions, configured formatters, linters, and nearby conventions.

## Scope in this project

The application is Flutter/Dart. Do not introduce React components, Node APIs, Next.js routes, or JavaScript naming rules into Dart code. Follow the project's Dart conventions and validation instructions.

Apply the TypeScript guidance to relevant files under supabase/functions. Inspect imports and runtime configuration before choosing APIs or dependencies; do not assume a Supabase Edge Function runs in Node.js or Next.js.

This skill uses the current session's tools and permissions. It does not install dependencies, change runtime settings, or authorize database execution or deployment.

## Maintainable changes

- Use descriptive names and small, cohesive units of behavior. Split code when responsibilities become unclear, not merely because a function exceeds an arbitrary line count.
- Prefer the simplest implementation that meets the request. Extract shared logic when it represents a stable shared responsibility; avoid speculative abstractions.
- Explain non-obvious decisions and invariants in comments. Document public behavior, inputs, outputs, and meaningful failure cases where callers need them.
- Keep changes focused. Do not reformat unrelated files or replace established folder structure to match a generic template.

## TypeScript and JavaScript

- Prefer explicit domain types and narrow unknown values at external boundaries. Avoid using any to conceal missing validation.
- Validate external input at runtime; a type assertion does not validate JSON. Reuse the project's validation approach instead of adding a library by default.
- Prefer immutable updates for shared state, props, and cached values. Local mutation is acceptable when ownership is clear and it improves simplicity or measured performance.
- Remember that object and array spreads are shallow copies. Update nested state deliberately.
- Await operations whose completion or failure matters. Run independent operations concurrently only when ordering, rate limits, and partial-failure behavior permit it.
- With Promise.all, one rejection rejects the aggregate but does not cancel other work. Use Promise.allSettled when every independent outcome must be examined, and handle each result.
- Catch errors where recovery, translation, cleanup, or useful context is possible. Preserve causes and diagnostic information; avoid catching only to replace an error with a generic message.
- Log useful diagnostics without credentials or sensitive request payloads. Return appropriate user-facing errors at the application boundary.

## React, when working in a React codebase

- Follow the existing component and hook conventions. Clean up subscriptions, timers, and other resources when required by their lifecycle.
- Use functional state updates when the next value depends on previous state. Direct replacement is appropriate when the new value is independent of the previous value.
- Keep loading, error, empty, and success states understandable. Avoid deeply nested conditional rendering when explicit branches read more clearly.
- Use memoization when justified by computation cost, identity requirements, or measured behavior; do not add it to every callback.
- Do not mutate input arrays while sorting derived state:

```typescript
const sortedItems = [...items].sort((a, b) => b.volume - a.volume)
```

## APIs and data access

- Preserve existing request and response contracts unless changing them is part of the task. Do not impose a generic response envelope or a particular framework.
- Validate inputs and enforce authorization on the server. Client-side checks support usability but do not replace access control.
- Handle malformed JSON, upstream failures, and expected domain errors consistently with the endpoint's conventions.
- Select the data needed by the caller. A full row can be appropriate when the complete model is required.
- Use pagination for complete large result sets. Adding an arbitrary limit is not a valid performance fix when it silently omits required data.
- Preserve authentication, row-level security, and related transaction or audit behavior. Consult existing services and SQL before duplicating mutations.
- Bound retries and consider idempotency before retrying writes.

## Verification

Use configured formatting and analysis tools and run the checks required by AGENTS.md. Inspect available scripts and runtime configuration before selecting JavaScript or TypeScript checks; do not assume npm, Jest, or a Node runtime.

Test observable behavior and meaningful failure cases for new logic or fixes when practical. Prefer descriptive names such as 'rejects a check-in with an invalid identifier'. Avoid tests that merely repeat implementation details.

Review the diff for unintended behavior and unrelated edits. Report validation actually performed, failures, and checks that could not be run. Documentation-only skill changes do not require application tests.
