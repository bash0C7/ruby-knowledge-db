#!/bin/bash
# PreToolUse hook for ruby-knowledge-db: block direct (non-rake) access to
# the trunk-changes cache repos. The cache holds shallow + working copies of
# picoruby/ruby/mruby that the rake pipeline mutates; running side `git`
# inspections here is how a recent subagent fabricated a wrong "ruby_3_4
# branch" attribution. Provenance must come from the [trunk-changes] line in
# `bundle exec rake generate:*` stdout.
set -euo pipefail

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // ""')

# Only fire on commands that touch the trunk-changes cache repos.
if ! echo "$cmd" | grep -qE '\.cache/trunk-changes-repos'; then
  exit 0
fi

# Allow the rake gateway — rake internally drives every legitimate cache op.
if echo "$cmd" | grep -qE 'bundle[[:space:]]+exec[[:space:]]+rake'; then
  exit 0
fi

# Explicit one-off bypass for human verification.
if echo "$cmd" | grep -qE 'RKDB_HOOK_BYPASS=1'; then
  echo "[rkdb-hook] BYPASSED via RKDB_HOOK_BYPASS=1 — direct cache repo access allowed for this command" >&2
  exit 0
fi

cat >&2 <<'EOF'
[rkdb-hook] BLOCKED: direct access to ~/.cache/trunk-changes-repos/ outside rake.

Provenance for trunk-changes commits comes from the [trunk-changes] line
emitted on stdout by `bundle exec rake generate:*` (or `bundle exec rake`).
Reconstructing branch / commit attribution via side `git` commands against
the cache repos is forbidden — that's the failure mode this hook guards.

If you genuinely need to inspect cache repo state for a one-off:
  RKDB_HOOK_BYPASS=1 <your command>

See:
  .claude/agents/ruby-knowledge-db-run.md
  .claude/agents/ruby-knowledge-db-inspect.md
EOF

exit 2
