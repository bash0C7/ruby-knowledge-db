# ruby-knowledge-db

PicoRuby / CRuby / mruby / rurema のナレッジを SQLite に集約するオーケストレーションリポジトリ。

## 思想

- **DBを作る側** — このリポジトリの責務。読ませる側は `chiebukuro_mcp` gem が担う
- **SQLQL** — yancya 発案。ツール1本（query）、SQL 直渡し、readonly: true
- **セマンティック検索** — 768次元ベクトル（ruri-v3-310m-onnx）で自然言語クエリ対応

## 現在の DB 状態

| ソース | 件数 | 収集方法 |
|--------|------|---------|
| rurema/doctree:ruby3.3 | ~1,559 | BitClust::RRDParser |
| picoruby/picoruby:docs | ~177 | RBS + README |
| picoruby/picoruby:trunk/article | ~77 | MD ファイル手動 import |

## 構成

```
gems/
├── chiebukuro_mcp/        # SQLite MCP サーバー（query + semantic_search）
├── ruby_knowledge_store/  # SQLite 書き込み・スキーマ管理・Embedder
├── picoruby_trunk/        # picoruby/picoruby trunk 収集
├── cruby_trunk/           # ruby/ruby trunk 収集
├── mruby_trunk/           # mruby/mruby trunk 収集
├── rurema/                # rurema/doctree RD パース（BitClust）
└── picoruby_docs/         # PicoRuby RBS + README 収集
```

## セットアップ

```bash
rbenv local 4.0.1
bundle config set --local path 'vendor/bundle'
bundle install
```

## 使い方

```bash
# DB 更新（差分: since は db/last_run.yml から自動取得）
bundle exec ruby scripts/update_all.rb

# 指定日時以降を強制再取得
bundle exec ruby scripts/update_all.rb 2026-01-01T00:00:00+09:00

# MD ファイル一括 import（picoruby trunk 変更記事等）
bundle exec ruby scripts/import_md_files.rb <dir> [source]

# MCP サーバー起動
bundle exec ruby bin/serve
```

## MCP 登録

```bash
# Claude Code（ユーザーワイド）
claude mcp add-json chiebukuro-mcp \
  '{"command":"bundle","args":["exec","ruby","bin/serve"],"cwd":"/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db"}' \
  --scope user

# Claude Desktop: claude_desktop_config.json に以下を追加
# "chiebukuro-mcp": { "command": "/path/to/ruby-knowledge-db/scripts/start_mcp.sh" }
```

## MCP ツール

| ツール | 説明 |
|--------|------|
| `semantic_search` | 自然言語 → vec0 KNN（768次元 ruri-v3）|
| `query` | SQL SELECT（読み取り専用）|
| `schema://database` | スキーマ説明リソース |

## DB スキーマ

`migrations/001_schema.sql` 参照。`_sqlite_mcp_meta` テーブルにスキーマ説明文を同居管理。

## テスト

```bash
bundle exec rake test   # 全テスト一括（52件）
```
