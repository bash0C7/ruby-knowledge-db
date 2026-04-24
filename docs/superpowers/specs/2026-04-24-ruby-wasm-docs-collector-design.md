# ruby-wasm-docs-collector design

- Date: 2026-04-24
- Status: Approved (pending user review of this document)
- Scope: Add `ruby/ruby.wasm` RBS / README / docs / js-gem README to `ruby-knowledge-db`.

## 1. Goal

`https://github.com/ruby/ruby.wasm` から以下の 4 系統のコンテンツを `ruby-knowledge-db` の `memories` テーブルに取り込み、`chiebukuro-mcp` 経由で FTS5 + vec0 検索可能にする。

- `sig/**/*.rbs` (RBS 型定義, 7 ファイル)
- `README.md` (repo ルート README)
- `docs/*.md` (api.md / faq.md / cheat_sheet.md)
- `packages/gems/js/README.md` (ruby.wasm の JS 連携 gem `js` の README)

**スコープ外:**
- `packages/npm-packages/*/README.md` (npm パッケージ README 群, バージョン違いで中身重複 + ビルド方法中心でノイズ多)
- `ext/ruby_wasm/README.md`, `CONTRIBUTING.md` 等の補助ファイル
- `chiebukuro-mcp` 側の recipe / clarification_field / column-hint 更新 (別リポ責任)

## 2. Architecture

`picoruby-docs-collector` と完全同型の in-project gem `ruby-wasm-docs-collector` を新規作成し、`ruby-knowledge-db` が path gem として取り込む。

```
ruby-knowledge-db/
├── Gemfile                     ← path gem 追加
├── config/sources.yml          ← ruby_wasm_docs: 追加
└── Rakefile                    ← update:ruby_wasm_docs task 追加
                                  (default task は update:* を動的発見、無改修)

../ruby-wasm-docs-collector/    ← 新規 in-project gem
├── ruby_wasm_docs_collector.gemspec
├── Gemfile / Gemfile.lock / Rakefile
├── lib/
│   ├── ruby_wasm_docs_collector.rb
│   └── ruby_wasm_docs_collector/
│       ├── collector.rb
│       ├── file_walker.rb
│       └── formatter.rb
├── test/
│   ├── test_helper.rb
│   ├── test_collector.rb
│   ├── test_file_walker.rb
│   ├── test_formatter.rb
│   └── fixtures/fake-ruby-wasm/...
└── README.md
```

**データ取得方針:** `rurema-collector` / `picoruby-docs-collector` と同じくローカル clone を前提とする。`~/dev/src/github.com/ruby/ruby.wasm` をユーザーが `ghq get` 済みで、`git pull` は手動運用。`cache:prepare` には載せない。

## 3. Components

### 3.1 `RubyWasmDocsCollector::Collector`

エントリポイント。CLAUDE.md 記載の Collector 統一インターフェース (`initialize(config)` + `collect(since:, before:)`) に準拠。

```ruby
module RubyWasmDocsCollector
  class Collector
    SOURCE_PREFIX = 'ruby/ruby.wasm:docs'

    def initialize(config, file_walker: nil, formatter: nil)
      @repo_path   = File.expand_path(config['repo_path'])
      abort "ruby.wasm repo not found: #{@repo_path}" unless Dir.exist?(@repo_path)
      @file_walker = file_walker || FileWalker.new(@repo_path)
      @formatter   = formatter   || Formatter.new
    end

    # since / before は無視 (content_hash で冪等)
    # @return [Array<{content: String, source: String}>]
    def collect(since: nil, before: nil)
      @file_walker.each_entry.map do |entry|
        {
          content: @formatter.format(entry),
          source:  "#{SOURCE_PREFIX}/#{entry[:source_suffix]}"
        }
      end
    end
  end
end
```

### 3.2 `RubyWasmDocsCollector::FileWalker`

4 系統 (rbs / root readme / docs / js-gem) を走査して entry Hash を yield する。

