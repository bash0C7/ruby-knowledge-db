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
| picoruby/picoruby:trunk/article/{submodule} | submodule 変更時に individual 記事生成 |
| ruby/ruby:trunk/article | 3フェーズパイプライン（generate → import） |
| ruby/ruby:trunk/diff | 3フェーズパイプライン（generate → import） |
| mruby/mruby:trunk/article | 3フェーズパイプライン（generate → import） |
| mruby/mruby:trunk/diff | 3フェーズパイプライン（generate → import） |

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
    repo_path: ~/.cache/trunk-changes-repos/picoruby # ローカルキャッシュパス（mutable、永続）
    source_diff: picoruby/picoruby:trunk/diff         # DB の source カラム値（diff）
    source_article: picoruby/picoruby:trunk/article   # DB の source カラム値（article）
    prompt_supplement: "..."         # Claude CLI への追加プロンプト（任意）
```

`*_trunk` で終わるキーから `generate:*`, `import:*`, `esa:*` の Rake タスクが自動生成される。

## ⚠️ 別 Mac 実行禁止（暫定 workaround）

`rake daily` / `rake update:*` / `rake import:*` / `rake esa:*` / `rake db:reembed` / `scripts/update_all.rb` などの**書き込み系タスクは特定の Mac（メイン機）でのみ実行**すること。別 Mac で動かすと以下の不整合を起こす:

- production DB (`db/ruby_knowledge.db`) は git 管理外のローカル資産で、`rake daily` 末尾で iCloud (`db_copy_to`) に**片方向コピー**される（pull 同期なし）
- esa token は macOS Keychain（`esa-mcp-token`）から取得するが、**iCloud Keychain では同期されない**汎用エントリなので Mac ごとに個別登録が必要
- 別 Mac で古い/空の DB に書き込むと、iCloud 上の正しい DB を上書き破壊する

そのため、本リポジトリは `config/environments/production.yml` の `allowed_write_host` と `scutil --get LocalHostName` の一致を、書き込み系タスクの開始時にチェックする**ホストガード**を持つ。

```bash
# 現ホストが allowed_write_host と異なると abort
APP_ENV=production bundle exec rake daily
# => Refusing to write: current host 'X' != allowed_write_host 'Y' ...

# どうしても別 Mac で走らせる必要がある場合のみ（非推奨）
ALLOW_WRITE=1 APP_ENV=production bundle exec rake daily
```

※ このガードはあくまで**暫定対処**。恒久的には「esa を source of truth にして DB を再生成可能にする」等の設計変更を検討中。`allowed_write_host` が未設定の環境（`development.yml` / `test.yml`）ではガードは無効。

## セットアップ

```bash
rbenv local 4.0.1
bundle config set --local path 'vendor/bundle'
bundle install
```

### esa 書き込み用トークン登録（macOS Keychain）

`rake daily` / `rake esa:*` は esa API へ記事を POST する。トークンは `security` コマンドで Keychain に登録する:

```bash
security add-generic-password -a "$USER" -s esa-mcp-token -w '<YOUR_ESA_TOKEN>'
# 確認
security find-generic-password -s esa-mcp-token -w
```

- team / category / wip は `config/environments/{APP_ENV}.yml` の `esa` セクションで制御
- production は `bash-trunk-changes` team に `wip: false`、development / test は `bist` team に `wip: true`
- **iCloud Keychain では同期されない**。Mac ごとに個別登録が必要（そもそも書き込みは単一 Mac 運用）

### allowed_write_host 設定

`config/environments/production.yml` に自分のメイン機の LocalHostName を設定する:

```yaml
allowed_write_host: MacBook-Air-M3   # scutil --get LocalHostName の値
```

現ホスト名は `scutil --get LocalHostName` で確認できる。

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

#### 二段コミット式 bookmark（`db/last_run.yml`）

各 `*_trunk` ソースごとに二段 bookmark を `db/last_run.yml` に書き込む:

- **Phase 1 開始直前**: `last_started_{at,before}` を記録
- **Phase 2b（esa 投稿）完走時のみ**: `last_completed_{at,before}` を追記（esa エラー 1件でもあれば書かへん）

```yaml
picoruby_trunk:
  last_started_at:       2026-04-16T00:36:06+09:00
  last_started_before:   2026-04-16
  last_completed_at:     2026-04-16T00:40:29+09:00
  last_completed_before: 2026-04-16
