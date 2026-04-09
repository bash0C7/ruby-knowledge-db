# CLAUDE.md — ruby-knowledge-db

## プロジェクト概要

Ruby エコシステム（PicoRuby / CRuby / mruby / rurema）のナレッジを SQLite に集約するオーケストレーションリポジトリ。

- **言語:** Ruby（Python 絶対禁止）
- **DB:** SQLite3 + sqlite-vec（FTS5 trigram + vec0 768次元）
- **埋め込みモデル:** `mochiya98/ruri-v3-310m-onnx`（informers gem、ONNX、VECTOR_SIZE=768）
- **MCP SDK:** `mcp` gem（modelcontextprotocol/ruby-sdk）— koicさんがコミッター、信頼できる正統派
- **テスト:** test-unit xUnit スタイル（t-wada スタイル TDD）

---

## アーキテクチャ全体像

```
【このリポジトリ】ruby-knowledge-db
  ├── ../chiebukuro-mcp/                      MCP サーバー（query + semantic_search）
  ├── ../ruby-knowledge-store/                Store / Embedder / Migrator
  ├── ../picoruby-trunk-changes-generator/    trunk-changes-diary をライブラリとして使用
  ├── ../cruby-trunk-changes-generator/
  ├── ../mruby-trunk-changes-generator/
  ├── ../rurema/                              bitclust-core で RD パース（実装済み）
  └── ../picoruby-docs/                       RBS + README 収集（実装済み）
  ├── lib/ruby_knowledge_db/
  │   └── orchestrator.rb    全ソース一括更新
  ├── scripts/
  │   ├── update_all.rb      手動実行エントリポイント（since 永続化: db/last_run.yml）
  │   ├── import_md_files.rb MD ファイル一括 import（picoruby trunk 変更記事等）
  │   └── start_mcp.sh       Claude Desktop 用起動スクリプト
  └── db/
      ├── ruby_knowledge.db  本番 DB（git 管理外）
      └── last_run.yml       since 永続化（コレクタークラス名 → 最終実行時刻）
```

---

## Collector の統一インターフェース

各 in-project gem はこのインターフェースに従う：

```ruby
module PicorubyTrunk  # または CrubyTrunk, Rurema 等
  class Collector
    SOURCE = "picoruby/picoruby:trunk"  # source カラムの値

    def initialize(config)
      # config: Hash（repo_path, work_dir 等）
    end

    # @param since [String, nil] ISO8601 — 前回実行時刻。nil なら全件
    # @return [Array<Hash>] [{content: String, source: String}, ...]
    def collect(since: nil)
      ...
    end
  end
end
```

---

## DB スキーマ設計

### memories テーブル

```sql
CREATE TABLE memories (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  content      TEXT    NOT NULL,
  source       TEXT    NOT NULL,
  content_hash TEXT    NOT NULL UNIQUE,
  embedding    BLOB,
  created_at   TEXT    NOT NULL
);
CREATE VIRTUAL TABLE memories_fts  USING fts5(content, content='memories', content_rowid='id', tokenize='trigram');
CREATE VIRTUAL TABLE memories_vec  USING vec0(memory_id INTEGER PRIMARY KEY, embedding FLOAT[768]);
```

### source 値の規約

| source 値 | 内容 |
|-----------|------|
| `picoruby/picoruby:trunk/article` | PicoRuby trunk 変更記事（AI 生成 or MD import）|
| `picoruby/picoruby:trunk/diff` | PicoRuby trunk 生 diff |
| `picoruby/picoruby:trunk/article/{submodule}` | PicoRuby submodule 変更記事 |
| `ruby/ruby:trunk/article` | CRuby trunk 変更記事 |
| `mruby/mruby:trunk/article` | mruby trunk 変更記事 |
| `rurema/doctree:ruby4.0/{lib}` | るりま Ruby 4.0 ライブラリドキュメント |
| `rurema/doctree:ruby4.0/{lib}#{class}` | るりま Ruby 4.0 クラスドキュメント |
| `picoruby/picoruby:docs/{gem}` | PicoRuby gem RBS + README |