```ruby
class FileWalker
  def initialize(repo_path)
    @repo_path = repo_path
  end

  # @return [Enumerator<{kind: Symbol, path: String, rel_path: String, source_suffix: String}>]
  def each_entry
    return enum_for(:each_entry) unless block_given?
    walk_rbs          { |e| yield e }
    walk_root_readme  { |e| yield e }
    walk_docs         { |e| yield e }
    walk_js_gem       { |e| yield e }
  end

  private

  # sig/**/*.rbs → kind: :rbs, source_suffix: "sig/<rel without .rbs>"
  def walk_rbs
    sig_dir = File.join(@repo_path, 'sig')
    unless Dir.exist?(sig_dir)
      warn "RubyWasmDocsCollector: sig/ not found in #{@repo_path}"
      return
    end
    Dir.glob(File.join(sig_dir, '**', '*.rbs')).sort.each do |path|
      rel    = path.sub(/\A#{Regexp.escape(@repo_path)}\//, '')  # => "sig/..."
      suffix = rel.sub(/\.rbs\z/, '')                            # => "sig/..." (prefix kept)
      yield(kind: :rbs, path: path, rel_path: rel, source_suffix: suffix)
    end
  end

  # README.md (root) → kind: :readme, source_suffix: 'readme'
  def walk_root_readme
    path = File.join(@repo_path, 'README.md')
    unless File.exist?(path)
      warn "RubyWasmDocsCollector: root README.md not found"
      return
    end
    yield(kind: :readme, path: path, rel_path: 'README.md', source_suffix: 'readme')
  end

  # docs/*.md → kind: :doc, source_suffix: "<basename without .md>"
  def walk_docs
    docs_dir = File.join(@repo_path, 'docs')
    unless Dir.exist?(docs_dir)
      warn "RubyWasmDocsCollector: docs/ not found"
      return
    end
    Dir.glob(File.join(docs_dir, '*.md')).sort.each do |path|
      name = File.basename(path, '.md')
      yield(kind: :doc, path: path, rel_path: "docs/#{File.basename(path)}", source_suffix: name)
    end
  end

  # packages/gems/js/README.md → kind: :readme, source_suffix: 'js-gem'
  def walk_js_gem
    path = File.join(@repo_path, 'packages', 'gems', 'js', 'README.md')
    unless File.exist?(path)
      warn "RubyWasmDocsCollector: js gem README not found at #{path}"
      return
    end
    yield(kind: :readme, path: path, rel_path: 'packages/gems/js/README.md', source_suffix: 'js-gem')
  end
end
```

### 3.3 `RubyWasmDocsCollector::Formatter`

RBS はヘッダ付与、それ以外はそのまま。

```ruby
class Formatter
  def format(entry)
    content = File.read(entry[:path], encoding: 'utf-8')
    case entry[:kind]
    when :rbs
      "# RBS: #{entry[:rel_path]}\n\n#{content}"
    when :readme, :doc
      content
    end
  rescue => e
    warn "RubyWasmDocsCollector: read failed: #{entry[:path]} (#{e.message})"
    nil
  end
end
```

`Formatter#format` が nil を返したら Collector 側で skip。

## 4. Source value mapping

`SOURCE_PREFIX = 'ruby/ruby.wasm:docs'` と `source_suffix` を `/` で結合する。

| ファイル | source 値 |
|---|---|
| `sig/open_uri.rbs` | `ruby/ruby.wasm:docs/sig/open_uri` |
| `sig/ruby_wasm/build.rbs` | `ruby/ruby.wasm:docs/sig/ruby_wasm/build` |
| `sig/ruby_wasm/cli.rbs` | `ruby/ruby.wasm:docs/sig/ruby_wasm/cli` |
| `sig/ruby_wasm/ext.rbs` | `ruby/ruby.wasm:docs/sig/ruby_wasm/ext` |
| `sig/ruby_wasm/feature_set.rbs` | `ruby/ruby.wasm:docs/sig/ruby_wasm/feature_set` |
| `sig/ruby_wasm/packager.rbs` | `ruby/ruby.wasm:docs/sig/ruby_wasm/packager` |
| `sig/ruby_wasm/util.rbs` | `ruby/ruby.wasm:docs/sig/ruby_wasm/util` |
| `README.md` (ルート) | `ruby/ruby.wasm:docs/readme` |
| `docs/api.md` | `ruby/ruby.wasm:docs/api` |
| `docs/faq.md` | `ruby/ruby.wasm:docs/faq` |
| `docs/cheat_sheet.md` | `ruby/ruby.wasm:docs/cheat_sheet` |
| `packages/gems/js/README.md` | `ruby/ruby.wasm:docs/js-gem` |

計 12 エントリ。`sig/` プレフィクスは `docs/` 配下ガイドとの区別のため残す。`docs/` プレフィクスは `ruby/ruby.wasm:docs/` と冗長なので剥ぐ。

## 5. Data flow

### 5.1 初回 run

