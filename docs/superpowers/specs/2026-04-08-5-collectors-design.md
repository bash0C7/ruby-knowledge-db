# 5 Collectors 実装設計

Date: 2026-04-08

## 概要

ruby-knowledge-db に知識を供給する 5 つの Collector gem を実装する。
実装順: picoruby-trunk-changes-generator → picoruby-docs-collector → rurema-collector → mruby-trunk-changes-generator → cruby-trunk-changes-generator

---

## 共通インターフェース

全 Collector は以下を満たす。

```ruby
collector = XxxCollector::Collector.new(config)
records   = collector.collect(since: '2026-04-01T00:00:00+09:00')
# => [{ content: String, source: String }, ...]
```

- `config` は `sources.yml` の該当キー（Hash）
- `since` は ISO8601 文字列または nil（nil なら全件 or デフォルト30日分）
- `content_hash` による冪等性は Store 層で担保するため、Collector は重複を気にしない

---

## 1. trunk-changes-diary — TrunkChangesCollector 追加

**ファイル**: `trunk_changes.rb`（末尾に追記）

```ruby
class TrunkChangesCollector
  DEFAULT_DAYS = 30

  def initialize(repo:, branch:, source_diff:, source_article:,
                 git_ops:, content_generator:)
    @branch           = branch
    @source_diff      = source_diff
    @source_article   = source_article
    @git              = git_ops
    @generator        = content_generator
  end

  def collect(since: nil)
    date_range(since).flat_map do |date|
      @git.commits_for_date(date, @branch).flat_map do |hash|
        diff    = @git.show(hash)
        article = @generator.call(context: build_context(hash))
        [
          { content: diff,    source: @source_diff },
          { content: article, source: @source_article }
        ]
      end
    end
  end

  private

  def date_range(since)
    start_date = since ? Date.parse(since) : Date.today - DEFAULT_DAYS
    (start_date..Date.today).to_a
  end

  def build_context(hash)
    metadata = @git.commit_metadata(hash)
    {
      hash:               hash,
      metadata:           metadata,
      show_output:        @git.show(hash),
      changed_files:      [],
      dependency_files:   [],
      project_meta_files: [],
      issue_contexts:     [],
      submodule_updates:  @git.submodule_updates(hash)
    }
  end
end
```

**テスト** (`trunk-changes-diary/test/test_trunk_changes_collector.rb`):
- stub git_ops: `commits_for_date` → `['abc123']`、`show` → `"diff..."` 、`commit_metadata` → 最低限のHash、`submodule_updates` → `[]`
- stub content_generator: `call` → `"article content"`
- `test_collect_returns_diff_and_article`: 1 コミット → 2 レコード、source 値確認
- `test_collect_with_since_uses_date_range`: since 指定 → 正しい日付が渡されること
- `test_collect_with_nil_since_uses_default_range`: since nil → DEFAULT_DAYS 分の範囲

---

## 2. picoruby-trunk-changes-generator

**ファイル構成**:
```
lib/picoruby_trunk_changes_generator.rb
lib/picoruby_trunk_changes_generator/collector.rb
test/test_collector.rb
```

**collector.rb**:
```ruby
require 'trunk_changes'

module PicorubyTrunkChangesGenerator
  class Collector
    REPO           = 'picoruby/picoruby'
    SOURCE_DIFF    = 'picoruby/picoruby:trunk/diff'
    SOURCE_ARTICLE = 'picoruby/picoruby:trunk/article'

    def initialize(config, git_ops: nil, content_generator: nil)
      repo_path = File.expand_path(config['repo_path'])
      branch    = config.fetch('branch', 'master')
      @trunk = TrunkChangesCollector.new(
        repo:              REPO,
        branch:            branch,
        source_diff:       SOURCE_DIFF,
        source_article:    SOURCE_ARTICLE,
        git_ops:           git_ops           || GitOps.new(repo_path),
        content_generator: content_generator || ContentGenerator.new(repo: REPO)
      )
    end

    def collect(since: nil)
      @trunk.collect(since: since)
    end
  end
end
```

