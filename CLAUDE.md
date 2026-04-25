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
  ├── ../chiebukuro-mcp/             MCP サーバー（query + semantic_search）
  ├── ../ruby-knowledge-store/       Store / Embedder / Migrator
  ├── ../trunk-changes-diary/        Git diff 取得・Claude CLI 記事生成エンジン
  ├── ../rurema-collector/           rurema/doctree RD パース（BitClust::RRDParser）
  ├── ../picoruby-docs-collector/    PicoRuby RBS + README 収集
  ├── ../ruby-rdoc-collector/        ruby/ruby RDoc HTML tarball → 英語原文格納
  └── ../ruby-wasm-docs-collector/   ruby/ruby.wasm RBS + README + docs/ + js-gem README 収集
  ├── lib/ruby_knowledge_db/
  │   ├── orchestrator.rb    全ソース一括更新
  │   ├── esa_writer.rb      esa API 投稿
  │   └── config.rb          APP_ENV 設定ロード
  ├── scripts/
  │   ├── update_all.rb          (legacy) 手動実行エントリポイント — 現状は trunk-changes 系の旧 generator gem に依存しており単独では動作しない。本流は `bundle exec rake`（default task）
  │   ├── import_md_files.rb     MD ファイル一括 import（picoruby trunk 変更記事等）
  │   └── import_esa_export.rb   esa エクスポート一括 import
  └── db/
      ├── ruby_knowledge.db  本番 DB（git 管理外）
      └── last_run.yml       since 永続化（docs は コレクタークラス名 → 最終実行時刻、trunk は sources.yml キー → 二段 bookmark Hash）
```

---

## Collector の統一インターフェース

各 in-project gem はこのインターフェースに従う：

```ruby
module RuremaCollector  # または PicorubyDocsCollector, etc.
  class Collector
    SOURCE = "rurema/doctree:ruby4.0"  # source カラムの値（細分化される場合はプレフィクス）

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

last_run.yml のキー: docs 系コレクターは完全修飾クラス名（例: `RuremaCollector::Collector`, `PicorubyDocsCollector::Collector`）。trunk 系は `sources.yml` のキー（`picoruby_trunk` / `cruby_trunk` / `mruby_trunk`）で、値は `last_started_{at,before}` / `last_completed_{at,before}` の 4 フィールド Hash。

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
| `ruby/ruby:rdoc/trunk/{ClassName}` | ruby/ruby trunk RDoc の英語原文（ruby-rdoc-collector）。JP query の英訳と和訳表示は chiebukuro-mcp 経由のホスト LLM agent が担当 |
| `ruby/ruby.wasm:docs/sig/{path}` | ruby/ruby.wasm の RBS 型定義 (sig/ 配下) |
| `ruby/ruby.wasm:docs/readme` | ruby/ruby.wasm ルート README |
| `ruby/ruby.wasm:docs/{name}` | ruby/ruby.wasm の docs/ 配下ガイド (api / faq / cheat_sheet) |
| `ruby/ruby.wasm:docs/js-gem` | ruby/ruby.wasm の js gem (`packages/gems/js`) README |

---

## 依存する外部リポジトリ（in-project gem）

各 collector / 記事生成は bash0C7 配下の gem リポジトリに分離されている。開発時はいずれもローカルクローンが必要。

| リポジトリ | ローカルパス | 役割 |
|-----------|------------|--------|
| trunk-changes-diary   | `../trunk-changes-diary`   | Git diff 取得・Claude CLI 記事生成エンジン |
| rurema-collector      | `../rurema-collector`      | rurema/doctree 収集（内部で rurema/doctree を clone/参照）|
| picoruby-docs-collector | `../picoruby-docs-collector` | picoruby/picoruby の docs（RBS + README）収集 |
| ruby-rdoc-collector   | `../ruby-rdoc-collector`   | ruby/ruby の RDoc HTML（cache.ruby-lang.org tarball）を取得し英語原文のまま格納。JP query 英訳と和訳表示は chiebukuro-mcp 経由のホスト LLM agent 担当 |
| ruby-wasm-docs-collector | `../ruby-wasm-docs-collector` | ruby/ruby.wasm の sig (RBS) + ルート README + docs/ + js-gem README を収集 |
| chiebukuro-mcp        | `../chiebukuro-mcp`        | MCP サーバー（`exe/chiebukuro-mcp serve` を委譲先として使用）|
| ruby-knowledge-store  | `../ruby-knowledge-store`  | Store / Embedder / Migrator |

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

