# TODO — ruby-knowledge-db

## 次セッションでやること

### 総合運転（最優先）

- [ ] `bundle exec ruby scripts/update_all.rb` を実際に実行して動作確認
  - picoruby/picoruby, ruby/ruby, mruby/mruby のローカルクローンが必要
  - `config/sources.yml` の `repo_path` を実際のパスに合わせる
- [ ] `bin/serve` を起動して MCP クライアントから接続確認
  - `query` ツールで SELECT が通るか
  - `schema` リソースで `_sqlite_mcp_meta` の内容が返るか

### Phase 3c: rurema Collector

- [ ] `gems/rurema/` 実装
  - `bitclust-core` を使って rurema/doctree の RD ファイルをパース
  - SOURCE = `rurema/doctree:ruby{version}`
  - rurema/doctree リポジトリのローカルパスを `config/sources.yml` に追加
  - 調査: `require 'bitclust/rdcompiler'` 等でどのクラスを使うか確認

- [ ] `gems/picoruby_docs/` 実装
  - picoruby/picoruby リポジトリで rake を実行してドキュメント生成
  - 調査: picoruby の Rakefile でドキュメント生成コマンドを特定
  - SOURCE = `picoruby/picoruby:docs`

### MCP サーバー提供（ローカル／リモート区別）

#### ローカル MCP サーバー（stdio transport）

- [ ] **導入スキル作成**（`~/.claude/skills/chiebukuro-mcp-local.md`）
  - Claude Code の `mcpServers` 設定への追加手順を自動化するスキル
  - `~/.claude/settings.json` または `.claude/settings.local.json` への書き込み
  - `command: bundle exec ruby bin/serve` + `cwd` を自動設定
  - `superpowers:writing-skills` スキルを使って作成する

#### リモート MCP サーバー（Streamable HTTP）

- [ ] `chiebukuro_mcp` に HTTP transport を追加
  - `stateless: true` でリクエストごとに DB を開閉
  - Rack + Puma でサーブ
  - `bin/serve_http` エントリポイント追加
  - 参考: mcp gem の `MCP::Server::Transports::RackTransport` 等を確認

### インフラ

- [ ] cron 設定（`scripts/update_all.rb` を定期実行）
  - 例: `0 6 * * * cd /path/to/ruby-knowledge-db && bundle exec ruby scripts/update_all.rb`
  - `since` 引数の管理（前回実行時刻をファイルに保存するか検討）

### 改善検討

- [ ] `since` の永続化
  - 現在は ARGV[0] で手渡し
  - `db/last_run.txt` に前回実行時刻を保存する仕組みを `update_all.rb` に追加

- [ ] mruby-c 対応
  - `gems/mruby_c_trunk/` — mruby-c/mruby-c のリポジトリ名確認後に追加
  - SOURCE = `mruby-c/mruby-c:trunk`

- [ ] エラー通知
  - Orchestrator の `results[:errors]` を Slack 等に飛ばす

---

## アーキテクチャメモ（別セッション向け）

```
# DB 更新（書き込み側）
bundle exec ruby scripts/update_all.rb [ISO8601]

# MCP サーバー起動（読み取り側）
bin/serve

# テスト全実行
bundle exec ruby -Itest test/test_orchestrator.rb
bundle exec ruby -Itest gems/ruby_knowledge_store/test/test_ruby_knowledge_store.rb
bundle exec ruby -Itest gems/chiebukuro_mcp/test/test_chiebukuro_mcp.rb
bundle exec ruby -Itest gems/picoruby_trunk/test/test_picoruby_trunk.rb
bundle exec ruby -Itest gems/cruby_trunk/test/test_cruby_trunk.rb
bundle exec ruby -Itest gems/mruby_trunk/test/test_mruby_trunk.rb
```

## 関連リポジトリ

| リポジトリ | パス | 用途 |
|---|---|---|
| trunk-changes-diary | `../trunk-changes-diary` | GitOps, ContentGenerator |
| picoruby/picoruby | `~/dev/src/github.com/picoruby/picoruby` | Collector 対象 |
| ruby/ruby | `~/dev/src/github.com/ruby/ruby` | Collector 対象 |
| mruby/mruby | `~/dev/src/github.com/mruby/mruby` | Collector 対象 |
| rurema/doctree | 要クローン | Collector 対象（Phase 3c） |
