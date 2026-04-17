# rdoc English-only store + on-demand translation (Agent 振る舞いへの移譲)

## Context / Motivation

`ruby_knowledge.db` は **AI データエージェント (chiebukuro-mcp + ホスト LLM = Claude Code) から読まれる個人用 DB**。すべてのコンテンツを人間が直読するわけではない。

現行 `ruby-rdoc-collector` は `ruby/ruby:rdoc/trunk/*` の英語 RDoc を **collect 時に claude haiku で日本語翻訳** してから store していた。しかし、

- 全件 upfront 翻訳は token コストが巨大（数百クラス × メソッド数）。
- 実際に人間が description を読むケースはごく一部、agent が読むケースは英語でも困らない。
- 既存 chiebukuro-mcp は **sampling を使わない / MCP server は読むだけ** 原則。LLM 翻訳は **ホスト LLM 側の仕事** として切り出せる。

→ **RDoc は英語のまま store し、日本語 query は agent が英訳してから検索、description の和訳は agent が表示時にオンデマンド実施。**

## Design Decisions

### 1. メタ YAML の note 更新 (dotfiles/chiebukuro-mcp 側)

`dotfiles/chiebukuro-mcp/chiebukuro-mcp/scripts/meta_patches/ruby_knowledge.yml` の `columns.memories.source.hints.note` にある rdoc 記述を書き換え。

**現行 (L33-37 抜粋):**
> rdoc/trunk/ は Ruby master の英語 RDoc API ドキュメントの日本語翻訳版。

**新:**
> rdoc/trunk/ は Ruby master の **英語 RDoc API ドキュメント原文** を格納（翻訳なし）。日本語 query は **先に英訳してから** FTS5 / source LIKE に投げること。description の和訳が必要な場合は agent 側で表示時にオンデマンド翻訳し、日本語と英語の両表記で提示せよ。

残りの相補性（rurema との関係、Prism 解析可能、C 拡張 RDoc 形式）は維持。

### 2. ruby-rdoc-collector パイプライン簡略化

**削除対象:**
- `lib/ruby_rdoc_collector/translator.rb`
- `lib/ruby_rdoc_collector/translation_cache.rb`
- `lib/ruby_rdoc_collector/claude_semaphore.rb`
- `test/test_translator.rb`
- `test/test_translation_cache.rb`
- `test/test_claude_semaphore.rb`
- `Collector#safe_translate_and_format` / `#parallel_translate` / `THREAD_POOL_SIZE` / `CLASS_POOL_SIZE` / `process_entities_in_pool` の class/method 並列化
- `Translator` 初期化・引数 (`translator:` kwarg)
- README.md の翻訳関連セクション（翻訳キャッシュ、claude 並列、haiku モデル、`chdir:'/tmp'` persona escape 等）

**簡略化:**
- `MarkdownFormatter#format(entity, jp_description:, jp_method_descriptions:, en_description:, en_method_descriptions:)` → `format(entity)` に縮退。`entity.description` と `entity.methods[].description` を直接出力。
- `Collector#process_entity`: HTML parse → `MarkdownFormatter#format` → yield、のシンプルパイプラインに。claude semaphore / yield_mutex / 並列処理は**全撤去**（serial 化、了解）。
- `SourceHashBaseline#compute_hash` は英語テキストそのものを hash 化（現行も入力文字列を hash るだけなので実質**変更なし**）。
- 中間 MD debug ファイルは英語のまま `/tmp/ruby-rdoc-<ts>/<Class>.md` に出力継続（debug artifact として有用）。

**Collector 公開インターフェースは維持** — 呼び出し側 (`ruby-knowledge-db` の `rake update:ruby_rdoc`) は無変更。

**キャッシュ廃棄:**
- `~/.cache/ruby-rdoc-collector/translations/` ディレクトリは**削除**（再発生せず）。
- `~/.cache/ruby-rdoc-collector/source_hashes.production.yml` と `.development.yml` / `.test.yml` は**削除**（既存 baseline は日本語 content 時代のもので混乱の元）。
- `~/.cache/ruby-rdoc-collector/tarball/` は**継続利用**（RDoc tarball キャッシュは有用）。

### 3. 既存 DB データのクリーンアップ

現 `production` DB に 4 クラス（ARGF / Addrinfo / ArgumentError / BigDecimal）が**日本語翻訳版で格納済**。このまま放置すると英語版との二重格納になる。

