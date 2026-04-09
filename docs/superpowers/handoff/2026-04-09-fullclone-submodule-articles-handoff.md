# 引き継ぎプロンプト — Full Clone + Submodule Article Generation

## 作業ディレクトリ
`~/dev/src/github.com/bash0C7/ruby-knowledge-db`

## やること
`docs/superpowers/plans/2026-04-09-fullclone-submodule-articles.md` のプランに従って実装を進めてください。
`superpowers:subagent-driven-development` スキルを使ってください。

---

## 前セッションの成果（既に push 済み）

### trunk-changes-diary
- `992de16` shallow-since -1day
- `42f7311` --ignore-submodules 分離
- `d73deb5` git diff parent..hash 方式
- `191c7b5` is_merge? / merge_log 追加
- `260e583` show: first-parent diff + stat fallback
- `e8ef56e` shallow-since -2day
- `0e170ba` build_context に merge 情報追加
- `1c520ac` daily prompt にマージセクション追加
- `c1975b5` --bare revert（不要だった）

### picoruby/cruby/mruby-trunk-changes-generator
- DEFAULT_REPO_PATH を `/tmp/trunk-changes-repos/` に変更済み
- テスト stub に is_merge?/merge_log 追加済み

### ruby-knowledge-db
- YAML.safe_load に Date 許可
- README.md / CLAUDE.md 更新済み

### E2E 検証結果
- Apr 5 単日: Phase 1-2a-2b 全成功（esa #239 投稿）
- Apr 4-5 複数日: diff 63MB→279B に改善、article 正常

---

## 今回のプランの概要

**2つのフィーチャーを統合実装:**

### Feature B: Full clone + 時系列 diff
- shallow clone → full clone（/tmp キャッシュ）
- git parent → main ブランチ上の時系列前コミントとの diff
- `GitOps#diff(from, to)` + `last_commit_before(date, branch)`
- `TrunkChangesCollector` で prev_hash を追跡

### Feature A: Submodule 記事生成
- `git submodule update --init --depth=1` で submodule clone
- `submodule_changes(hash)` で SHA range 取得
- submodule ごとに Claude CLI で個別記事生成
- source: `picoruby/picoruby:trunk/article/{submodule_name}`

---

## Task 一覧（12タスク）

1. GitOps#setup を full clone に変更
2. GitOps#diff と last_commit_before 追加
3. TrunkChangesCollector を時系列 diff に変更
4. GitOps#submodule_changes 追加（submodule_updates 置換）
5. GitOps#submodule_log と submodule_diff_stat 追加
6. TrunkChangesCollector に submodule 記事生成追加
7. ContentGenerator に submodule プロンプト追加
8. Rakefile の write_md を submodule 対応
9. 3 generator テストの stub 更新
10. 旧コード削除（show の parent lookup、shallow 関連）
11. E2E 検証
12. 全リポジトリ push + CLAUDE.md 更新

---

## 関連リポジトリ

| リポジトリ | ローカルパス |
|---|---|
| trunk-changes-diary | `~/dev/src/github.com/bash0C7/trunk-changes-diary` |
| ruby-knowledge-db | `~/dev/src/github.com/bash0C7/ruby-knowledge-db` |
| picoruby-trunk-changes-generator | `~/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator` |
| cruby-trunk-changes-generator | `~/dev/src/github.com/bash0C7/cruby-trunk-changes-generator` |
| mruby-trunk-changes-generator | `~/dev/src/github.com/bash0C7/mruby-trunk-changes-generator` |

---

## テストコマンド

```bash
# trunk-changes-diary（bundler 不要）
cd ~/dev/src/github.com/bash0C7/trunk-changes-diary && rake test

# ruby-knowledge-db
cd ~/dev/src/github.com/bash0C7/ruby-knowledge-db && bundle exec rake test

# generators
cd ~/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator && bundle exec rake test
cd ~/dev/src/github.com/bash0C7/cruby-trunk-changes-generator && bundle exec rake test
cd ~/dev/src/github.com/bash0C7/mruby-trunk-changes-generator && bundle exec rake test
```