### rake（日次一括処理・デフォルトタスク）

```bash
# 昨日分を自動処理（SINCE=昨日, BEFORE=今日 を自動設定）
APP_ENV=production bundle exec rake

# 特定日を指定
APP_ENV=production SINCE=2026-04-10 BEFORE=2026-04-11 bundle exec rake
```

デフォルトタスクが全パイプライン。全 `_trunk` ソース（picoruby/cruby/mruby）を順次 generate → import → esa 投稿。続けて `namespace :update` 配下の全 `update:*` タスクを動的発見して順次 invoke（現状は `update:picoruby_docs` / `update:ruby_rdoc` / `update:rurema` — 新しいデータソースを増やす時は `task :foo` を `namespace :update` に追加するだけで自動で取り込まれる）。最後に `db_copy_to` で chiebukuro-mcp 参照先（iCloud）にコピーまで行う。Store は共有して1回だけ開く。rdoc/rurema/picoruby_docs も同じ `ruby_knowledge.db` に同居。テストを回す時は `bundle exec rake test`。

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

- **full clone**: `~/.cache/trunk-changes-repos/` にキャッシュ（mutable に保持、`/tmp` は揮発のため使わない）。`--no-single-branch` で全ブランチ取得
- **時系列 diff**: `git diff --ignore-submodules prev_hash..hash` で前コミットとの差分。`last_commit_before(date, branch)` で起点取得
- **merge commit**: `is_merge?` フラグ + `merge_log` でコミット一覧付与。PR 全体をまとめて解説する記事を生成
- **submodule 記事**: `git submodule update --init --depth=1` で clone。`submodule_changes` で SHA range 取得、`submodule_log` + `submodule_diff_stat` を Claude CLI に渡して個別記事生成
- source: `picoruby/picoruby:trunk/article/{submodule_name}`

### trunk-changes パイプラインの非決定論と監視

Claude CLI の記事生成は**非決定論**（同じ入力で毎回違う出力）。これに起因する運用上の罠と決定論的対策:

- **再実行で重複が積もる**: `rake` が途中失敗した後そのまま再実行すると、Claude CLI は違う文体で記事を再生成する → `content_hash` が一致せず DB 重複、esa 側も同名（`(1)` サフィックス）で二重投稿。対処1: `rake` は esa preflight で SINCE/BEFORE 範囲に既存投稿があれば hard abort（`EsaPreflight.check_conflicts!`）。対処2: 事後に `rake db:scan_pollution` / `rake esa:find_duplicates` を必ず回す。なお `rake` は partial 失敗時に `last_completed_*` を書かへんため subagent PLAN で `wip=true` が立つ — 次の再実行で自動的に同じ SINCE から拾い直すが、**既に投稿済みの esa 記事は preflight で検出されて abort する**ので、esa 側を手動で掃除してから再実行する運用。
- **generate フェーズの git stderr が exit 0 に埋もれる**: GitOps.setup や submodule update のエラーが silent failure になり、空データで記事生成 → 空メタ記事混入。trunk-changes-diary 5810d4c で submodule 側は on-demand fetch ガード済み。親リポ側は `rake cache:prepare`（`rake` の prereq）が fetch→reset→submodule 再帰を強制実行して事前検知。
- **汚染 cleanup は ID 指定が安全**: `rake db:delete_polluted IDS=...` / `rake esa:delete IDS=...`。どちらも host guard 有効、IDS 未指定は abort。

運用フロー（subagent 経由ではなく手動で回す場合）:

```bash
# pre-flight は rake のデフォルトタスクに prereq 化済み（明示不要だが、トラブル時は単体実行可）
APP_ENV=production bundle exec rake cache:prepare

# 本番パイプライン
APP_ENV=production SINCE=YYYY-MM-DD BEFORE=YYYY-MM-DD bundle exec rake

# 事後検査
APP_ENV=production bundle exec rake db:stats
APP_ENV=production bundle exec rake db:scan_pollution
APP_ENV=production bundle exec rake esa:find_duplicates DATE=YYYY-MM-DD

# cleanup（必要時のみ、ID を明示）
APP_ENV=production bundle exec rake db:delete_polluted IDS=1866,1869
APP_ENV=production bundle exec rake esa:delete IDS=104
```

### キャッシュ方針

