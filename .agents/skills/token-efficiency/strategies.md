# Focused tools and output

Use rg --files with globs for paths, rg -n with context for implementation, rg -l for matching filenames, and rg -q for existence. Exit codes are 0 for a match, 1 for no match, and 2 for an error. A scoped search does not establish absence across the repository.

Avoid generated artifacts and dependency caches unless relevant. Read enough surrounding code to understand behavior; symbol lists alone are insufficient.

For a long-running command, collect completion and status through its session handle instead of launching it again. Capture noisy output in a temporary log when useful, preserving the native exit code before filtering. Retain diagnostics long enough to investigate failures.

Prefer a useful bounded query over many tiny reads. If truncated, narrow the query or retrieve missing evidence.

Parse JSON with ConvertFrom-Json and CSV with Import-Csv or another parser. Splitting CSV on commas breaks quoted fields. Parsing locally reduces returned text but may still require streaming for large inputs. Avoid printing secrets or complete environment files.

Use apply_patch for focused edits when available. Use Copy-Item -LiteralPath for exact copies with understood destinations and overwrite behavior. Preserve encoding and unrelated changes. Before bulk transformations, inspect affected files; review the resulting diff.

Keep Windows filesystem operations within one shell. Verify resolved paths before recursive moves or deletion. Token efficiency grants no additional authorization.
