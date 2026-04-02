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

このリポジトリは「DBを作る・育てる」側。「DBを読ませる」側は別プロジェクト（sqlite-mcp、未実装）。

```
【このリポジトリ】ruby-knowledge-db
  ├── gems/（in-project gems）各ソース固有の収集ロジック
  │   ├── picoruby_trunk/    trunk-changes-diary をライブラリとして使用
  │   ├── cruby_trunk/
  │   ├── mruby_trunk/
  │   ├── rurema/            bitclust をライブラリとして使用（要調査）
  │   └── picoruby_docs/     picoruby repo 内で rake 実行（要調査）
  ├── lib/ruby_knowledge_db/
  │   ├── store.rb           long-term-memory の MemoryStore 薄ラッパー
  │   └── orchestrator.rb    全ソース一括更新
  └── scripts/update_all.rb  cron エントリポイント

【別リポジトリ予定】sqlite-mcp
  DBを読ませる（SQLQL サーバー）
  → ruby_knowledge.db を databases.yml に登録するだけ
  → ローカル: stdio transport（mcp gem）
  → リモート: Streamable HTTP + Rack + Puma（stateless: true）

【既存リポジトリ】long-term-memory（ライブラリとして使用）
  path: ../long-term-memory — MemoryStore クラスを利用

【既存リポジトリ】trunk-changes-diary（ライブラリとして使用）
  path: ../trunk-changes-diary — TrunkChanges クラスを利用
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

### memories テーブル（long-term-memory の MemoryStore と同構造）

```sql
CREATE TABLE memories (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  content      TEXT    NOT NULL,
  source       TEXT    NOT NULL,
  content_hash TEXT    NOT NULL UNIQUE,
  embedding    BLOB,
  created_at   TEXT    NOT NULL
);
CREATE VIRTUAL TABLE memories_fts  USING fts5(content, tokenize='trigram');
CREATE VIRTUAL TABLE memories_vec0 USING vec0(embedding float[768]);
```

### _sqlite_mcp_meta テーブル（SQLQL サーバー用自己記述）

```sql
CREATE TABLE _sqlite_mcp_meta (
  object_type TEXT NOT NULL,  -- 'db' | 'table' | 'column'
  object_name TEXT NOT NULL,
  description TEXT,
  PRIMARY KEY (object_type, object_name)
);
```

### source 値の規約

| source 値 | 内容 |
|-----------|------|
| `picoruby/picoruby:trunk` | PicoRuby trunk 変更履歴 |
| `ruby/ruby:trunk` | CRuby trunk 変更履歴 |
| `mruby/mruby:trunk` | mruby trunk 変更履歴 |
| `mruby-c/mruby-c:trunk` | mruby/c trunk 変更履歴 |
| `rurema/doctree:ruby33` | るりま Ruby 3.3 ドキュメント |
| `picoruby/picoruby:docs` | PicoRuby rake 生成ドキュメント |

---

## 依存する外部リポジトリ

| リポジトリ | ローカルパス | 使い方 |
|-----------|------------|--------|
| long-term-memory | `../long-term-memory` | MemoryStore クラス |
| trunk-changes-diary | `../trunk-changes-diary` | TrunkChanges クラス |

```ruby
# Gemfile
gem 'long_term_memory',      path: '../long-term-memory'
gem 'trunk_changes_diary',   path: '../trunk-changes-diary'

# in-project gems
gem 'picoruby_trunk', path: 'gems/picoruby_trunk'
gem 'rurema',         path: 'gems/rurema'
# ...
```

**注意:** long-term-memory / trunk-changes-diary に gemspec がない場合、`$LOAD_PATH` 操作が必要。gemspec 追加を先に行うこと（PLAN.md Phase 0 参照）。

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

### created_at フォーマット
```ruby
Time.now.iso8601   # RFC 3339
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
| `gems/picoruby_trunk/` | PicoRuby trunk 変更収集（trunk-changes-diary 使用） |
| `gems/cruby_trunk/` | CRuby trunk 変更収集 |
| `gems/mruby_trunk/` | mruby trunk 変更収集 |
| `gems/rurema/` | rurema doctree 取得・RD パース（bitclust 使用） |
| `gems/picoruby_docs/` | PicoRuby rake 生成ドキュメント取得 |
| `lib/ruby_knowledge_db/store.rb` | MemoryStore 薄ラッパー |
| `lib/ruby_knowledge_db/orchestrator.rb` | 全ソース一括更新オーケストレーション |
| `migrations/001_schema.sql` | memories テーブル + FTS5 + vec0 |
| `migrations/002_meta.sql` | _sqlite_mcp_meta テーブル + 初期データ |
| `config/sources.yml` | 収集対象リポジトリ設定 |
| `scripts/update_all.rb` | cron 実行エントリポイント |
| `test/test_helper.rb` | StubEmbedder + 共通セットアップ |

---

## 未解決の論点（実装前に要調査）

1. **long-term-memory / trunk-changes-diary の gemspec 化** — 現状 gemspec がない場合は先に追加が必要
2. **rurema の RD パース** — `bitclust` gem をライブラリとして使えるか確認
3. **PicoRuby docs の rake コマンド** — picoruby repo で何を実行すれば docs が生成されるか確認
4. **mruby-c リポジトリ名** — `mruby-c/mruby-c` か `mruby/mruby-c` か確認
