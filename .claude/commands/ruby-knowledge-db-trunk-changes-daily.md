---
description: Run the trunk-changes daily pipeline (rake daily) via the ruby-knowledge-db-trunk-changes-daily subagent — PLAN first, then confirm, then EXECUTE.
---

Invoke the `ruby-knowledge-db-trunk-changes-daily` subagent (via the Agent tool) to run the trunk-changes daily pipeline for this project.

Behavior:

1. **First invocation — PLAN mode.** Dispatch the subagent with a prompt that forwards any user-supplied arguments ($ARGUMENTS) but does NOT contain the `CONFIRMED` token. The subagent will read `db/last_run.yml`, compute the intended SINCE/BEFORE, and report back without executing.
2. **Relay the PLAN to the user.** Show the planned APP_ENV / SINCE / BEFORE / target sources exactly as the subagent reported them. Ask the user to confirm or adjust the date range.
3. **Second invocation — EXECUTE mode.** Only after explicit user approval, re-dispatch the subagent with a prompt that contains `CONFIRMED SINCE=<value> BEFORE=<value>` (plus any APP_ENV override the user gave). Relay the subagent's execution summary back.

Do NOT execute `rake daily` yourself from the main session — always go through the subagent so the date-range gate and logging stay consistent.

If `$ARGUMENTS` already contains explicit `SINCE=` / `BEFORE=` values, still start in PLAN mode and echo them back for confirmation before adding `CONFIRMED`.

User arguments (optional): $ARGUMENTS
