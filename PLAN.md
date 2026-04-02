# PLAN.md — ruby-knowledge-db 実装計画

## 背景・コンテキスト

このプランは以下の思考実験から生まれた：

- SQLite + WASM をリモート MCP サーバーとして GitHub Pages / Cloudflare Workers から提供できないか
- PicoRuby / mruby/c / CRuby / rurema のナレッジを AI フレンドリーに提供できないか
- trunk-changes-diary の累積出力が自然にナレッジになる
- yancya さん発案の「SQLQL」思想（抽象化せずSQL直渡し）をMCPに適用

**このリポジトリの責務:** DB を作る・育てる（読ませる側は別プロジェクト sqlite-mcp）

---

## 設計上の重要な決定事項

| 決定 | 内容 | 理由 |
|------|------|------|
| MCP gem | `mcp` gem（modelcontextprotocol/ruby-sdk） | koicさんがコミッター、正統派、long-term-memoryと統一 |
| HTTP/SSE | Streamable HTTP 対応済み（stateless: true でリモート可） | fast-mcp の Rails 統合は不要なシンプルな用途 |
| MemoryStore 再利用 | long-term-memory の MemoryStore を path: で参照 | FTS5 + vec0 実装済み、content_hash 冪等性済み |
| in-project gems | gems/ ディレクトリに各ソース固有コレクターを配置 | 独立テスト可能、gemspec で管理 |
| 書き込み専用バッチ | ユーザーは読み取り専用、更新は orchestrator のみ | 誤操作防止、sqlite-mcp は readonly: true で開く |
| _sqlite_mcp_meta | DB 自身がスキーマ説明を持つ | SQLQL 思想、yaml 二重管理を避ける |

---

## Phase 0: 前提条件の確認・整備

### 0-1. long-term-memory の gemspec 確認
- `/Users/bash/dev/src/github.com/bash0C7/long-term-memory/` に gemspec があるか確認
- なければ `long_term_memory.gemspec` を追加（`lib/memory_store.rb` 等を expose）

### 0-2. trunk-changes-diary の gemspec 確認
- `/Users/bash/dev/src/github.com/bash0C7/trunk-changes-diary/` に gemspec があるか確認
- なければ `trunk_changes_diary.gemspec` を追加（`lib/trunk_changes.rb` 等を expose）

### 0-3. rurema / bitclust 調査
- `bitclust` gem が rubygems に存在するか確認（`gem search bitclust`）
- rurema/doctree の RD ファイル構造を確認
- bitclust をライブラリとして `require` できるか確認

### 0-4. PicoRuby docs rake コマンド調査
- `picoruby/picoruby` repo の Rakefile を確認
- ドキュメント生成コマンドを特定

### 0-5. mruby-c リポジトリ名確認
- GitHub で正式な org/repo 名を確認

---

## Phase 1: 基盤セットアップ

### 1-1. git init + Gemfile
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
git init
bundle config set --local path 'vendor/bundle'
```

Gemfile の骨格：
```ruby
source 'https://rubygems.org'

ruby '4.0.1'

gem 'sqlite3'
gem 'sqlite_vec'
gem 'informers'
gem 'test-unit'

# 外部リポジトリをライブラリとして参照
gem 'long_term_memory',    path: '../long-term-memory'
gem 'trunk_changes_diary', path: '../trunk-changes-diary'

