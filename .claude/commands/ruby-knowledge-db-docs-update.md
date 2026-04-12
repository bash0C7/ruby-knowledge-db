---
description: Run the docs update tasks (rake update:rurema / update:picoruby_docs) via the ruby-knowledge-db-docs-update subagent — PLAN first, then confirm, then EXECUTE.
---

Invoke the `ruby-knowledge-db-docs-update` subagent (via the Agent tool) to run the rurema / picoruby_docs update tasks for this project.

Behavior:

1. **First invocation — PLAN mode.** Dispatch the subagent with a prompt that forwards any user-supplied arguments ($ARGUMENTS) but does NOT contain the `CONFIRMED` token. The subagent will read `db/last_run.yml` per collector (`RuremaCollector::Collector`, `PicorubyDocsCollector::Collector`), compute per-collector SINCE and a shared BEFORE, and report back without executing.
2. **Relay the PLAN to the user.** Show the planned APP_ENV / per-collector SINCE / BEFORE / in-scope tasks exactly as the subagent reported them. Ask the user to confirm or adjust.
3. **Second invocation — EXECUTE mode.** Only after explicit user approval, re-dispatch the subagent with a prompt containing `CONFIRMED` plus the confirmed values:
   - Shared: `SINCE=<value> BEFORE=<value>` — or —
   - Per-collector: `RUREMA_SINCE=<value> PICORUBY_DOCS_SINCE=<value> BEFORE=<value>`
   - Sub-scope (optional): `ONLY=rurema` or `ONLY=picoruby_docs`
   Relay the subagent's execution summary back.

Do NOT execute `rake update:*` yourself from the main session — always go through the subagent so the date-range gate and logging stay consistent.

If `$ARGUMENTS` already contains explicit date values or `ONLY=...`, still start in PLAN mode and echo them back for confirmation before adding `CONFIRMED`.

User arguments (optional): $ARGUMENTS
