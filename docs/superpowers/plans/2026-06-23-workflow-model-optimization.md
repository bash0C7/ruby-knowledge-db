# Workflow化・モデル最適化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Daily pipeline を Context 分離 Workflow に移行し、Claude CLI 記事生成・各エージェントのモデルを品質/コストに応じて最適化することで、twin dispatch と `consistent: false` バグを機械的に排除する

**Architecture:** Agent frontmatter にモデルを明示（inspect: Haiku、run: Opus）。Rakefile に `RKDB_ARTICLE_MODEL` 環境変数を追加してデフォルトを Opus に変更。Daily pipeline を `.claude/workflows/rkdb-daily.js` に移行（Stage 1 preflight Haiku → Stage 2 launch Haiku → Stage 3 script loop → Stage 4 postcheck Opus）。Lockfile `tmp/longrun/RUNNING` で twin dispatch を機械的に防止。`/ruby-knowledge-db` コマンドは pipeline intent を Workflow に委譲し、inspect/cleanup は現行維持。

**Tech Stack:** Ruby (Rakefile), Claude Code Workflow JS, Markdown (agent/command frontmatter)

---

### Task 1: inspect-agent に `model: haiku` を設定

**Files:**
- Modify: `.claude/agents/ruby-knowledge-db-inspect.md`

- [ ] **Step 1: frontmatter に model 行を追加**

`.claude/agents/ruby-knowledge-db-inspect.md` の frontmatter を以下に差し替える:

```markdown
---
name: ruby-knowledge-db-inspect
description: Read-only inspection for ruby-knowledge-db — DB stats, pollution/duplicate scans, esa duplicate search, `rake -T` listing, `db/last_run.yml` bookmark readback. Never executes write-side tasks. For pipeline runs or destructive cleanup, use `ruby-knowledge-db-run`.
tools: Bash, Read
model: haiku
---
```

- [ ] **Step 2: commit**

```bash
git add .claude/agents/ruby-knowledge-db-inspect.md
git commit -m "feat(agents): set inspect-agent to haiku model"
```

---

### Task 2: run-agent に `model: opus` を設定

**Files:**
- Modify: `.claude/agents/ruby-knowledge-db-run.md`

- [ ] **Step 1: frontmatter に model 行を追加**

`.claude/agents/ruby-knowledge-db-run.md` の frontmatter を以下に差し替える（description・tools は現行のまま）:

```markdown
---
name: ruby-knowledge-db-run
description: Execute any write-side rake task for ruby-knowledge-db — the full pipeline (`rake`), individual `update:*` / `generate:*` / `import:*` / `esa:*` phases, or destructive cleanup (`db:delete_polluted`, `esa:delete`). Uses a PLAN / CONFIRMED gate so the main session can confirm date ranges and destructive IDs with the user before execution. For read-only queries (stats, scan, find_duplicates, rake -T), use `ruby-knowledge-db-inspect` instead.
tools: Bash, Read
model: opus
---
```

- [ ] **Step 2: commit**

```bash
git add .claude/agents/ruby-knowledge-db-run.md
git commit -m "feat(agents): set run-agent to opus model"
```

---

### Task 3: 記事生成モデルを Opus デフォルトに変更

`trunk_changes.rb:187` の `ContentGenerator` はデフォルト `"sonnet"` を使う。Rakefile の呼び出し側から `model:` を渡すことで上書き可能にする。

**Files:**
- Modify: `Rakefile:148-165` (`build_trunk_collector` メソッド)

- [ ] **Step 1: RKDB_ARTICLE_MODEL 環境変数を追加**

`Rakefile` の `build_trunk_collector` メソッドを以下に差し替える:

```ruby
def build_trunk_collector(source_cfg)
  repo_path = File.expand_path(source_cfg['repo_path'])
  git = GitOps.new(repo_path)
  git.setup(source_cfg['clone_url'], source_cfg['branch'], since_date: ENV['SINCE'])
  gen = ContentGenerator.new(
    repo: source_cfg['repo'],
    prompt_supplement: source_cfg['prompt_supplement'],
    model: ENV.fetch('RKDB_ARTICLE_MODEL', 'opus')
  )
  TrunkChangesCollector.new(
    repo:              source_cfg['repo'],
    branch:            source_cfg['branch'],
    source_diff:       source_cfg['source_diff'],
    source_article:    source_cfg['source_article'],
    git_ops:           git,
    content_generator: gen
  )
end
```