# in-project gems
gem 'picoruby_trunk', path: 'gems/picoruby_trunk'
gem 'cruby_trunk',    path: 'gems/cruby_trunk'
gem 'mruby_trunk',    path: 'gems/mruby_trunk'
gem 'rurema',         path: 'gems/rurema'
gem 'picoruby_docs',  path: 'gems/picoruby_docs'
```

### 1-2. DB マイグレーション

`migrations/001_schema.sql`:
```sql
CREATE TABLE IF NOT EXISTS memories (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  content      TEXT    NOT NULL,
  source       TEXT    NOT NULL,
  content_hash TEXT    NOT NULL UNIQUE,
  embedding    BLOB,
  created_at   TEXT    NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts
  USING fts5(content, tokenize='trigram');
CREATE VIRTUAL TABLE IF NOT EXISTS memories_vec0
  USING vec0(embedding float[768]);
```

`migrations/002_meta.sql`:
```sql
CREATE TABLE IF NOT EXISTS _sqlite_mcp_meta (
  object_type TEXT NOT NULL,
  object_name TEXT NOT NULL,
  description TEXT,
  PRIMARY KEY (object_type, object_name)
);

INSERT OR REPLACE INTO _sqlite_mcp_meta VALUES
  ('db',     'db',                          'Ruby エコシステムのナレッジ集約DB'),
  ('table',  'memories',                    'Ruby関連ナレッジの本文・埋め込み・ソース'),
  ('column', 'memories.content',            'ナレッジ本文（Markdown）'),
  ('column', 'memories.source',             'ソース識別子（例: picoruby/picoruby:trunk）'),
  ('column', 'memories.content_hash',       'SHA256ハッシュ（冪等性保証）'),
  ('column', 'memories.embedding',          '768次元ベクトル（float32 blob）'),
  ('column', 'memories.created_at',         '取り込み日時（ISO8601）');
```

### 1-3. test/test_helper.rb
long-term-memory の StubEmbedder を再利用 or コピー。

---

## Phase 2: lib/ruby_knowledge_db/ 実装

### 2-1. store.rb
MemoryStore の薄ラッパー。source フィルタ等、このプロジェクト固有の操作を追加。

```ruby
require 'memory_store'

module RubyKnowledgeDb
  class Store
    def initialize(db_path, embedder:)
      @inner = MemoryStore.new(db_path, embedder: embedder)
    end

    def store(content, source:)
      @inner.store(content, source: source)
    end

    def stats_by_source
      @inner.stats[:by_source]
    end
  end
end
```

### 2-2. orchestrator.rb スケルトン
各 Collector を呼び出して Store に格納する。

```ruby
module RubyKnowledgeDb
  class Orchestrator
    def initialize(store, collectors)
      @store = store
      @collectors = collectors
    end

    def run(since: nil)
      @collectors.each do |collector|
        collector.collect(since: since).each do |chunk|
          @store.store(chunk[:content], source: chunk[:source])
        end
      end
    end
  end
end
```

---

## Phase 3: in-project gems 実装（優先順）

### 優先度高（trunk-changes-diary の資産を最大活用）

#### 3-1. gems/picoruby_trunk/
- `TrunkChanges` クラスを内部で使う
- config から picoruby/picoruby の repo path / pos.json path を受け取る
- SOURCE = "picoruby/picoruby:trunk"

#### 3-2. gems/mruby_trunk/
- 同様の構造、SOURCE = "mruby/mruby:trunk"

#### 3-3. gems/cruby_trunk/
- 同様の構造、SOURCE = "ruby/ruby:trunk"

### 優先度中（調査が必要）

#### 3-4. gems/rurema/
- bitclust 調査結果次第で実装方針決定
- RD ファイルをクラス・メソッド単位でチャンク化
- SOURCE = "rurema/doctree:ruby{version}"

#### 3-5. gems/picoruby_docs/
- picoruby repo での rake コマンド特定後に実装
- SOURCE = "picoruby/picoruby:docs"

---

## Phase 4: Orchestrator 完成 + cron

### 4-1. scripts/update_all.rb
```ruby
#!/usr/bin/env ruby
require_relative '../lib/ruby_knowledge_db'
require 'yaml'

config = YAML.load_file(File.join(__dir__, '../config/sources.yml'))
embedder = Embedder.new  # long-term-memory の Embedder
store = RubyKnowledgeDb::Store.new(config['db_path'], embedder: embedder)

collectors = [
  PicorubyTrunk::Collector.new(config['sources']['picoruby_trunk']),
  MrubyTrunk::Collector.new(config['sources']['mruby_trunk']),
  CrubyTrunk::Collector.new(config['sources']['cruby_trunk']),
  # 調査完了後に追加:
  # Rurema::Collector.new(config['sources']['rurema']),
  # PicorubyDocs::Collector.new(config['sources']['picoruby_docs']),
]

orchestrator = RubyKnowledgeDb::Orchestrator.new(store, collectors)
orchestrator.run(since: ARGV[0])  # 引数で since を渡せる
```

### 4-2. config/sources.yml
```yaml
db_path: db/ruby_knowledge.db

sources:
  picoruby_trunk:
    repo_path: ~/dev/src/github.com/picoruby/picoruby
    pos_path: db/picoruby_trunk_pos.json

  mruby_trunk:
    repo_path: ~/dev/src/github.com/mruby/mruby
    pos_path: db/mruby_trunk_pos.json

  cruby_trunk:
    repo_path: ~/dev/src/github.com/ruby/ruby
    pos_path: db/cruby_trunk_pos.json
```

---

## Phase 5: sqlite-mcp（別リポジトリ）

**このフェーズは ruby-knowledge-db の外で実施。**

SQLQL サーバーの実装：

```
sqlite-mcp/（別リポジトリ）
├── bin/sqlite-mcp
├── lib/sqlite_mcp/
│   ├── registry.rb       # databases.yml 読み込み
│   ├── executor.rb       # readonly: true で SQLite を開く
│   ├── meta.rb           # _sqlite_mcp_meta 読み込み
│   ├── tools/
│   │   └── query_tool.rb # SELECT のみ実行
│   └── resources/
│       └── schema_resource.rb  # _sqlite_mcp_meta 合成スキーマ
└── Gemfile               # gem 'mcp'
```

databases.yml での ruby-knowledge-db 登録：
```yaml
databases:
  ruby_knowledge:
    path: ~/dev/src/github.com/bash0C7/ruby-knowledge-db/db/ruby_knowledge.db
    vec: true
```

---

## 実装順序サマリー

```
Phase 0: 前提確認（gemspec, bitclust, PicoRuby rake, mruby-c）
  ↓
Phase 1: git init + Gemfile + migrations + test_helper
  ↓
Phase 2: store.rb + orchestrator.rb スケルトン
  ↓
Phase 3a: picoruby_trunk gem（trunk-changes-diary 使用）
  ↓
Phase 3b: mruby_trunk, cruby_trunk gems
  ↓
Phase 3c: rurema, picoruby_docs gems（調査結果次第）
  ↓
Phase 4: update_all.rb + config/sources.yml + cron 設定
  ↓
Phase 5: sqlite-mcp 別リポジトリ実装
```

---

## 関連リポジトリ・参考情報

| リポジトリ | パス/URL | 備考 |
|-----------|---------|------|
| long-term-memory | `../long-term-memory` | MemoryStore, Embedder, StubEmbedder |
| trunk-changes-diary | `../trunk-changes-diary` | TrunkChanges クラス |
| modelcontextprotocol/ruby-sdk | https://github.com/modelcontextprotocol/ruby-sdk | mcp gem 本体 |
| rurema/doctree | https://github.com/rurema/doctree | るりま RD ソース |
| picoruby/picoruby | https://github.com/picoruby/picoruby | PicoRuby 本体 |

## yancya SQLQL 思想

> URLにSQLを送信すると、SQL実行結果のJSONが返ってくる

MCP 版 SQLQL：
- ツール 1 本: `query(db:, sql:)` — SELECT のみ、readonly: true で構造的に書き込み拒否
- リソース: `schema/{db_name}` — _sqlite_mcp_meta + sqlite_master の合成
- SQLガードなし — readonly: true 1層で十分
- スキーマはDB自身が持つ（yaml 二重管理なし）