```
rake update:ruby_wasm_docs
  → run_collector(:ruby_wasm_docs, 'RubyWasmDocsCollector::Collector', 'ruby_wasm_docs')
  → Collector#collect → 12 レコード
  → Orchestrator → Store#store → memories / memories_vec / memories_fts に INSERT
  → last_run.yml に { 'RubyWasmDocsCollector::Collector' => BEFORE } 書き込み
```

### 5.2 差分 run

`since / before` は collector 側で無視。`Store#store` が `content_hash = SHA256(content)` による UNIQUE 制約で重複を弾く。変更のあったファイルのみ新規 INSERT される。これは `picoruby-docs-collector` / `rurema-collector` と同じ方針。

### 5.3 古い行の残置について

`content_hash` UNIQUE 方式は「同じ source で古い content が DB に残り続ける」性質を持つ。ruby.wasm の RBS / docs は年単位で緩やかにしか変わらないため、12 行 × 数年規模の残置は許容範囲。

**scope 外:** source 単位の差分削除方式は今回実装しない。必要になれば `ruby-rdoc-collector` の `SourceHashBaseline` を他 collector にも展開する別タスクとして扱う。

## 6. Error handling

| エラー | 発生箇所 | 対応 |
|---|---|---|
| `repo_path` 不在 | `Collector#initialize` | `abort` (運用ミス扱い) |
| `sig/` 不在 | `FileWalker#walk_rbs` | warn して続行 |
| `docs/` 不在 | `FileWalker#walk_docs` | warn して続行 |
| ルート `README.md` 不在 | `FileWalker#walk_root_readme` | warn して続行 |
| `packages/gems/js/README.md` 不在 | `FileWalker#walk_js_gem` | warn して続行 |
| 個別ファイル read 失敗 | `Formatter#format` | warn して当該 entry skip、他は続行 |
| Store / DB エラー | 上位 Orchestrator | 既存の errors 配列で受ける |

ログ形式: `warn "RubyWasmDocsCollector: <reason>: <path>"`

## 7. Testing

### 7.1 Fixture

実 repo 非依存のため、手書き fixture を用意。

```
test/fixtures/fake-ruby-wasm/
├── README.md
├── sig/
│   ├── open_uri.rbs
│   └── ruby_wasm/build.rbs
├── docs/
│   └── api.md
└── packages/gems/js/README.md
```

### 7.2 Test files

- `test/test_file_walker.rb` — 4 系統それぞれを yield すること、欠落時に warn して続行すること
- `test/test_formatter.rb` — RBS ヘッダ付与、md / readme パススルー、read 失敗時 nil
- `test/test_collector.rb` — 統合: collect が期待通りの source 値配列を返すこと、since/before 無視、repo 不在で abort

### 7.3 TDD 規律

CLAUDE.md の TDD コミット境界規律に従い、以下を独立コミットにする:

- `test: add failing specs for FileWalker`
- `feat: implement FileWalker to discover rbs/readme/docs/js-gem entries`
- `test: add failing specs for Formatter`
- `feat: implement Formatter with RBS header prefix`
- `test: add failing specs for Collector`
- `feat: implement Collector entry point`

`rake test` 全緑を各 green commit の完了条件とする。

## 8. Integration (ruby-knowledge-db changes)

### 8.1 `config/sources.yml`

```yaml
  ruby_wasm_docs:
    repo_path: ~/dev/src/github.com/ruby/ruby.wasm
```

### 8.2 `Gemfile`

```ruby
gem 'ruby_wasm_docs_collector', path: '../ruby-wasm-docs-collector'
```

### 8.3 `Rakefile`

```ruby
def require_update_deps
  require_store_deps
  require 'rurema_collector'
  require 'picoruby_docs_collector'
  require 'ruby_rdoc_collector'
  require 'ruby_wasm_docs_collector'   # 追加
end

namespace :update do
  # ...

  desc "Update ruby.wasm docs (SINCE/BEFORE は無視, content_hash 冪等)"
  task :ruby_wasm_docs do
    run_collector(:ruby_wasm_docs, 'RubyWasmDocsCollector::Collector', 'ruby_wasm_docs')
  end
end
```

`default` タスクは `update:*` を動的発見するため、本 task の追加だけで自動的に pipeline に組み込まれる。

### 8.4 `CLAUDE.md`

- source 値規約テーブルに 4 行追加 (sig / readme / docs guide / js-gem)
- 依存外部リポジトリ表に 1 行追加 (`ruby-wasm-docs-collector`)

### 8.5 `README.md`

