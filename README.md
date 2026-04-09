# ruby-knowledge-db

PicoRuby / CRuby / mruby / rurema のナレッジを SQLite に集約するオーケストレーションリポジトリ。

## 思想

- **DBを作る側** — このリポジトリの責務。読ませる側は `chiebukuro_mcp` gem が担う
- **SQLQL** — yancya 発案。ツール1本（query）、SQL 直渡し、readonly: true
- **セマンティック検索** — 768次元ベクトル（ruri-v3-310m-onnx）で自然言語クエリ対応

## DB ソース一覧

| ソース | 収集方法 |
|--------|---------|
| rurema/doctree:ruby4.0 | BitClust::RRDParser |
| picoruby/picoruby:docs | RBS + README |
| picoruby/picoruby:trunk/article | 3フェーズパイプライン（generate → import） |
| picoruby/picoruby:trunk/diff | 3フェーズパイプライン（generate → import） |
| ruby/ruby:trunk/article | 3フェーズパイプライン（generate → import） |
| mruby/mruby:trunk/article | 3フェーズパイプライン（generate → import） |

## 構成

このリポジトリはオーケストレーターで、各機能は個別の gem リポジトリに分離されています。

```
~/dev/src/github.com/bash0C7/
├── ruby-knowledge-db/                  # このリポジトリ（オーケストレーター）
├── chiebukuro-mcp/                     # SQLite MCP サーバー（query + semantic_search）
├── ruby-knowledge-store/               # SQLite 書き込み・スキーマ管理・Embedder
├── trunk-changes-diary/                # Git diff 取得・Claude CLI 記事生成エンジン
├── rurema-collector/                   # rurema/doctree RD パース（BitClust）
└── picoruby-docs-collector/            # PicoRuby RBS + README 収集
```

trunk-changes（picoruby/cruby/mruby）の収集対象は `config/sources.yml` で管理。対象追加は YAML に数行追記するだけ。

## 関連リポジトリ

開発時は以下の gem リポジトリも併せてクローンが必要です。

