# Understanding unfamiliar code

Choose exploration depth from the task, not a model name or fixed reading budget.

For a focused change, locate its entry point and implementation, then read relevant types, callers, and tests. Trace error handling and side effects where they affect the change. Expand when dependencies or behavior remain unresolved.

For an architecture explanation, begin with project instructions and the manifest, then follow startup, routing, state management, and service boundaries. Read representative workflows deeply enough to explain their connections.

For a convention, compare a working implementation with its consumer and tests. Read a second example when the first is ambiguous or behavior differs by role.

Distinguish observed behavior from inference. Filenames and symbol searches locate evidence; they do not prove runtime behavior. Small samples cannot justify repository-wide claims.

Reuse findings in the conversation. Create persistent notes only when requested or required for a concrete deliverable; avoid automatically adding scratch documentation.

Stop exploration when evidence is sufficient to fulfill the request and validate the result. Continue authorized implementation through completion.
