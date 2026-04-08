# E2E Verification Plan — picoruby-trunk-changes (test env)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** End-to-end verification of the 3-phase trunk-changes pipeline in test environment, then confirm esa posting works.

**Architecture:**
```
Phase 1: rake generate:picoruby_trunk SINCE=... BEFORE=... APP_ENV=test
  → git shallow-clone (repos/) → daily article via Claude CLI → MD files in Dir.mktmpdir

Phase 2a: rake import:picoruby_trunk DIR=xxx APP_ENV=test
  → MD files → SQLite (db/ruby_knowledge_test.db)

Phase 2b: rake esa:picoruby_trunk DIR=xxx APP_ENV=test
  → article MD files → esa API (team: bist, category: test/picoruby/trunk-changes, wip: true)
```

**Tech Stack:** Ruby 4.0.1, rake, test-unit, sqlite3, esa API, claude CLI

---

## Context (前セッションからの引き継ぎ)

### 実装済み（全 push 済み）

| リポジトリ | 状態 |
|---|---|
| trunk-changes-diary | TrunkChangesCollector (daily grouping, --shallow-since, --submodule=short) |
| picoruby/mruby/cruby-trunk-changes-generator | self-managed repos/, setup in collect, CLONE_URL |
| rurema-collector | 実装済み |
| picoruby-docs-collector | 実装済み |
| ruby-knowledge-db | generate/import/esa rake tasks, APP_ENV config, EsaWriter |

### 重要な設計仕様

- **1日 = 1記事**: その日の全コミットをまとめて daily article 1本生成
- **SINCE/BEFORE**: 半開区間 [since, before)。`SINCE=2026-04-01 BEFORE=2026-04-04` → Apr 1, 2, 3 の 3 記事
- **APP_ENV**: デフォルト development。production は明示必要。
- **tmpdir**: `Dir.mktmpdir` でステージング。Phase 1 完了時に `DIR=xxx` を表示。
- **MD ファイル名**: `YYYY-MM-DD-diff.md` / `YYYY-MM-DD-article.md`（日単位）

### ENV 設定

| APP_ENV | DB | esa team | esa wip |
|---|---|---|---|
| development | db/ruby_knowledge_development.db | bist | true |
| test | db/ruby_knowledge_test.db | bist | true |
| production | db/ruby_knowledge.db | bash-trunk-changes | false |

### 既知の状況

- picoruby/picoruby は `picoruby-trunk-changes-generator/repos/picoruby/` に shallow clone 済み（209MB）
- 2026-04-05 に 3 コミットあり（4721ec86, 8903b99c, ffd6b588）
- 2026-04-04 にも 1 コミットあり（82b1c900）
- esa token は keychain に `esa-mcp-token` として保存済み

---

## Task 1: Phase 1 実行 (generate)

**Files:** `ruby-knowledge-db/Rakefile` (generate:picoruby_trunk)

- [ ] **Step 1: Phase 1 実行**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-knowledge-db
APP_ENV=test SINCE=2026-04-05 BEFORE=2026-04-06 bundle exec rake generate:picoruby_trunk
```

Expected output:
```
Generated 2 records
DIR=/var/folders/.../picoruby_trunk_..._2026-04-05_2026-04-06
```
2 records = diff 1本 + article 1本（Apr 5 の全コミットまとめ）

- [ ] **Step 2: 生成ファイル確認**

```bash
ls -la $DIR
# 期待: 2026-04-05-diff.md, 2026-04-05-article.md の 2 ファイル
```

- [ ] **Step 3: article 内容確認**

```bash
cat $DIR/2026-04-05-article.md
```

期待: 日本語ですます調、Apr 5 の 3 コミット（4721ec86, 8903b99c, ffd6b588）をまとめた記事

- [ ] **Step 4: diff サイズ確認**

```bash
ls -lh $DIR/2026-04-05-diff.md
# 期待: --submodule=short により数十KB程度（66MB ではないこと）
```

- [ ] **Step 5: 問題があれば修正してコミット**

---

## Task 2: Phase 2a 実行 (import to SQLite)

**Files:** `ruby-knowledge-db/Rakefile` (import:picoruby_trunk)

- [ ] **Step 1: Phase 2a 実行**

```bash
DIR=<Task 1 で出力された DIR パス>
APP_ENV=test DIR=$DIR bundle exec rake import:picoruby_trunk
```

Expected:
```
import picoruby_trunk: stored=2, skipped=0
```

- [ ] **Step 2: DB 確認**

```bash
bundle exec ruby -e "
require 'bundler/setup'
require 'ruby_knowledge_store'
db = File.expand_path('db/ruby_knowledge_test.db')
require 'sqlite3'
db = SQLite3::Database.new(db)
rows = db.execute('SELECT id, source, substr(content,1,80) FROM memories ORDER BY id DESC LIMIT 5')
rows.each { |r| puts r.inspect }
"
```

- [ ] **Step 3: 2回目実行で skipped になること（冪等性確認）**

```bash
APP_ENV=test DIR=$DIR bundle exec rake import:picoruby_trunk
# 期待: stored=0, skipped=2
```

---

## Task 3: Phase 2b 実行 (post to esa)

**Files:** `ruby-knowledge-db/Rakefile` (esa:picoruby_trunk), `lib/ruby_knowledge_db/esa_writer.rb`

- [ ] **Step 1: Phase 2b 実行**

```bash
APP_ENV=test DIR=$DIR bundle exec rake esa:picoruby_trunk
```

Expected:
```
Posted: #NNN bist/test/picoruby/trunk-changes/...
esa picoruby_trunk: posted=1
```

- [ ] **Step 2: esa で確認**

esa の `bist` チーム → `test/picoruby/trunk-changes` カテゴリに WIP 記事が作成されていること

- [ ] **Step 3: 問題があれば EsaWriter を修正してコミット**

---

## Task 4: 複数日テスト

- [ ] **Step 1: 2日分テスト**

```bash
APP_ENV=test SINCE=2026-04-04 BEFORE=2026-04-06 bundle exec rake generate:picoruby_trunk
```

Expected:
```
Generated 4 records
DIR=...
```
4 records = (Apr 4: diff+article) + (Apr 5: diff+article)

- [ ] **Step 2: 生成ファイル確認**

```bash
ls $DIR
# 期待: 2026-04-04-diff.md, 2026-04-04-article.md, 2026-04-05-diff.md, 2026-04-05-article.md
```

---

## Task 5: commit & push

全タスク完了後、変更があればコミット・push。