件数や実行時間の変動情報は書かない (memory `feedback_readme_no_variable_numbers.md` 準拠)。「対応ソース」列挙があれば `ruby/ruby.wasm:docs/*` を追加する程度。

### 8.6 `.claude/agents/ruby-knowledge-db-run.md`

このプロジェクトローカルの subagent は非 trunk 系 collector クラス名をハードコードしているため、以下 2 箇所に `RubyWasmDocsCollector::Collector` を追加する:

1. **PLAN mode の SINCE default 定義部** (行内テーブル): `update:ruby_wasm_docs`: key `RubyWasmDocsCollector::Collector`, or yesterday if absent (`update:picoruby_docs` と同じ扱い) を追加する。

2. **Collector bookmark readback の Ruby one-liner**:

   ```ruby
   %w[RuremaCollector::Collector PicorubyDocsCollector::Collector RubyRdocCollector::Collector]
   ```

   →

   ```ruby
   %w[RuremaCollector::Collector PicorubyDocsCollector::Collector RubyRdocCollector::Collector RubyWasmDocsCollector::Collector]
   ```

### 8.7 `.claude/agents/ruby-knowledge-db-inspect.md`

同様に、`last_run` bookmark readback の Ruby one-liner にクラス名を追加する:

```ruby
%w[RuremaCollector::Collector PicorubyDocsCollector::Collector RubyRdocCollector::Collector]
```

→

```ruby
%w[RuremaCollector::Collector PicorubyDocsCollector::Collector RubyRdocCollector::Collector RubyWasmDocsCollector::Collector]
```

### 8.8 `.claude/commands/ruby-knowledge-db.md` (router)

変更不要。ルーターは `rake -T` を動的取得するので、`update:ruby_wasm_docs` が Rakefile に定義されれば自動でメニューに現れる。

## 9. Build sequence

### Phase 1: ruby-wasm-docs-collector gem (上流)

1. `ghq create github.com/bash0C7/ruby-wasm-docs-collector` で skeleton
2. `picoruby-docs-collector` から構造コピー (中身空): `chore: scaffold gem structure`
3. fixture 配置: `test: add fixture for fake ruby.wasm repo`
4. RED→GREEN (FileWalker → Formatter → Collector) を各 2 commit ずつ
5. (任意) refactor commit
6. `docs: add README`

### Phase 2: ruby-knowledge-db 統合 (下流、Phase 1 完走後)

7. `Gemfile` 更新 + `bundle install`
8. `config/sources.yml` 追記
9. `Rakefile` 追記 (require_update_deps + namespace :update)
10. smoke run: `APP_ENV=development bundle exec rake update:ruby_wasm_docs`
    - 期待: stored=12, skipped=0
11. 冪等性確認: 再実行で stored=0, skipped=12
12. `CLAUDE.md` 更新
13. `.claude/agents/ruby-knowledge-db-run.md` と `.claude/agents/ruby-knowledge-db-inspect.md` の collector クラス名配列に `RubyWasmDocsCollector::Collector` 追加 (ruby-knowledge-db-run.md は SINCE default テーブルにも追加)
14. 単一 commit: `feat: add ruby-wasm-docs-collector integration`
15. production フルラン (user 実施): `APP_ENV=production bundle exec rake`

### 検証チェックポイント

| 段階 | 確認 |
|---|---|
| Phase 1 完了時 | `cd ../ruby-wasm-docs-collector && rake test` 全緑 |
| Phase 2 step 10 | dev DB に `ruby/ruby.wasm:docs/*` 12 行 |
| Phase 2 step 11 | 冪等 (skipped=12) |
| Phase 2 step 15 後 | production DB + iCloud 参照先に反映 |

### Rollback

- Phase 1 で中止: 新 gem ディレクトリを削除して戻す
- Phase 2 で問題発生: 該当 source を消す escape hatch は本 scope 外。必要なら `rake db:delete_polluted IDS=...` を手動適用するか、別タスクで `db:delete_ruby_wasm` を追加する。

## 10. Follow-ups (out of scope)

- **`chiebukuro-mcp` 側 meta patch 追加**: `dotfiles/chiebukuro-mcp/scripts/meta_patches/ruby_knowledge.yml` に `ruby/ruby.wasm:docs/*` パターンの recipe / column-hint を追加すること。これは `chiebukuro-mcp` リポ側の責任 (CLAUDE.md "Responsibility boundary" 参照)。
- **差分削除方式の全 collector 統一**: `ruby-rdoc-collector` の `SourceHashBaseline` を他 docs 系 collector にも展開する設計を別途検討。