---

## 依存する外部リポジトリ

| リポジトリ | ローカルパス | 使い方 |
|-----------|------------|--------|
| trunk-changes-diary | `../trunk-changes-diary` | TrunkChanges クラス |
| rurema/doctree | `~/dev/src/github.com/rurema/doctree` | RD ファイル収集対象 |
| picoruby/picoruby | `~/dev/src/github.com/picoruby/picoruby` | docs 収集対象 |

---

## 開発ルール

### 言語・依存
- Python（`python3`、`.py`、`pip`）絶対禁止
- gems はプロジェクト配下に閉じる: `bundle config set --local path 'vendor/bundle'`
- すべての Ruby コマンドは `bundle exec` 経由で実行する

### TDD
- Red → Green → Refactor の順を守る
- テストファイルは絶対に削除しない
- 実モデル（ONNX）はテストで起動しない（StubEmbedder 使用）
- ruby-knowledge-db テスト: `bundle exec rake test`
- trunk-changes-diary テスト: `cd ../trunk-changes-diary && rake test`（bundler 不要）

### git
- conventional commits スタイル（`feat:` / `fix:` / `test:` / `chore:` / `docs:`）
- コミットメッセージは英語
- `.claude/` ディレクトリの内容も必ずコミットに含める

### スコープ規律
- 指示されたファイル以外は変更しない
- スコープ外の変更が必要な場合はユーザーに確認してから行う

---

## 重要な実装メモ

### sqlite-vec の require
```ruby
require 'sqlite_vec'   # アンダースコア（ハイフンではない）
```

### content_hash による冪等性
`Digest::SHA256.hexdigest(content)` を UNIQUE INDEX で管理。同一内容の二重保存は DB 層で自動スキップ。

### vec0 KNN クエリ構文
```sql
SELECT m.content, m.source, v.distance
FROM memories_vec v
JOIN memories m ON m.id = v.memory_id
WHERE v.embedding MATCH ? AND k = ?
ORDER BY v.distance
```

### 3 フェーズパイプライン（trunk-changes）

trunk 変更記事の生成・格納・投稿は 3 フェーズに分離:

```bash
# Phase 1: generate — full clone（/tmp キャッシュ）→ 時系列 diff → Claude CLI で daily article + submodule article 生成
APP_ENV=test SINCE=2026-04-05 BEFORE=2026-04-06 bundle exec rake generate:picoruby_trunk
# → DIR=... が出力される（tmpdir パス）

# Phase 2a: import — MD → SQLite（content_hash で冪等）
APP_ENV=test DIR=$DIR bundle exec rake import:picoruby_trunk

# Phase 2b: esa — article MD → esa API（WIP 記事投稿）
APP_ENV=test DIR=$DIR bundle exec rake esa:picoruby_trunk
```

- SINCE/BEFORE: 半開区間 `[since, before)`。1日分なら `SINCE=2026-04-05 BEFORE=2026-04-06`
- Claude CLI は sonnet モデルを使用（trunk-changes-diary のデフォルト）
- MD ファイル名: `YYYY-MM-DD-diff.md` / `YYYY-MM-DD-article.md` / `YYYY-MM-DD-article-{submodule}.md`
- import 対象: article + diff 全ファイルが DB に格納される。esa には article のみ投稿（`*-article.md` マッチ）

### rake daily（日次一括処理）

```bash
# 昨日分を自動処理（SINCE=昨日, BEFORE=今日 を自動設定）
APP_ENV=production bundle exec rake daily

# 特定日を指定
APP_ENV=production SINCE=2026-04-10 BEFORE=2026-04-11 bundle exec rake daily
```

全 `_trunk` ソース（picoruby/cruby/mruby）を順次 generate → import → esa 投稿。Store は共有して1回だけ開く。

### esa フルパスルール

記事は決定論的なフルパスで投稿:
```
{category}/{yyyy}/{mm}/{dd}/{yyyy-mm-dd}-{short_name}-trunk-changes
```
例: `production/picoruby/trunk-changes/2026/04/08/2026-04-08-picoruby-trunk-changes`