**テスト**: stub git_ops + stub content_generator を渡して `collect` の source 値が正しいことを確認

---

## 3. mruby-trunk-changes-generator

picoruby と同パターン。定数のみ差し替え。

```ruby
REPO           = 'mruby/mruby'
SOURCE_DIFF    = 'mruby/mruby:trunk/diff'
SOURCE_ARTICLE = 'mruby/mruby:trunk/article'
```

モジュール名: `MrubyTrunkChangesGenerator::Collector`

---

## 4. cruby-trunk-changes-generator

同パターン。

```ruby
REPO           = 'ruby/ruby'
SOURCE_DIFF    = 'ruby/ruby:trunk/diff'
SOURCE_ARTICLE = 'ruby/ruby:trunk/article'
```

モジュール名: `CrubyTrunkChangesGenerator::Collector`

---

## 5. picoruby-docs-collector

**ファイル構成**:
```
lib/picoruby_docs_collector.rb
lib/picoruby_docs_collector/collector.rb
lib/picoruby_docs_collector/gem_doc_collector.rb
lib/picoruby_docs_collector/rbs_parser.rb
lib/picoruby_docs_collector/readme_parser.rb
test/test_collector.rb
test/test_rbs_parser.rb
test/test_gem_doc_collector.rb
```

- `since:` は無視（常に全件、content_hash で冪等性担保）
- 対象: `{repo_path}/mrbgems/picoruby-*` ディレクトリ
- source: `picoruby/picoruby:docs/{gem-name}`
- `GemDocCollector`: `sig/*.rbs` → RbsParser で解析 + `README.md` → ReadmeParser でそのまま返す
- `RbsParser`: class名・定数・instance/class メソッド・attributes を正規表現で抽出してMarkdown化
- `ReadmeParser`: strip して返すだけ

**テスト**:
- `test_collect_returns_records_for_each_gem`: stub GemDocCollector → 2 gem × 1 content = 2 レコード
- `test_collect_skips_empty_content`: GemDocCollector が空を返したら除外
- RbsParser: class名抽出、メソッド抽出など個別テスト
- GemDocCollector: rbs_parser/readme_parser を stub で注入してテスト

---

## 6. rurema-collector

**ファイル構成**:
```
lib/rurema_collector.rb
lib/rurema_collector/collector.rb
lib/rurema_collector/doctree_manager.rb
test/test_collector.rb
test/test_doctree_manager.rb
```

- `since:` は無視（content_hash で冪等性担保）
- `DoctreeManager`: `doctree_path` 配下の `.git` 有無で `git pull` / `git clone` を判断、`rd_files(version)` で `refm/api/src/**/*.rd` を列挙
- `DefaultRDParser`: `BitClust::RRDParser.parse_stdlib_file` でパース
- source: `rurema/doctree:ruby3.3/{lib}` / `rurema/doctree:ruby3.3/{lib}#{class}`
- パースエラーは warn してスキップ

**テスト**:
- stub DoctreeManager + stub RD パーサーで `collect` の source 値・レコード数を確認
- `test_collect_skips_parse_error`: パーサーが nil を返したらスキップ

---

## テスト方針（全 gem 共通）

- Red → Green → Refactor の順
- 実 ONNX モデル・実 git・実 Claude CLI は一切起動しない
- 引数でスタブオブジェクトを渡す（普通の Ruby、特別な仕組みなし）
- `bundle exec rake test` で全テストが通ること

---

## 実装順と依存関係

```
1. trunk-changes-diary に TrunkChangesCollector 追加 + テスト
2. picoruby-trunk-changes-generator（TrunkChangesCollector を使う）
3. picoruby-docs-collector（独立）
4. rurema-collector（独立）
5. mruby-trunk-changes-generator（2 と同パターン）
6. cruby-trunk-changes-generator（2 と同パターン）
```
