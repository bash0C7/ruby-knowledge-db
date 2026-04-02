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
| `ruby/ruby:trunk/article` | CRuby trunk 変更記事 |
| `mruby/mruby:trunk/article` | mruby trunk 変更記事 |
| `rurema/doctree:ruby3.3/{lib}` | るりま Ruby 3.3 ライブラリドキュメント |
| `rurema/doctree:ruby3.3/{lib}#{class}` | るりま Ruby 3.3 クラスドキュメント |
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
- 全テスト: `bundle exec rake test`（52件）

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
| `../picoruby-trunk-changes-generator/` | PicoRuby trunk 変更収集（trunk-changes-diary 使用）|
| `../cruby-trunk-changes-generator/` | CRuby trunk 変更収集 |
| `../mruby-trunk-changes-generator/` | mruby trunk 変更収集 |
| `../rurema/` | rurema doctree RD パース（BitClust::RRDParser）|
| `../picoruby-docs/` | PicoRuby RBS + README 収集 |
| `lib/ruby_knowledge_db/orchestrator.rb` | 全ソース一括更新オーケストレーション |
| `../ruby-knowledge-store/migrations/001_schema.sql` | memories + FTS5 + vec0 + _sqlite_mcp_meta |
| `config/sources.yml` | 収集対象リポジトリ設定 |
| `scripts/update_all.rb` | 手動実行エントリポイント（since 永続化）|
| `scripts/import_md_files.rb` | MD ファイル一括 import |
| `scripts/start_mcp.sh` | Claude Desktop 用 MCP 起動スクリプト |
| `bin/serve` | Claude Code 用 MCP サーバー起動 |
| `db/last_run.yml` | since 永続化ファイル（git 管理外）|
| `test/test_helper.rb` | StubEmbedder + 共通セットアップ |
