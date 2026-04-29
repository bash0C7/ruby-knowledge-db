---
description: Unified entry point for ruby-knowledge-db operations. Routes user intent (pipeline runs / read-only inspection / cleanup / task listing) to the appropriate subagent after confirming with the user.
---

Unified router for the ruby-knowledge-db project. Use this whenever the user asks for anything scoped to this repo — running the daily pipeline, individual `update:*` tasks, inspecting DB state, finding duplicates, cleaning up pollution, or just listing what's available.

## Routing targets

- **run-agent** (`ruby-knowledge-db-run`) — any write-side rake task:
  - `rake` (default pipeline: trunk + every `update:*` + iCloud copy)
  - `rake update:<name>` / `generate:<key>` / `import:<key>` / `esa:<key>` (individual phases)
  - `rake db:delete_polluted IDS=...` / `rake esa:delete IDS=...` (destructive cleanup)
  - Uses a `CONFIRMED`-token gate so the main session can relay parameters to the user for approval.
- **inspect-agent** (`ruby-knowledge-db-inspect`) — read-only:
  - `rake -T`, `rake plan`, `rake db:stats`, `rake db:scan_pollution`, `rake esa:find_duplicates`, `db/last_run.yml` readback, ad-hoc SQL SELECT.
  - No gate — safe to run immediately.

## Flow

### 1. Always begin by fetching `rake -T`

Run `cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db && bundle exec rake -T` yourself in the main session (quick, cheap, no side effects). This is the source of truth for what's currently invocable — task sets change as the Rakefile evolves.

Do not cache or assume the task list; re-run every time this command is invoked.

### 2. Parse `$ARGUMENTS` to infer intent

If `$ARGUMENTS` clearly names an operation (e.g. "daily", "rake 走らせて", "db:stats", "rurema 更新", "削除して #135", "tasks 見せて"), skip to step 4 with that intent pre-filled.

If `$ARGUMENTS` is empty or ambiguous, go to step 3.

### 3. Present the semi-dynamic menu

Show the user these choices. The labels are fixed; the bullet points under each are drawn from the current `rake -T` output so new tasks get surfaced automatically.

```
どれにする、質問？

1. 取り込み — パイプライン実行
   - `rake`（デフォルト、全パイプライン: trunk + update:* + iCloud）
   - `rake update:<name>` 個別（<name> は rake -T の update:* から選択）
   - `rake generate:<key>` / `import:<key>` / `esa:<key>` 個別

2. 確認 — read-only
   - `rake db:stats`（memories / vec / fts 三者一致）
   - `rake db:scan_pollution`（空メタ・重複検出）
   - `rake esa:find_duplicates [DATE=...]`
   - `db/last_run.yml` bookmark 読み出し
   - 任意の SELECT クエリ

3. 掃除 — 破壊的整理
   - `rake db:delete_polluted IDS=...`
   - `rake esa:delete IDS=...`

4. rake -T 一覧表示（このまま出力）

5. その他（自由入力）
```

List the current `update:*` / `generate:*` / `import:*` / `esa:*` task names under each category dynamically from the `rake -T` output — do not hardcode the list.

Ask the user to pick (number or natural language).

### 4. Confirm understanding

Whether intent came from `$ARGUMENTS` (step 2) or the menu (step 3), echo back your interpretation in one or two sentences:

```
→ 「<意図の言い換え>」で進めるピョン、確認？
   （例: rake daily 相当の全パイプラインを昨日分で実行、SINCE/BEFORE は subagent が bookmark から計算）
```

Wait for user approval. If the user adjusts, update and re-confirm.

### 5. Dispatch

Based on the confirmed intent:

| Menu choice | Dispatch target                                                           |
|-------------|---------------------------------------------------------------------------|
| 1. 取り込み   | `ruby-knowledge-db-run` subagent (PLAN first, then CONFIRMED/AUTOCONFIRM on approval) |
| 2. 確認      | `ruby-knowledge-db-inspect` subagent (direct, no gate)                    |
| 3. 掃除      | `ruby-knowledge-db-run` subagent (TASK=db:delete_polluted or esa:delete, PLAN then CONFIRMED) |
| 4. rake -T  | Print the `rake -T` output you already fetched in step 1 — no subagent    |
| 5. その他    | Treat as free-form; re-ask clarification, or route to whichever subagent fits once clarified |

#### For `ruby-knowledge-db-run` dispatches (choices 1 and 3)

**Pipeline tasks (`default`, `generate:<*_trunk>`)** have a fast path. Before dispatching, run `rake plan` via the inspect-agent (or directly in the main session — it's read-only):

```
INTENT=plan [SINCE=...] [BEFORE=...] [APP_ENV=production]
```

Parse the JSON output's `consistent` field:

- **`consistent: true`** → echo SINCE/BEFORE to the user (step 4 confirmation), then dispatch with **`AUTOCONFIRM`** in one shot (no separate PLAN round-trip):

  ```
  AUTOCONFIRM TASK=<task> SINCE=<plan.since> BEFORE=<plan.before> APP_ENV=<v>
  ```

- **`consistent: false`** → relay `contradiction_reasons` verbatim to the user. Wait for the user to either (a) fix the underlying issue (e.g. `rake esa:delete IDS=...`) and re-invoke `/ruby-knowledge-db`, or (b) explicitly approve a forced run, in which case dispatch with **`CONFIRMED ... RKDB_FORCE=1`**.

**Destructive tasks (`db:delete_polluted`, `esa:delete`) and non-trunk `update:*`** still use the legacy two-step PLAN → CONFIRMED flow. First invocation:

```
TASK=<resolved task> [SINCE=...] [BEFORE=...] [IDS=...] [APP_ENV=...]
[free-form context from the user]
```

Relay the subagent's PLAN to the user. On approval, second invocation:

```
CONFIRMED TASK=<task> SINCE=<v> BEFORE=<v> [IDS=<v>] [APP_ENV=<v>]
```

#### For `ruby-knowledge-db-inspect` dispatches (choice 2)

One invocation, direct. Prompt template:

```
INTENT=<db:stats|db:scan_pollution|esa:find_duplicates|last_run|free-form SQL>
[additional params: DATE=..., SQL=..., etc.]
```

### 6. Relay the result

When the subagent returns, relay its output back to the user. Keep it concise — avoid re-explaining what the subagent already explained.

## Hard rules

- **Never** execute `rake` / `rake update:*` / `rake generate:*` / `rake import:*` / `rake esa:*` / `rake db:delete_*` / `rake esa:delete` yourself from the main session — always go through `ruby-knowledge-db-run`.
- **Never** run ad-hoc write queries against `db/ruby_knowledge.db` yourself — delegate to subagents.
- **Never** skip step 4 (confirm understanding). Even when `$ARGUMENTS` is explicit, echo back the interpretation before dispatching.
- **`rake -T`, `rake plan`, and `rake db:stats`** may be run directly in the main session (all read-only). Anything else: delegate.

User arguments (optional): $ARGUMENTS
