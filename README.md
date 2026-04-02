# ruby-knowledge-db

PicoRuby / CRuby / mruby / rurema のナレッジを SQLite に集約するオーケストレーションリポジトリ。

## 思想

- **DBを作る側** — このリポジトリの責務。読ませる側は `chiebukuro_mcp` gem が担う
- **SQLQL** — yancya 発案。ツール1本（query）、SQL 直渡し、readonly: true
- **1コミット2レコード** — AI生成記事（/article）と生 diff（/diff）を両方保存

## 構成

```
gems/
├── chiebukuro_mcp/        # 汎用 SQLite MCP サーバー（読み取り専用）
├── ruby_knowledge_store/  # SQLite 書き込み・スキーマ管理
├── picoruby_trunk/        # picoruby/picoruby trunk 収集
├── cruby_trunk/           # ruby/ruby trunk 収集
├── mruby_trunk/           # mruby/mruby trunk 収集
├── rurema/                # rurema/doctree 収集（未実装）
└── picoruby_docs/         # PicoRuby docs 収集（未実装）
```

## セットアップ

```bash
rbenv local 4.0.1
bundle config set --local path 'vendor/bundle'
bundle install
```

## 使い方

```bash
# DB 更新（全件）
bundle exec ruby scripts/update_all.rb

# 差分更新（ISO8601 以降）
bundle exec ruby scripts/update_all.rb 2024-01-01T00:00:00+09:00

# MCP サーバー起動
bin/serve
```

## DB スキーマ

`migrations/001_schema.sql` 参照。`_sqlite_mcp_meta` テーブルにスキーマ説明文を同居管理。

## テスト

```bash
bundle exec ruby -Itest test/test_orchestrator.rb
bundle exec ruby -Itest gems/ruby_knowledge_store/test/test_ruby_knowledge_store.rb
bundle exec ruby -Itest gems/chiebukuro_mcp/test/test_chiebukuro_mcp.rb
bundle exec ruby -Itest gems/picoruby_trunk/test/test_picoruby_trunk.rb
bundle exec ruby -Itest gems/cruby_trunk/test/test_cruby_trunk.rb
bundle exec ruby -Itest gems/mruby_trunk/test/test_mruby_trunk.rb
```