cruby_trunk: { ... }
mruby_trunk: { ... }
```

`last_started_before > last_completed_before`（あるいは `last_completed_*` 欠落）のソースは **WIP = 前回実行が完走してへん** シグナル。次回の SINCE は `min(last_completed_before)` を床にして安全に再開（`content_hash` 冪等で DB 重複は自動スキップ）。

rurema / picoruby_docs 系の docs collector は従来通り flat string 形式（`RuremaCollector::Collector: '2026-04-16'`）で、キー空間が分離されているため共存する。

#### Claude Code subagent 経由の推奨フロー

手動 `rake daily` 実行も可能やが、Claude Code では `ruby-knowledge-db-trunk-changes-daily` subagent 経由が推奨:

- **PLAN モード** — `db/last_run.yml` を読んで FLOOR（`min(last_completed_before)`）を自動算出、WIP 検出、対象ソース一覧を報告
- **CONFIRMED ゲート** — PLAN 内容をユーザーが確認後、`CONFIRMED SINCE=... BEFORE=...` トークン付きで再 dispatch した時のみ EXECUTE
- **EXECUTE モード** — `rake daily` + 事後の `db:scan_pollution` / `esa:find_duplicates` 自動実行

Claude Code スラッシュコマンド `/ruby-knowledge-db-trunk-changes-daily` で起動。

### 運用と監視（非決定論対策）

trunk-changes パイプラインは Claude CLI で記事を生成するため**本質的に非決定論**で、失敗後の再実行や git キャッシュ破損によって DB / esa に汚染データが混入する可能性がある。以下の決定論的タスクで事前・事後に検出・修復する。

#### cache:prepare（事前、`rake daily` に自動依存）

```bash
APP_ENV=production bundle exec rake cache:prepare
```

各 `*_trunk` source の `repo_path` に対して `git fetch origin <branch>` → `git checkout -f -B <branch> origin/<branch>` → `git submodule update --init --recursive --force` を強制実行。**どれか1つでも失敗したら即 abort**。前提: working copy は常にクリーン、ローカルブランチは都度作り直し、submodule は再帰再初期化。`rake daily` の prereq になっているので、通常は明示呼び出し不要。

#### db:scan_pollution（事後、read-only）

```bash
APP_ENV=production bundle exec rake db:scan_pollution
```

既知の空メタマーカー（`空やん`, `書く材料がない`, `情報が渡されてへん`, `変更なし`, `出力フォーマット` 等）と `(source, 先頭200文字)` で重複候補を検出。ヒットしたレコードの ID 一覧を表示。

#### db:delete_polluted（明示 ID 指定の破壊的削除）

```bash
APP_ENV=production bundle exec rake db:delete_polluted IDS=1866,1869,1871
```

`memories_vec` + `memories` を対象（`memories_fts` はトリガで自動追従）。`IDS` 必須、未指定は abort。host guard 有効。

#### esa:find_duplicates（事後、read-only）

```bash
APP_ENV=production bundle exec rake esa:find_duplicates
# 特定日のみ
APP_ENV=production bundle exec rake esa:find_duplicates DATE=2026-04-12
```

`bash-trunk-changes` team 全体（または特定日）で、同一 category + 同一ベース名（` (1)` 等のサフィックス除去後）の重複投稿を検出。esa 側の書き込み齟齬・手動再投稿・retry での重複はここで見える。

#### esa:delete（明示 ID 指定）

```bash
APP_ENV=production bundle exec rake esa:delete IDS=104,110
```

HTTP DELETE で esa 記事を削除。`IDS` 必須、host guard 有効。レート制限対策に各リクエスト間 2 秒 sleep。

### ヒューリスティック注意事項

- **`rake daily` の再実行は慎重に**: Claude CLI は同じ SINCE/BEFORE でも毎回違う文体・長さの記事を生成する。content_hash が一致せず、DB に重複レコードが積み上がる。失敗後の再実行前に `db:scan_pollution` / `esa:find_duplicates` で既存を確認、必要なら cleanup してから再走らせる。
- **WIP bookmark と esa 重複の連鎖**: partial 失敗時（esa posting が途中で1件エラー等）は `last_completed_*` が書かれへんので subagent PLAN で `wip=true` になる → 次の再実行で同じ SINCE から拾い直すが、**既に投稿済みの esa 記事は `(1)` サフィックスで重複投稿される**。WIP 検出を見たら必ず `rake esa:find_duplicates DATE=YYYY-MM-DD` で該当日を確認、重複があれば `esa:delete IDS=...` で残すものを決めて cleanup。
- **generate フェーズの git stderr は exit 0 に埋もれる**: 失敗しても Rake タスクは完走することがある。post-run の `scan_pollution` は必須と考えること。
- **submodule shallow clone の空記事混入**は trunk-changes-diary 側で on-demand fetch ガードを入れて封じた（`trunk_changes.rb` の `ensure_submodule_sha`）。それでも取りこぼしの可能性はゼロではない — `scan_pollution` で最終判定する。
- **キャッシュは `~/.cache/trunk-changes-repos/` に永続**。`/tmp` は揮発領域、使用禁止。`cache:prepare` が mutable 前提で動くので、手作業での `rm -rf` は原則不要（壊れたら reclone は手動判断）。

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

# DB 一括更新（docs 系 collector の since を db/last_run.yml の flat-string 形式から自動取得。trunk 系とは別スキーマ）
bundle exec ruby scripts/update_all.rb

# 指定日時以降を強制再取得
bundle exec ruby scripts/update_all.rb 2026-01-01T00:00:00+09:00

# MD ファイル一括 import（picoruby trunk 変更記事等）
bundle exec ruby scripts/import_md_files.rb <dir> [source]

# esa エクスポート一括 import
bundle exec ruby scripts/import_esa_export.rb <dir>
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

## DB 操作の注意

**sqlite3 CLI 禁止** — システムの sqlite3 は vec0 拡張を持たないため、`memories_vec` テーブルへのアクセスでエラーになる。DB への問い合わせは必ず Ruby + `sqlite_vec` gem 経由で行うこと。

```bash
# DB 状態確認（vec0 含む全テーブル対応）
bundle exec rake db:stats
```

## DB 設計ノート

### embedding カラムと memories_vec の関係

memories テーブルの `embedding` カラムは NULL（全件）。ベクトルデータは `memories_vec`（vec0 仮想テーブル）にのみ格納する設計。semantic_search は memories_vec に対して KNN クエリを実行するため、memories.embedding は使用しない。

### rurema の source 値

rurema レコードの source はライブラリ単位で細分化される（例: `rurema/doctree:ruby4.0/yaml`, `rurema/doctree:ruby4.0/string`）。`GROUP BY source` の上位には現れないが、`WHERE source LIKE 'rurema%'` で全件取得可能。

## DB スキーマ

`ruby-knowledge-store` リポジトリの `migrations/001_schema.sql` 参照。`_sqlite_mcp_meta` テーブルにスキーマ説明文を同居管理。

## テスト

```bash
bundle exec rake test   # orchestrator テスト
# 各 gem のテストは個別リポジトリで実施
# trunk-changes-diary: cd ../trunk-changes-diary && rake test（bundler 不要）
```

## Agent meta schema

`ruby_knowledge.db` is read by the chiebukuro-mcp MCP server. The server expects the extended `_sqlite_mcp_meta` schema provided by `ruby-knowledge-store/migrations/003_extend_meta.sql`. After bumping `ruby-knowledge-store`, re-run the migrator before reapplying dotfiles meta patches.

Recipe and clarification_field data itself is managed in `dotfiles/chiebukuro-mcp/scripts/meta_patches/ruby_knowledge.yml`, not here.