- [ ] **Step 2: 変更を確認**

```bash
grep -A12 "def build_trunk_collector" Rakefile
# → model: ENV.fetch('RKDB_ARTICLE_MODEL', 'opus') が含まれていること
```

- [ ] **Step 3: rake plan が通ることを確認（read-only で安全）**

```bash
APP_ENV=production bundle exec rake plan
# → JSON が出力される（ContentGenerator は呼ばれないので安全）
```

- [ ] **Step 4: commit**

```bash
git add Rakefile
git commit -m "feat(rakefile): add RKDB_ARTICLE_MODEL env var, default opus"
```

---

### Task 4: rkdb-daily Workflow スクリプト作成

Workflow JS はランタイムが実行する。Claude が生成する。

**Files:**
- Create: `.claude/workflows/rkdb-daily.js`

**Workflow の要件（Claude への指示用）:**

| Stage | Model | 処理 |
|-------|-------|------|
| 1. preflight | haiku | lockfile 存在確認 → rake plan → consistent 判定 |
| 2. launch | haiku | lockfile 書き込み → PRE state 取得 → tmux 起動 |
| 3. wait | script loop | 30秒ポーリング、120分タイムアウト |
| 4. postcheck | opus | ログ分析 → delta 計算 → pollution scan → lockfile 削除 |

- [ ] **Step 1: ultracode トリガーで Workflow 生成を依頼**

新しいメッセージに以下を入力して Workflow を生成させる:

```
ultracode: Create a saved workflow for the ruby-knowledge-db daily pipeline.
Save as: .claude/workflows/rkdb-daily.js
Working directory: /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db

Stage 1 — preflight (model: haiku):
- Check if file tmp/longrun/RUNNING exists (use Bash: test -f tmp/longrun/RUNNING).
  If it does, abort with message: "前回パイプラインが実行中です。tmp/longrun/RUNNING を確認してから再実行してください。"
- Run: APP_ENV=production bundle exec rake plan
  Parse the JSON output. Extract: since, before, consistent, contradiction_reasons.
  If consistent is false, abort with: "異常検出: {contradiction_reasons}。手動で修正してから再実行してください。"
- Store since and before as script variables for later stages.

Stage 2 — launch (model: haiku):
- mkdir -p tmp/longrun
- Write content "running" to tmp/longrun/RUNNING
- Run: APP_ENV=production bundle exec rake db:stats → extract "memories total: N", store as preMemories
- Read db/last_run.yml → store content as preBookmark
- Generate timestamp: YYYYMMDD-HHMMSS (current local time)
- session = "rkdb-default-{timestamp}", logPath = "tmp/longrun/{session}.log"
- Launch detached tmux (use exactly this command, substituting {since}, {before}, {log}):
  tmux new-session -d -s rkdb-default-{timestamp} 'bash -c "cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db; export PATH=$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH; { echo ENV which bundle: $(which bundle); ruby -v; } > {log} 2>&1; APP_ENV=production SINCE={since} BEFORE={before} bundle exec rake >> {log} 2>&1; echo DONE: exit=$? finished_at=$(date -Iseconds) >> {log}"'
- Verify: read first 2 lines of log to confirm bundle resolves to rbenv (not /usr/bin/bundle).
  If log shows /usr/bin/bundle, abort: "rbenv 設定が失敗しました。ログ: {first 2 lines}"
- Store session, logPath, preMemories, preBookmark as script variables.

Stage 3 — wait (script loop, no agent needed):
- Poll logPath every 30 seconds for a line starting with "DONE:".
- Timeout after 120 minutes: abort "パイプライン完了待ちがタイムアウトしました (120分)。{logPath} を確認してください。"

Stage 4 — postcheck (model: claude-opus-4-8):
- Read logPath. Find line "DONE: exit=N". Extract exit code N.
- If N != 0:
  - Delete tmp/longrun/RUNNING (run: rm -f tmp/longrun/RUNNING)
  - Abort: "パイプライン異常終了 (exit={N})。ログ末尾:\n{last 50 lines of log}"
- Run: APP_ENV=production bundle exec rake db:stats → extract postMemories
- Run: APP_ENV=production bundle exec rake db:scan_pollution
- Run: APP_ENV=production bundle exec rake esa:find_duplicates
- Compute delta: memoriesDelta = postMemories - preMemories
- Extract from log: all lines matching "esa: #" (posted articles), "ERROR in update:" (failures)
- Extract [trunk-changes] provenance lines verbatim (lines matching "[trunk-changes]")
- Delete tmp/longrun/RUNNING (run: rm -f tmp/longrun/RUNNING)
- Report:
  - Session: {session}
  - Memories: {preMemories} → {postMemories} (+{memoriesDelta})
  - ESA posts: {esa lines}
  - Failures: {ERROR lines or "なし"}
  - Pollution scan: {output}
  - ESA duplicates: {output}
  - PRE bookmark: {preBookmark}
```

