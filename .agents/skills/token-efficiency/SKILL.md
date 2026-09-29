---
name: token-efficiency
description: Reduce unnecessary context and tool output in Codex when users request token-efficient work or tasks involve large logs, broad repository exploration, or repetitive reads.
---

# Token efficiency for Codex

Reduce unnecessary reads and output while completing the user's task. Preserve correctness, required validation, and useful explanations.

## Workflow

- Follow applicable AGENTS.md instructions. Locate candidates with rg or rg --files, then read relevant implementations, callers, and tests. Read small files in full when simpler; expand excerpts whenever context is insufficient.
- Reuse established session findings. Re-read when files change, output was truncated, or the evidence is insufficient.
- Inspect summaries and relevant error context before large logs. Preserve command exit status and access to full diagnostics. Empty filtered output does not prove success.
- Bound tool output sensibly. Retrieve missing sections if truncation prevents a reliable conclusion.
- Batch independent reads and searches with available orchestration tools; inspect every result. Keep dependent operations and edits sequential.
- Prefer apply_patch for focused source edits when available. Use native filesystem commands for exact copies without returning complete file contents. Understand affected code before changing behavior.
- Complete required checks. Repeat passing checks only after new edits or when unresolved concerns justify it.
- Report results, meaningful verification, and remaining limitations concisely. Provide more detail when the user requests it.

## Environment

Use tools exposed by the current Codex session. This skill adds no tools or permissions and cannot override system, developer, user, or project instructions.

Keep the current model unless the user requests a supported change. Do not prescribe model switching or subagents to save tokens. Parallel tool calls do not require delegation.

Use the active shell. This workspace uses PowerShell: quote paths with spaces and prefer -LiteralPath for filesystem commands. Do not assume Bash utilities or syntax.

Tool calls and returned text both contribute to context; shell commands are not free. Do not claim savings percentages or pricing without measurements and current evidence.

## Optional references

Read only the reference relevant to the task:
- [strategies.md](strategies.md): Output limits, diagnostics, structured data, and edits.
- [examples.md](examples.md): PowerShell exploration and diagnostic examples.
- [learning-mode.md](learning-mode.md): Understanding unfamiliar code.
- [project-patterns.md](project-patterns.md): Flutter and Supabase starting points.
