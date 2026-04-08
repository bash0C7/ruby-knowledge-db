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

## Context（前セッションからの引き継ぎ）

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

### 既知の状況（2026-04-08 調査済み）

- picoruby/picoruby は `picoruby-trunk-changes-generator/repos/picoruby/` に shallow clone 済み（209MB）
- **2026-04-05 に 3 コミットあり**（8903b99c, 4721ec86, ffd6b588）
- **2026-04-04 にも 1 コミットあり**（82b1c900）
- **2026-04-06 にも 4 コミットあり**（684d4d3a, f13b5223, e43851a7, 8dedae7e）
- esa token は keychain に `esa-mcp-token` として保存済み

---

## 重要なバグ調査結果（2026-04-08 発見）

### 問題: `Generated 0 records` になる

**原因:** `git clone --shallow-since=SINCE_DATE` の挙動バグ

`8dedae7e`（Apr 6 merge commit）は親2に `8903b99c`（Apr 5）を持つが、
`--shallow-since=2026-04-05` だと `8dedae7e` 自体が `.git/shallow` に入ってしまい、
Apr 5 コミットが `git log master --after=... --before=...` で辿れなくなる。

**実証:**
- `--shallow-since=2026-04-05` → `8dedae7e` が shallow → Apr 5 **見えない**
- `--shallow-since=2026-04-04` → `8dedae7e` が shallow 外 → Apr 5 **見える** ✅

**修正:** `trunk-changes-diary/trunk_changes.rb` の `GitOps#setup` で `since_date - 1` を使う

```ruby
# 修正済みコード（未 push）
if since_date
  shallow_date = (Date.parse(since_date) - 1).strftime('%Y-%m-%d')
  shallow_opt  = "--shallow-since=#{shallow_date}"
else
  shallow_opt = "--depth=100"
end
```

**修正ファイル:** `~/dev/src/github.com/bash0C7/trunk-changes-diary/trunk_changes.rb` の `setup` メソッド（line 15 付近）

**この修正は git には未 push。テスト後にコミット・push が必要。**

### 追加の状態: repos/picoruby の `.git/shallow` 汚染

`.git/shallow` に存在しないオブジェクトが 4 件あった（既に手動で削除済み）:
- 削除済み: `2eb91b999`, `96478c91`, `9b0fa5ff`, `c0aee14f`
- 現在の `.git/shallow` は有効なエントリのみ（6件）

---

## Task 1: trunk-changes-diary のテストを通す

**Files:** `~/dev/src/github.com/bash0C7/trunk-changes-diary/trunk_changes.rb`（修正済み、未コミット）

- [ ] **Step 1: テスト実行**

```bash
cd ~/dev/src/github.com/bash0C7/trunk-changes-diary
bundle exec rake test
```

期待: 全テスト green（修正が既存テストを壊していないこと）

- [ ] **Step 2: 問題があれば修正**

- [ ] **Step 3: コミット（trunk-changes-diary）**

```bash
cd ~/dev/src/github.com/bash0C7/trunk-changes-diary
git add trunk_changes.rb
git commit -m "fix: subtract 1 day from since_date for shallow-since to include merge-commit parents"
git push
```

---

## Task 2: Phase 1 実行 (generate:picoruby_trunk)

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
head -50 $DIR/2026-04-05-article.md
```

期待: 日本語ですます調、Apr 5 の 3 コミット（8903b99c, 4721ec86, ffd6b588）をまとめた記事

- [ ] **Step 4: diff サイズ確認**

```bash
ls -lh $DIR/2026-04-05-diff.md
# 期待: --submodule=short により数十KB程度（66MB ではないこと）
```

- [ ] **Step 5: 問題があれば修正してコミット**

---

## Task 3: Phase 2a 実行 (import to SQLite)

**Files:** `ruby-knowledge-db/Rakefile` (import:picoruby_trunk)

- [ ] **Step 1: Phase 2a 実行**

```bash
DIR=<Task 2 で出力された DIR パス>
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
require 'sqlite3'
db = SQLite3::Database.new('db/ruby_knowledge_test.db')
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

## Task 4: Phase 2b 実行 (post to esa)

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

## Task 5: 複数日テスト

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

## Task 6: commit & push（全リポジトリ）

全タスク完了後、変更があればコミット・push。

対象リポジトリ:
- `trunk-changes-diary` （Task 1 でコミット済みのはず）
- `ruby-knowledge-db`（変更あれば）
- `picoruby-trunk-changes-generator`（変更あれば）