- [ ] **Step 2: 生成されたスクリプトを `/workflows` でレビュー**

`/workflows` を実行して生成された run を選択。各ステージのモデル指定・lockfile 操作・tmux コマンドが要件通りか確認する。問題があれば Claude に修正を依頼。

- [ ] **Step 3: ワークフローをプロジェクトに保存**

`/workflows` → 対象 run を選択 → `s` → Tab で Project location (`.claude/workflows/`) を選択 → Enter。

ファイルが作成されたことを確認:

```bash
ls -la .claude/workflows/rkdb-daily.js
```

- [ ] **Step 4: clean state での smoke test**

現在の bookmark が clean（前回 June 19 分が完了済み）なので、`APP_ENV=test` で preflight だけ確認する:

```bash
APP_ENV=test bundle exec rake plan
# → consistent: true と since/before が出ること
```

その後 `/rkdb-daily` を起動してみて Stage 1 が rake plan を実行し consistent: true を確認して Stage 2 に進むことを確認（Stage 2 で本番 tmux を起動したくなければ途中で `p` で一時停止する）。

- [ ] **Step 5: commit**

```bash
git add .claude/workflows/rkdb-daily.js
git commit -m "feat(workflows): add rkdb-daily with per-stage model optimization and lockfile guard"
```

---

### Task 5: `/ruby-knowledge-db` コマンドを Workflow に委譲

Pipeline dispatch ロジック（AUTOCONFIRM fast path・PLAN→CONFIRMED round-trip・background watcher・POSTCHECK 再 dispatch）を削除し、Workflow 呼び出しに差し替える。inspect/cleanup フローは変更しない。

**Files:**
- Modify: `.claude/commands/ruby-knowledge-db.md`

- [ ] **Step 1: Step 5 Dispatch セクションの pipeline 部分を差し替え**

`.claude/commands/ruby-knowledge-db.md` の `#### For ruby-knowledge-db-run dispatches (choices 1 and 3)` セクション内、**pipeline tasks (`default`, `generate:<*_trunk>`) の dispatch ロジック**（AUTOCONFIRM fast path / PLAN→CONFIRMED / detached pattern monitoring / POSTCHECK 再 dispatch の全ブロック）を以下に差し替える。cleanup tasks (`db:delete_polluted`, `esa:delete`) と non-trunk `update:*` の PLAN→CONFIRMED フローは残す。

差し替え後のパイプライン dispatch 部分:

```markdown
#### For pipeline dispatches (choice 1 — `rake default` / `generate:<*_trunk>`)

Invoke `/rkdb-daily` workflow. Do NOT call `ruby-knowledge-db-run` for pipeline tasks.

Before invoking, echo once:
→ 「daily pipeline を /rkdb-daily ワークフローで実行します (SINCE/BEFORE は Workflow Stage 1 が rake plan から解決)」

Then invoke `/rkdb-daily`.

The Workflow handles everything: preflight (rake plan + consistent check), lockfile guard, tmux launch, completion wait, and postcheck. If `consistent: false`, the Workflow aborts with contradiction reasons — surface that message to the user and wait for manual resolution. Do NOT attempt to recover, retry, or use RKDB_FORCE from this command.
```

- [ ] **Step 2: Hard rules セクションに pipeline 禁止ルールを追加**

コマンドの `## Hard rules` セクション末尾に追加:

```markdown
- **Pipeline tasks (`rake`, `generate:<*_trunk>`) は必ず `/rkdb-daily` Workflow 経由**。`ruby-knowledge-db-run` への直接 pipeline dispatch は禁止。`rake plan` を自分で先に取得する必要もない（Workflow Stage 1 が担当）。
```

- [ ] **Step 3: commit**

```bash
git add .claude/commands/ruby-knowledge-db.md
git commit -m "feat(commands): delegate pipeline dispatch to rkdb-daily workflow"
```