`~/.cache/trunk-changes-repos/` に永続。`/tmp` は揮発なので使わない。mutable 前提 = working copy は常にクリーン / ローカルブランチは都度作り直し / submodule は recursive 再初期化、という不変条件を `cache:prepare` が強制する。物理破損（pack 崩れ等）は自動修復不可 → 手動で該当ディレクトリを削除して再 clone するのがエスケープハッチ。

`ruby-rdoc-collector` は `https://cache.ruby-lang.org/pub/ruby/doc/ruby-docs-en-master.tar.xz` を `~/.cache/ruby-rdoc-collector/tarball/` にダウンロード・展開する。ruby/ruby clone は不要（`cache:prepare` 依存なし）。**コンテンツは英語原文のまま格納**され、翻訳は chiebukuro-mcp 経由のホスト LLM agent がオンデマンドで行う（meta YAML の `columns.memories.source.hints.note` に指示）。smoke test 用エスケープハッチとして `RUBY_RDOC_TARGETS=ClassA,ClassB` / `RUBY_RDOC_MAX_METHODS=20` env var を Collector が認識する（default は無制限）。

### since 永続化
`db/last_run.yml` にコレクタークラス名をキーとして最終実行時刻を保存。本流は `Rakefile` の `run_collector` ヘルパー（`namespace :update` 配下）が自動読み書きする。`scripts/update_all.rb` も同ファイルを参照する設計やったが現状 legacy。

**since 無視 collector の bookmark 値（`RubyWasmDocsCollector::Collector` 等）:** `run_collector` は collector が since を無視するか否かに関わらず `last_run[klass_name] = before` を一律に書き込むため、since 無視 collector のエントリも積まれる。これは collector 側のロジックには使われない **dead value**（情報用ログとしてのみ意味を持つ）。冪等性は `content_hash` で担保されているため bookmark がずれても挙動に影響しない。将来的に「since 無視」フラグを `run_collector` に持たせて bookmark をスキップする選択肢はあるが、現状はシンプルさを優先して全 collector 統一の挙動にしている。

**更新:** `rake`（trunk-changes 3フェーズパイプライン）は **二段コミット式 bookmark** を `last_run.yml` に書き込む。各 `*_trunk` ソースごとに Phase 1 開始直前に `last_started_{at,before}` を記録し、Phase 2b（esa 投稿）がエラーなく完走した時だけ `last_completed_{at,before}` を追記する。`last_started_before > last_completed_before`（あるいは `last_completed_*` 欠落）のソースは WIP = 前回実行が完走してへん、というシグナル。次回の SINCE は `min(last_completed_before)` を床にして safe floor から再開（`content_hash` 冪等で重複は自動スキップ）。`rurema` / `picoruby_docs` / `ruby_wasm_docs` 系は従来通り flat string（`Rakefile` の `namespace :update` が管理。`scripts/update_all.rb` は legacy）。

二段コミット bookmark のスキーマ例:

```yaml
picoruby_trunk:
  last_started_at:       2026-04-15T10:00:00+09:00
  last_started_before:   2026-04-15
  last_completed_at:     2026-04-15T10:05:00+09:00
  last_completed_before: 2026-04-15
```

### MD ファイル import（picoruby trunk）
```bash
bundle exec ruby scripts/import_md_files.rb <dir> [source]
# YAML フロントマター除去 + content_hash 重複スキップ
# ファイル名パターン: YYYY-MM-DD.md のみ（重複ファイル自動除外）
```

### db:delete_rdoc: rdoc ソース全削除

```bash
APP_ENV=production bundle exec rake db:delete_rdoc
```

`ruby/ruby:rdoc/trunk/%` な行を memories + memories_vec から削除（memories_fts は trigger で自動追従）。パイプライン設計変更（日本語翻訳 → 英語原文）に伴う一括切り替え時や、baseline が壊れた時の escape hatch として使用。host guard 有効（`ensure_write_host!`）。

### sqlite3 CLI 禁止（sqlite_vec 経由必須）

システムの `/usr/bin/sqlite3` は vec0 拡張を持たないため、`memories_vec` テーブルにアクセスすると `no such module: vec0` エラーになる。**DB への問い合わせは必ず Ruby + `sqlite_vec` gem 経由で行うこと。** `sqlite3` コマンドラインツールの直接使用は禁止。

DB 状態確認は `bundle exec rake db:stats` を使用する。

