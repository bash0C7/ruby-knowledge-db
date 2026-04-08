# 引き継ぎプロンプト — merge commit-aware diff generation

## 作業ディレクトリ
`~/dev/src/github.com/bash0C7/ruby-knowledge-db`

## やること
`docs/superpowers/plans/2026-04-09-merge-commit-aware-diff.md` のプランに従って実装を進めてください。
`superpowers:subagent-driven-development` スキルを使ってください。

---

## 前セッションで完了したこと

### E2E 検証（Apr 5 単日）— 成功
- Phase 1: `Generated 2 records`、diff 14KB、article 3.3KB ✅
- Phase 2a: `stored=2, skipped=0`、冪等性 `stored=0, skipped=2` ✅
- Phase 2b: esa #239 投稿成功（bist/test/picoruby/trunk-changes/）✅

### 既にコミット・push 済みの修正（trunk-changes-diary）

1. `992de16` — `setup` の shallow-since を -1 day に
2. `42f7311` — `show` を `--ignore-submodules`、`submodule_updates` を分離
3. `d73deb5` — `show` を `git diff parent..hash` に変更（shallow boundary 対策）

### ruby-knowledge-db 側のコミット済み修正

- `5f55e15` — `YAML.safe_load` に `permitted_classes: [Date]` 追加

### 残っている問題

**merge commit（Apr 4 の `82b1c900`）で diff が 63MB になる**
- 原因: merge commit の `M^1`（main 側親 `5c3668ea`）が shallow clone に含まれない
- `git diff parent..hash` の修正だけでは不十分
- → **merge commit 対応の新設計が必要**（今回のプランの主題）

---

## 設計方針

- **merge commit**: `M^1..M` の diff で PR 全体の変更を1記事にまとめる
- **non-merge commit**: 従来通り個別 diff
- **shallow-since**: `-2 day` に拡大
- **プロンプト**: merge commit にはコミット一覧を付与し「PR 全体として解説」を指示
- **submodule**: `--ignore-submodules` で除外（将来別コンテキストで実装予定）

---

## Task 一覧

1. **Task 1**: `GitOps#is_merge?` と `GitOps#merge_log` を追加
2. **Task 2**: `GitOps#show` を merge commit 対応に書き換え
3. **Task 3**: shallow-since を -2 day に拡大
4. **Task 4**: `TrunkChangesCollector#build_context` に merge 情報追加
5. **Task 5**: `ContentGenerator#build_daily_prompt` にマージ情報セクション追加
6. **Task 6**: E2E 再検証（Apr 4-5 複数日テスト）
7. **Task 7**: 全リポジトリ commit & push

---

## 関連リポジトリ

| リポジトリ | ローカルパス | 役割 |
|---|---|---|
| trunk-changes-diary | `~/dev/src/github.com/bash0C7/trunk-changes-diary` | Task 1-5 の実装対象 |
| ruby-knowledge-db | `~/dev/src/github.com/bash0C7/ruby-knowledge-db` | Task 6-7、Rakefile |
| picoruby-trunk-changes-generator | `~/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator` | path gem 経由で trunk-changes-diary を使用 |

---

## 検証コマンド

```bash
# trunk-changes-diary テスト
cd ~/dev/src/github.com/bash0C7/trunk-changes-diary
rake test

# E2E Phase 1（複数日）
cd ~/dev/src/github.com/bash0C7/ruby-knowledge-db
APP_ENV=test SINCE=2026-04-04 BEFORE=2026-04-06 bundle exec rake generate:picoruby_trunk

# E2E Phase 2a
APP_ENV=test DIR=$DIR bundle exec rake import:picoruby_trunk
```