| リポジトリ | gem名 | 役割 |
|---|---|---|
| [bash0C7/chiebukuro-mcp](https://github.com/bash0C7/chiebukuro-mcp) | `chiebukuro_mcp` | SQLite MCP サーバー |
| [bash0C7/ruby-knowledge-store](https://github.com/bash0C7/ruby-knowledge-store) | `ruby_knowledge_store` | Store / Embedder / Migrator |
| [bash0C7/trunk-changes-diary](https://github.com/bash0C7/trunk-changes-diary) | `trunk_changes_diary` | Git diff 取得・Claude CLI 記事生成エンジン |
| [bash0C7/rurema-collector](https://github.com/bash0C7/rurema-collector) | `rurema_collector` | rurema doctree 収集 |
| [bash0C7/picoruby-docs-collector](https://github.com/bash0C7/picoruby-docs-collector) | `picoruby_docs_collector` | PicoRuby docs 収集 |

別マシンでの初回セットアップ：

```bash
BASE=~/dev/src/github.com/bash0C7
mkdir -p $BASE && cd $BASE
git clone https://github.com/bash0C7/ruby-knowledge-db
git clone https://github.com/bash0C7/chiebukuro-mcp
git clone https://github.com/bash0C7/ruby-knowledge-store
git clone https://github.com/bash0C7/trunk-changes-diary
git clone https://github.com/bash0C7/rurema-collector
git clone https://github.com/bash0C7/picoruby-docs-collector
```

## sources.yml（収集対象設定）

`config/sources.yml` で trunk-changes の収集対象リポジトリを管理。対象追加は YAML に追記するだけ。

```yaml
sources:
  picoruby_trunk:                    # Rake タスク名のキー（*_trunk で自動認識）
    repo: picoruby/picoruby          # GitHub org/repo
    branch: master                   # 対象ブランチ
    clone_url: https://github.com/picoruby/picoruby  # git clone URL
    repo_path: /tmp/trunk-changes-repos/picoruby     # ローカルキャッシュパス
    source_diff: picoruby/picoruby:trunk/diff         # DB の source カラム値（diff）
    source_article: picoruby/picoruby:trunk/article   # DB の source カラム値（article）
    prompt_supplement: "..."         # Claude CLI への追加プロンプト（任意）
```

`*_trunk` で終わるキーから `generate:*`, `import:*`, `esa:*` の Rake タスクが自動生成される。

## セットアップ

```bash
rbenv local 4.0.1
bundle config set --local path 'vendor/bundle'
bundle install
```

## 使い方

### 3 フェーズパイプライン（trunk-changes）

trunk 変更記事の生成は 3 フェーズに分かれています。各フェーズは独立して実行可能です。

```bash
# Phase 1: generate — git clone → daily article 生成（Claude CLI 使用）→ tmpdir に MD 出力
#   SINCE/BEFORE: 半開区間 [since, before)。日単位で記事を生成
#   Claude CLI は sonnet モデルを使用（trunk-changes-diary のデフォルト）
APP_ENV=test SINCE=2026-04-05 BEFORE=2026-04-06 bundle exec rake generate:picoruby_trunk
# => Generated 2 records
# => DIR=/var/folders/.../picoruby_trunk_..._2026-04-05_2026-04-06

# Phase 2a: import — tmpdir の MD を SQLite に格納（content_hash で冪等）
APP_ENV=test DIR=$DIR bundle exec rake import:picoruby_trunk
# => import picoruby_trunk: stored=2, skipped=0

# Phase 2b: esa — tmpdir の article MD を esa に WIP 記事として投稿
APP_ENV=test DIR=$DIR bundle exec rake esa:picoruby_trunk
# => Posted: #NNN test/picoruby/trunk-changes/...
```

picoruby 以外にも `cruby_trunk`, `mruby_trunk` の同名タスクがあります。

**import の対象**: generate で生成される MD ファイル（article + diff）は全て DB に格納される。esa には article のみ投稿（`*-article.md` にマッチするファイルのみ）。diff は DB での検索用途。

### rake daily（日次一括処理）

```bash
# 昨日分を自動処理（SINCE=昨日, BEFORE=今日 を自動設定）
APP_ENV=production bundle exec rake daily

# 特定日を指定
APP_ENV=production SINCE=2026-04-10 BEFORE=2026-04-11 bundle exec rake daily
```

全 `_trunk` ソース（picoruby/cruby/mruby）を順次 generate → import → esa 投稿。Store は共有して1回だけ開く。

### APP_ENV

| APP_ENV | DB | esa team | esa wip | esa category prefix |
|---|---|---|---|---|
| development（デフォルト） | db/ruby_knowledge_development.db | bist | true | development/ |
| test | db/ruby_knowledge_test.db | bist | true | test/ |
| production | db/ruby_knowledge.db | bash-trunk-changes | false | production/ |

### その他のタスク

```bash
# rurema ドキュメント更新
bundle exec rake update:rurema

# PicoRuby docs 更新
bundle exec rake update:picoruby_docs

# DB 一括更新（差分: since は db/last_run.yml から自動取得）
bundle exec ruby scripts/update_all.rb

# 指定日時以降を強制再取得
bundle exec ruby scripts/update_all.rb 2026-01-01T00:00:00+09:00

# MD ファイル一括 import（picoruby trunk 変更記事等）
bundle exec ruby scripts/import_md_files.rb <dir> [source]
```

## 個人設定（~/chiebukuro-mcp/）

DB パスや接続先などの個人環境依存設定はリポジトリとは分離し、`~/chiebukuro-mcp/chiebukuro.json` に置く。

```bash
mkdir -p ~/chiebukuro-mcp
cp config/chiebukuro.json.example ~/chiebukuro-mcp/chiebukuro.json
# パスを自分の環境に合わせて編集
```

### DB ファイルの配置（iCloud Drive 推奨）

`~/chiebukuro-mcp/chiebukuro.json` は dotfiles（iCloud + GitHub）で管理済み。
DB ファイルは大きいため dotfiles とは**別の** iCloud Drive フォルダに置く:

```
~/Library/Mobile Documents/com~apple~CloudDocs/chiebukuro-mcp/db/
  ruby_knowledge.db      # ← 主に読み取り、infrequent 書き込み
  health.db              # ← Apple HealthKit（import スクリプトのみ書き込み）
  # memory.db は long-term-memory リポジトリ配下で直接管理
```

`~/chiebukuro-mcp/chiebukuro.json` の各 `path` をこのパスに更新する。
書き込みが頻繁な DB は同時に複数マシンから書かないこと（SQLite WAL の同期競合リスク）。

## MCP 登録

MCP サーバーの起動は **`chiebukuro-mcp` リポジトリに委譲**。`chiebukuro-mcp/exe/chiebukuro-mcp serve` を使う。

```bash
# Claude Code（ユーザーワイド）
REPO=/path/to/chiebukuro-mcp
claude mcp remove chiebukuro-mcp -s user 2>/dev/null || true
claude mcp add-json chiebukuro-mcp \
  "{\"type\":\"stdio\",\"command\":\"$REPO/exe/chiebukuro-mcp\",\"args\":[\"serve\"]}" \
  --scope user
```

起動前に `~/chiebukuro-mcp/chiebukuro.json` が存在すること（`chiebukuro-mcp` リポジトリの README 参照）。

## MCP ツール

| ツール | 説明 |
|--------|------|
| `chiebukuro_query_<db>` | SQL SELECT（読み取り専用）各 DB ごとに生成 |
| `chiebukuro_semantic_search_<db>` | 自然言語 → vec0 KNN（768次元 ruri-v3）`semantic_search` 設定のある DB のみ |
| `schema://<db>` | スキーマ説明リソース |

## DB スキーマ

`ruby-knowledge-store` リポジトリの `migrations/001_schema.sql` 参照。`_sqlite_mcp_meta` テーブルにスキーマ説明文を同居管理。

## テスト

```bash
bundle exec rake test   # orchestrator テスト
# 各 gem のテストは個別リポジトリで実施
# trunk-changes-diary: cd ../trunk-changes-diary && rake test（bundler 不要）
```