### memories.embedding は NULL（仕様）
memories テーブルの embedding カラムは全件 NULL。ベクトルは memories_vec にのみ格納。chiebukuro-mcp の semantic_search は memories_vec を使うため問題なし。

### rurema の source 値は細分化（仕様）
rurema は `rurema/doctree:ruby4.0/{lib}` 形式で source が細分化される。GROUP BY source の上位に出ないのは仕様。全件確認は `WHERE source LIKE 'rurema%'`。

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
| `../trunk-changes-diary/` | Git diff 取得・Claude CLI 記事生成エンジン |
| `../rurema-collector/` | rurema doctree RD パース（BitClust::RRDParser）|
| `../picoruby-docs-collector/` | PicoRuby RBS + README 収集 |
| `lib/ruby_knowledge_db/orchestrator.rb` | 全ソース一括更新オーケストレーション |
| `lib/ruby_knowledge_db/trunk_bookmark.rb` | `rake` の二段 bookmark 管理（load/save/mark_started/mark_completed/status/recommended_since_floor）|
| `lib/ruby_knowledge_db/esa_preflight.rb` | `rake` 起動前の多重実行ガード — esa 側に SINCE/BEFORE 範囲の投稿が既にあれば hard abort |
| `lib/ruby_knowledge_db/esa_writer.rb` | esa API 投稿 |
| `lib/ruby_knowledge_db/config.rb` | APP_ENV 別設定ロード |
| `../ruby-knowledge-store/migrations/001_schema.sql` | memories + FTS5 + vec0 + _sqlite_mcp_meta |
| `config/chiebukuro.json.example` | DB 接続設定テンプレート（実設定は `~/chiebukuro-mcp/chiebukuro.json` へ）|
| `config/sources.yml` | trunk-changes 収集対象リポジトリ設定（`*_trunk` キーから Rake タスク自動生成）|
| `config/environments/{APP_ENV}.yml` | APP_ENV 別の DB パス・esa 設定 |
| `scripts/update_all.rb` | (legacy) 旧手動実行エントリポイント。trunk-changes 系の旧 generator gem (`picoruby_trunk_changes_generator` 等) に依存しており現状単独実行不可。本流は `bundle exec rake`（default task）|
| `scripts/import_md_files.rb` | MD ファイル一括 import |
| `scripts/import_esa_export.rb` | esa エクスポート一括 import |
| `db/last_run.yml` | since 永続化ファイル（git 管理外）|
| `test/test_helper.rb` | StubEmbedder + 共通セットアップ |
| `.claude/commands/ruby-knowledge-db.md` | 統合スラッシュコマンド — 意図解釈 → subagent dispatch |
| `.claude/agents/ruby-knowledge-db-run.md` | 書き込み系 subagent（pipeline / 個別 phase / 破壊的削除、PLAN→CONFIRMED ゲート）|
| `.claude/agents/ruby-knowledge-db-inspect.md` | 読み取り系 subagent（stats / scan / find_duplicates / bookmark / ad-hoc SELECT、ゲートなし）|

MCP サーバーの起動は `chiebukuro-mcp` リポジトリの `exe/chiebukuro-mcp serve` に委譲する（このリポジトリに `bin/serve` や `scripts/start_mcp.sh` は存在しない）。

### Claude Code 経由の運用

統合コマンド `/ruby-knowledge-db` が router。`rake -T` で現行タスク一覧を動的取得し、ユーザー引数から意図を解釈、不明なら半動的メニュー（取り込み / 確認 / 掃除 / rake -T / その他）を提示。確認後に適切な subagent へ dispatch する（書き込み系は `ruby-knowledge-db-run`、読み取り系は `ruby-knowledge-db-inspect`）。新しい `rake` タスクを足しても、router が `rake -T` を再取得するので command 側は改修不要。

## Responsibility boundary (chiebukuro-mcp agent schema)

This repo owns the generation and update of `ruby_knowledge.db`, plus applying `ruby-knowledge-store` migrations (including `003_extend_meta.sql`, which adds the `hints_json` / `recipe_sql` / `recipe_label` columns required by the chiebukuro-mcp agent-ready schema).

**This repo does not own recipe / clarification_field / column-hint data.** That data lives in `dotfiles/chiebukuro-mcp/scripts/meta_patches/ruby_knowledge.yml` and is applied by `apply_meta_patches.rb`. Do not duplicate it here. See `chiebukuro-mcp/CLAUDE.md` for the meta schema spec.
