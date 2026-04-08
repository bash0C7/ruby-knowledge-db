# 引き継ぎプロンプト — ruby-knowledge-db E2E 検証（picoruby-trunk-changes）

## 作業ディレクトリ
`~/dev/src/github.com/bash0C7/ruby-knowledge-db`

## やること
`docs/superpowers/plans/2026-04-08-e2e-verification.md` のプランに従って E2E 検証を進めてください。
`superpowers:subagent-driven-development` スキルを使ってください。

---

## 前セッションで判明したバグと修正状況

### バグ: `Generated 0 records` になる

**根本原因:** `git clone --shallow-since=SINCE_DATE` が merge commit の親を見えなくする

具体的には、`8dedae7e`（Apr 6 merge commit）が `--shallow-since=2026-04-05` のとき
`.git/shallow` に入ってしまい、Apr 5 コミットが `git log master` で辿れなくなる。

**修正済みファイル（未コミット・未 push）:**

```
~/dev/src/github.com/bash0C7/trunk-changes-diary/trunk_changes.rb
```

`GitOps#setup`（line 15 付近）を変更済み:

```ruby
# 修正後
if since_date
  shallow_date = (Date.parse(since_date) - 1).strftime('%Y-%m-%d')  # -1 day
  shallow_opt  = "--shallow-since=#{shallow_date}"
else
  shallow_opt = "--depth=100"
end
```

**まず `bundle exec rake test` を trunk-changes-diary で通してからコミット。**

### repos/picoruby の `.git/shallow` 状態

`~/.../picoruby-trunk-changes-generator/repos/picoruby/.git/shallow` から
無効なエントリ 4 件を手動削除済み。現在は有効な 6 件のみ。

---

## プランの Task 一覧（Task 1 が最優先）

1. **Task 1**: trunk-changes-diary のテストを通してコミット（修正が既存テストを壊していないか確認）
2. **Task 2**: Phase 1 実行 → `Generated 2 records` + `DIR=...` を確認
3. **Task 3**: Phase 2a 実行 → SQLite に `stored=2, skipped=0`、冪等性確認
4. **Task 4**: Phase 2b 実行 → esa に WIP 記事投稿確認
5. **Task 5**: 複数日テスト（SINCE=2026-04-04 BEFORE=2026-04-06 → 4 records）
6. **Task 6**: 全リポジトリ commit & push

---

## 関連リポジトリ（全て `~/dev/src/github.com/bash0C7/` 配下）

| リポジトリ | 役割 |
|---|---|
| `ruby-knowledge-db` | メイン（Rakefile, EsaWriter） |
| `trunk-changes-diary` | GitOps#setup のバグ修正対象 |
| `picoruby-trunk-changes-generator` | Collector gem |
| `ruby-knowledge-store` | Store/Embedder/Migrator |

---

## 検証コマンド早見表

```bash
# Phase 1
cd ~/dev/src/github.com/bash0C7/ruby-knowledge-db
APP_ENV=test SINCE=2026-04-05 BEFORE=2026-04-06 bundle exec rake generate:picoruby_trunk

# Phase 2a（$DIR は Phase 1 の出力から）
APP_ENV=test DIR=$DIR bundle exec rake import:picoruby_trunk

# Phase 2b
APP_ENV=test DIR=$DIR bundle exec rake esa:picoruby_trunk

# 複数日テスト
APP_ENV=test SINCE=2026-04-04 BEFORE=2026-04-06 bundle exec rake generate:picoruby_trunk
```
