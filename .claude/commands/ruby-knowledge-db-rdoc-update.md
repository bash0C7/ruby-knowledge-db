---
description: Run the RDoc JP translation update (rake update:ruby_rdoc) via the ruby-knowledge-db-rdoc-update subagent — PLAN first, then confirm, then EXECUTE.
---

Invoke the `ruby-knowledge-db-rdoc-update` subagent (via the Agent tool) to run the RDoc JP translation pipeline for this project.

Behavior:

1. **First invocation — PLAN mode.** Dispatch the subagent with a prompt that forwards any user-supplied arguments ($ARGUMENTS) but does NOT contain the `CONFIRMED` token. The subagent will read `db/last_run.yml`, check translation cache size, estimate cost, and report back without executing.
2. **Relay the PLAN to the user.** Show the planned APP_ENV / SINCE / BEFORE / TARGETS / MAX_METHODS / cost estimate exactly as the subagent reported them. Ask the user to confirm or adjust.
3. **Second invocation — EXECUTE mode.** Only after explicit user approval, re-dispatch the subagent with a prompt containing `CONFIRMED` plus the confirmed values:
   - `SINCE=<value> BEFORE=<value>`
   - Optionally: `RUBY_RDOC_TARGETS=<classes>` / `RUBY_RDOC_MAX_METHODS=<N>`
   Relay the subagent's execution summary back.

Do NOT execute `rake update:ruby_rdoc` yourself from the main session — always go through the subagent so the cost/scope gate stays consistent.

If `$ARGUMENTS` already contains explicit values, still start in PLAN mode and echo them back for confirmation before adding `CONFIRMED`.

User arguments (optional): $ARGUMENTS