**クリーンアップ手順:**
```ruby
# Ruby + sqlite_vec 経由（sqlite3 CLI 禁止）
# memories + memories_vec + memories_fts すべてから該当行削除
DELETE FROM memories WHERE source LIKE 'ruby/ruby:rdoc/trunk/%';
# memories_fts / memories_vec は TRIGGER or 手動削除（既存スキーマ確認要）
```

Rake task として `rake db:delete_rdoc` を新設し、APP_ENV 別に安全に実行できる形で提供、了解。

### 4. Embedding 戦略

**採用: 案 a** — ruri-v3-310m-onnx で英語 content も embedding する。

理由:
- ruri-v3 は日本語特化だが英語テキストも embed 自体は可能。cross-lingual 精度は未検証だが、**日本語 query → agent が英訳 → 英訳 query を ruri-v3 で embed → 英語 content の ruri-v3 embedding と比較** の構成なら「英 vs 英」同言語比較になるため精度低下懸念は軽減される。
- FTS5 trigram だけでは曖昧検索（類義語 / 部分一致）ができない。vec0 併用で semantic_search ツールが引き続き機能する。

実装:
- `ruby-knowledge-store` の `Embedder#embed(text)` をそのまま呼ぶ（変更なし）。
- `Store#store(content:, source:)` の通常パスで memories + memories_vec + memories_fts に INSERT。

### 5. Agent 振る舞いの期待動作

chiebukuro-mcp ツール経由で rdoc を扱う際、ホスト LLM（Claude Code）は `hints.note` を schema resource から読み取り、以下の振る舞いを取る:

1. **Query 英訳:** 日本語入力クエリを英訳してから `chiebukuro_query` / `chiebukuro_semantic_search` に投げる。
2. **結果表示:** 検索結果の description（英語）を必要に応じて agent 側で和訳し、**日本語 + 英語の両表記**で提示する。

MCP tool 側は**何も変えない**（読むだけ原則）。agent 側で全て完結、了解。

## Affected Repositories

| リポジトリ | 変更内容 |
|---|---|
| `../ruby-rdoc-collector` | コード削除 + 簡略化 + テスト削除 + README 削除、主要変更 |
| `dotfiles/chiebukuro-mcp/chiebukuro-mcp/scripts/meta_patches/` | `ruby_knowledge.yml` の note 書き換え |
| `ruby-knowledge-db` (this repo) | `rake db:delete_rdoc` 追加。既存 `rake update:ruby_rdoc` は変更なし（Collector 公開 IF 維持のため）。CLAUDE.md の rdoc 関連記述更新。|

## Migration / Rollout Plan

1. ruby-rdoc-collector で TDD: テスト削除 → コード削除 → markdown_formatter / collector 簡略化 → 残テスト green 化。
2. dotfiles の meta YAML 更新 + `apply_meta_patches.rb` で本番 DB に反映。
3. ruby-knowledge-db で `rake db:delete_rdoc` 追加 + TDD。
4. production DB クリーンアップ: `APP_ENV=production bundle exec rake db:delete_rdoc` 実行。
5. baseline / translation キャッシュ削除。
6. `APP_ENV=production bundle exec rake update:ruby_rdoc` フルラン（haiku なしで高速完走の想定、評価）。
7. `chiebukuro-mcp` 経由で日本語クエリを流して、agent が英訳 → 検索 → 和訳両表記する振る舞いを手動検証。

## Test Strategy

**ruby-rdoc-collector:**
- t-wada TDD: 残すテスト (`test_collector.rb`, `test_collector_streaming.rb`, `test_markdown_formatter.rb`) を **翻訳なし前提**に書き換え → red → 実装簡略化 → green。
- StubTranslator / claude 関連 stub を削除し、input → output の純粋な変換テストに。

**ruby-knowledge-db:**
- `rake db:delete_rdoc` の integration test。test env DB に fixture row を入れ、実行後に 0 件になることを確認。

## Out of Scope

- rurema / trunk-changes / picoruby-docs 系 collector は**無変更**。これらは日本語コンテンツのままで問題なし（agent は言語を意識しない）。
- chiebukuro-mcp gem 本体のコード変更は**しない**。既存 MCP tool / resource でカバー。
- 英語 content を ruri-v3 で embed した際の cross-lingual 精度評価は**別タスク**。必要なら後日計測。
- 既存の日本語翻訳版 4 クラスの内容保全（rescue）はしない。英語版を改めて格納する。

## Non-Goals / 明示的に避けること

- MCP server 側での自動翻訳（sampling 禁止の原則に反する、了解）。
- 新しい MCP tool 追加（`query_rdoc_bilingual` 等）。既存 tool + metadata で完結させる。
- ruby-rdoc-collector の API 変更（公開 IF は維持、内部簡略化のみ）。