- `short_name`: sources.yml のキーから `_trunk` を除去（`picoruby_trunk` → `picoruby`）
- `category`: `config/environments/{APP_ENV}.yml` の `esa.sources.{key}.category`

### 記事見出しフォーマット（必須）

通常コミット: `### [変更内容タイトル](https://github.com/repo/commit/hash) 日時`
submodule: `### (submodule名)[submodule GitHub URL] [変更内容タイトル](コミットURL) 日時`

### APP_ENV

| APP_ENV | DB | esa team | esa wip |
|---|---|---|---|
| development（デフォルト） | db/ruby_knowledge_development.db | bist | true |
| test | db/ruby_knowledge_test.db | bist | true |
| production | db/ruby_knowledge.db | bash-trunk-changes | false |

環境設定: `config/environments/{APP_ENV}.yml`

### diff 生成方式（trunk-changes-diary）

- **full clone**: `/tmp/trunk-changes-repos/` にキャッシュ。`--no-single-branch` で全ブランチ取得
- **時系列 diff**: `git diff --ignore-submodules prev_hash..hash` で前コミットとの差分。`last_commit_before(date, branch)` で起点取得
- **merge commit**: `is_merge?` フラグ + `merge_log` でコミット一覧付与。PR 全体をまとめて解説する記事を生成
- **submodule 記事**: `git submodule update --init --depth=1` で clone。`submodule_changes` で SHA range 取得、`submodule_log` + `submodule_diff_stat` を Claude CLI に渡して個別記事生成
- source: `picoruby/picoruby:trunk/article/{submodule_name}`

### since 永続化
`db/last_run.yml` にコレクタークラス名をキーとして最終実行時刻を保存。
`scripts/update_all.rb` が自動読み書き。ARGV[0] で手動上書き可能。

### MD ファイル import（picoruby trunk）
```bash
bundle exec ruby scripts/import_md_files.rb <dir> [source]
# YAML フロントマター除去 + content_hash 重複スキップ
# ファイル名パターン: YYYY-MM-DD.md のみ（重複ファイル自動除外）
```

### FTS5 の日本語対応
`tokenize='trigram'` を使用（3文字以上の部分一致）。2文字以下の検索語は FTS5 にヒットしない。

### 埋め込みバイナリ
```ruby
embedding.pack("f*")   # float 配列 → blob
```

---

## ファイル構成と責務

| ファイル/ディレクトリ | 責務 |
|-------------------|------|
| `../chiebukuro-mcp/` | MCP サーバー（query / semantic_search ツール、schema リソース）|
| `../ruby-knowledge-store/` | Store（write）/ Embedder（ruri-v3）/ Migrator |
| `config/sources.yml` | trunk-changes 収集対象リポジトリ設定（`*_trunk` キーから Rake タスク自動生成）|
| `../rurema/` | rurema doctree RD パース（BitClust::RRDParser）|
| `../picoruby-docs/` | PicoRuby RBS + README 収集 |
| `lib/ruby_knowledge_db/orchestrator.rb` | 全ソース一括更新オーケストレーション |
| `../ruby-knowledge-store/migrations/001_schema.sql` | memories + FTS5 + vec0 + _sqlite_mcp_meta |
| `config/chiebukuro.json.example` | DB 接続設定テンプレート（実設定は `~/chiebukuro-mcp/chiebukuro.json` へ）|
| `config/sources.yml` | 収集対象リポジトリ設定 |
| `scripts/update_all.rb` | 手動実行エントリポイント（since 永続化）|
| `scripts/import_md_files.rb` | MD ファイル一括 import |
| `scripts/start_mcp.sh` | MCP 起動スクリプト（SCRIPT_DIR 相対パス、環境非依存）|
| `bin/serve` | MCP サーバー起動（`~/chiebukuro-mcp/chiebukuro.json` 優先ロード）|
| `db/last_run.yml` | since 永続化ファイル（git 管理外）|
| `test/test_helper.rb` | StubEmbedder + 共通セットアップ |
