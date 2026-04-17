# rdoc English-only + On-demand Translation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ruby-rdoc-collector` から upfront 翻訳を撤去して英語のまま `ruby_knowledge.db` に store し、日本語 query 翻訳と両表記表示を chiebukuro-mcp 経由のホスト LLM (Claude Code) agent に委譲する。

**Architecture:** (1) ruby-rdoc-collector の Translator / TranslationCache / ClaudeSemaphore を削除、MarkdownFormatter / Collector を英語入力だけで完結する形に簡略化。(2) dotfiles の chiebukuro-mcp meta YAML に「rdoc は英語原文、日本語 query は先に英訳せよ」の note を記載。(3) ruby-knowledge-db に `rake db:delete_rdoc` を追加し、既存の日本語翻訳済 4 クラスを削除してからフルラン再実行。

**Tech Stack:** Ruby 3.x / test-unit (xUnit / t-wada TDD) / SQLite3 + sqlite-vec / informers + ruri-v3-310m-onnx / chiebukuro-mcp meta_patches YAML

---

## Affected Repositories

| 略称 | パス |
|---|---|
| collector | `/Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector` |
| db | `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db` (this repo) |
| dotfiles | `/Users/bash/Library/Mobile Documents/com~apple~CloudDocs/dotfiles/chiebukuro-mcp/chiebukuro-mcp` |

各リポジトリで TDD → commit → push（ユーザー許可済）。

---

## Phase A: ruby-rdoc-collector simplification

### Task A1: MarkdownFormatter テストを英語入力 only に書き換え

**Files:**
- Modify: `collector/test/test_markdown_formatter.rb`

- [ ] **Step 1: 既存テストを全置換**

`test/test_markdown_formatter.rb` 全体を以下に書き換え:

```ruby
require_relative 'test_helper'

class TestMarkdownFormatter < Test::Unit::TestCase
  def setup
    @entity = RubyRdocCollector::ClassEntity.new(
      name:        'Ruby::Box',
      description: 'A Ruby::Box wraps a single value.',
      methods: [
        RubyRdocCollector::MethodEntry.new(
          name:        'value',
          call_seq:    'box.value -> object',
          description: 'Returns the wrapped value.'
        ),
        RubyRdocCollector::MethodEntry.new(
          name:        'replace',
          call_seq:    'box.replace(obj) -> obj',
          description: 'Replaces the wrapped value.'
        )
      ],
      constants:  [],
      superclass: 'Module'
    )
    @formatter = RubyRdocCollector::MarkdownFormatter.new
  end

  def test_emits_class_header_with_superclass
    md = @formatter.format(@entity)
    assert_match(/\A# Ruby::Box/, md)
    assert_include md, '(< Module)'
  end

  def test_includes_english_description_in_overview
    md = @formatter.format(@entity)
    assert_include md, 'A Ruby::Box wraps a single value.'
  end

  def test_method_section_keeps_call_seq_and_description
    md = @formatter.format(@entity)
    assert_include md, 'box.value -> object'
    assert_include md, 'Returns the wrapped value.'
    assert_include md, 'box.replace(obj) -> obj'
    assert_include md, 'Replaces the wrapped value.'
  end

  def test_empty_methods_omits_methods_section
    entity = RubyRdocCollector::ClassEntity.new(
      name: 'Empty', description: '', methods: [], constants: [], superclass: 'Object'
    )
    md = @formatter.format(entity)
    assert_not_match(/^## Methods/, md)
  end

  def test_no_details_block_emitted_anywhere
    md = @formatter.format(@entity)
    assert_not_include md, '<details>'
    assert_not_include md, '<summary>'
  end

  def test_missing_method_description_falls_back_to_empty_string
    entity = RubyRdocCollector::ClassEntity.new(
      name: 'NoDesc', description: 'c', methods: [
        RubyRdocCollector::MethodEntry.new(name: 'm', call_seq: nil, description: nil)
      ], constants: [], superclass: 'Object'
    )
    md = @formatter.format(entity)
    assert_include md, '### m'
  end
end
```

- [ ] **Step 2: テスト実行して red を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector
bundle exec rake test TEST=test/test_markdown_formatter.rb
```

Expected: `ArgumentError: missing keyword: :jp_description` 等で fail、了解。

---

### Task A2: MarkdownFormatter を英語 only に簡略化

**Files:**
- Modify: `collector/lib/ruby_rdoc_collector/markdown_formatter.rb`

- [ ] **Step 1: ファイル全体を置換**

```ruby
module RubyRdocCollector
  class MarkdownFormatter
    def format(entity)
      lines = []
      header = "# #{entity.name}"
      header += " (< #{entity.superclass})" if entity.superclass && !entity.superclass.empty?
      lines << header
      lines << ''
      lines << '## Overview'
      lines << ''
      lines << (entity.description.to_s.empty? ? '' : entity.description)
      lines << ''

      unless entity.methods.empty?
        lines << '## Methods'
        lines << ''
        entity.methods.each do |m|
          lines << "### #{m.name}"
          lines << ''
          if m.call_seq && !m.call_seq.empty?
            lines << '```'
            lines << m.call_seq
            lines << '```'
            lines << ''
          end
          lines << (m.description || '')
          lines << ''
        end
      end

      lines.join("\n").rstrip + "\n"
    end
  end
end
```

- [ ] **Step 2: テスト実行で green 確認**

```bash
bundle exec rake test TEST=test/test_markdown_formatter.rb
```

Expected: 全 pass、了解。

- [ ] **Step 3: commit**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector
git add lib/ruby_rdoc_collector/markdown_formatter.rb test/test_markdown_formatter.rb
git commit -m "$(cat <<'EOF'
refactor: simplify MarkdownFormatter to English-only

Remove jp_description / jp_method_descriptions / en_description /
en_method_descriptions kwargs. Formatter now accepts only entity
and outputs raw English description + call_seq. <details> block
for bilingual display is dropped — on-demand translation moved
to host LLM agent via chiebukuro-mcp hints.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task A3: test_helper.rb を簡略化（translator stub 撤去）

**Files:**
- Modify: `collector/test/test_helper.rb`

- [ ] **Step 1: ファイル全体を置換**

```ruby
require 'test/unit'
require 'fileutils'
require 'tmpdir'
require 'json'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'ruby_rdoc_collector'

FIXTURE_DIR = File.expand_path('fixtures', __dir__)

# Shared test doubles and factory for Collector tests.
module RubyRdocCollectorTestSupport
  class StubFetcher
    def initialize(dir); @dir = dir; end
    def fetch; @dir; end
    def unchanged?; false; end
  end

  class StubParser
    def initialize(entities); @entities = entities; end
    def parse(_dir, targets: nil)
      return @entities if targets.nil?
      @entities.select { |e| targets.include?(e.name) }
    end
  end

  def build_collector(entities, baseline: nil, output_dir: nil, file_writer: nil)
    opts = {
      fetcher:    StubFetcher.new('/fake'),
      parser:     StubParser.new(entities),
      formatter:  RubyRdocCollector::MarkdownFormatter.new,
      baseline:   baseline   || @baseline,
      output_dir: output_dir || @output_dir
    }
    opts[:file_writer] = file_writer if file_writer
    RubyRdocCollector::Collector.new({}, **opts)
  end
end
```

- [ ] **Step 2: commit (他ファイル未変更なのでこの時点では本ファイルだけで commit OK)**

`EchoRunner` / `FailingRunner` / `StubRunner` / `translator:` kwarg 全撤去、了解。次 Task で依存テストを書き換えるので commit は Task A6 完了後にまとめる、確認。

---

### Task A4: test_collector.rb を英語 only に書き換え

**Files:**
- Modify: `collector/test/test_collector.rb`

- [ ] **Step 1: ファイル全体を置換**

```ruby
require_relative 'test_helper'

class TestCollector < Test::Unit::TestCase
  include RubyRdocCollectorTestSupport

  def setup
    @dir        = Dir.mktmpdir('collector')
    @baseline   = RubyRdocCollector::SourceHashBaseline.new(path: File.join(@dir, 'baseline.yml'))
    @output_dir = File.join(@dir, 'out')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def build_entity(name)
    RubyRdocCollector::ClassEntity.new(
      name: name, description: "desc of #{name}", methods: [], constants: [], superclass: 'Object'
    )
  end

  def test_collect_returns_content_and_source_per_class
    entities = [build_entity('String'), build_entity('Integer')]
    c = build_collector(entities)
    results = c.collect.to_a
    assert_equal 2, results.size
    results.each do |r|
      assert_kind_of String, r[:content]
      assert_match %r{\Aruby/ruby:rdoc/trunk/}, r[:source]
    end
    sources = results.map { |r| r[:source] }
    assert_include sources, 'ruby/ruby:rdoc/trunk/String'
  end

  def test_since_and_before_are_ignored
    entities = [build_entity('A')]
    c = build_collector(entities)
    r1 = c.collect(since: '2020-01-01', before: '2020-01-02').to_a
    fresh_baseline = RubyRdocCollector::SourceHashBaseline.new(path: File.join(@dir, 'baseline2.yml'))
    c2 = build_collector(entities, baseline: fresh_baseline, output_dir: File.join(@dir, 'out2'))
    r2 = c2.collect.to_a
    assert_equal r1.map { |r| r[:source] }, r2.map { |r| r[:source] }
    assert_equal r1.map { |r| r[:content] }, r2.map { |r| r[:content] }
  end

  def with_env(vars)
    saved = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| ENV[k] = v }
  end

  def test_targets_env_filters_to_listed_classes_only
    entities = [build_entity('Keep1'), build_entity('Drop'), build_entity('Keep2')]
    c = build_collector(entities)
    results = with_env('RUBY_RDOC_TARGETS' => 'Keep1, Keep2') { c.collect.to_a }
    sources = results.map { |r| r[:source] }
    assert_equal 2, results.size
    assert_include sources, 'ruby/ruby:rdoc/trunk/Keep1'
    assert_include sources, 'ruby/ruby:rdoc/trunk/Keep2'
    assert_not_include sources, 'ruby/ruby:rdoc/trunk/Drop'
  end

  def test_max_methods_env_caps_methods_per_class
    methods = (1..10).map do |i|
      RubyRdocCollector::MethodEntry.new(name: "m#{i}", call_seq: nil, description: "d#{i}")
    end
    entity = RubyRdocCollector::ClassEntity.new(
      name: 'Big', description: 'desc', methods: methods, constants: [], superclass: 'Object'
    )
    c = build_collector([entity])
    results = with_env('RUBY_RDOC_MAX_METHODS' => '3') { c.collect.to_a }
    assert_equal 1, results.size
    # content should include only first 3 methods
    content = results.first[:content]
    assert_include content, '### m1'
    assert_include content, '### m3'
    assert_not_include content, '### m4'
  end

  def test_english_description_appears_verbatim_in_content
    methods = [
      RubyRdocCollector::MethodEntry.new(name: 'greet', call_seq: nil, description: 'Says hello.')
    ]
    entity = RubyRdocCollector::ClassEntity.new(
      name: 'Greeter', description: 'A greeter class.', methods: methods, constants: [], superclass: 'Object'
    )
    c = build_collector([entity])
    results = c.collect.to_a
    content = results.first[:content]
    assert_include content, 'A greeter class.'
    assert_include content, 'Says hello.'
    assert_not_include content, '<details>'
  end
end
```

**削除:** `test_partial_failure_skips_single_class_not_whole_batch` / `test_all_methods_translated_in_parallel` / `test_method_translation_error_per_method_does_not_kill_class` / `test_en_description_and_method_descriptions_wired_to_formatter` は Translator 依存なので完全削除、了解。

---

### Task A5: test_collector_streaming.rb を英語 only に書き換え

**Files:**
- Modify: `collector/test/test_collector_streaming.rb`

- [ ] **Step 1: Translator / cache 依存行と claude 並列性テストを削除**

以下 7 テストを**削除:**
- `test_class_workers_overlap_claude_calls_wall_time` (claude wall time 前提)
- `test_yield_is_serialized_across_class_workers` (class 並列前提)
- `test_parallel_class_processing_preserves_all_records` (class 並列前提)
- `test_parallel_processing_persists_all_baseline_entries` (class 並列前提、serial でも通るので残しても可 → **残す**に変更)

実際の削除対象は上記 wall time / parallel 3 件だけ、確認。

- [ ] **Step 2: setup から Translator / TranslationCache 参照を削除**

`setup` の以下を置換:

```ruby
# 変更前
cache        = RubyRdocCollector::TranslationCache.new(cache_dir: File.join(@dir, 'cache'))
@translator  = RubyRdocCollector::Translator.new(
  runner: EchoRunner.new(response: 'JP'), cache: cache, sleeper: ->(_s) {}
)

# 変更後 (削除)
```

すなわち setup は:

```ruby
def setup
  @dir         = Dir.mktmpdir('collector_stream')
  @baseline    = RubyRdocCollector::SourceHashBaseline.new(path: File.join(@dir, 'baseline.yml'))
  @output_dir  = File.join(@dir, 'out')
end
```

- [ ] **Step 3: fast-path テスト 3 件の `translator:` kwarg を削除**

該当テスト内の `RubyRdocCollector::Collector.new({}, ...)` 呼び出しから `translator: @translator,` 行を削除（3 箇所: `test_fast_path_skips_parse_when_tarball_unchanged_and_last_run_completed`, `test_fast_path_triggers_only_when_baseline_completed`, `test_parser_receives_targets_when_smoke_active`, `test_parser_receives_nil_targets_when_smoke_inactive`, `test_default_output_dir_under_tmp`）。

- [ ] **Step 4: 削除対象テスト 3 件を削除**

`test_class_workers_overlap_claude_calls_wall_time` / `test_yield_is_serialized_across_class_workers` / `test_parallel_class_processing_preserves_all_records` の 3 テスト丸ごと削除、了解。

- [ ] **Step 5: テスト実行（この時点ではまだ red 想定、次 Task A6 で green 化）**

```bash
bundle exec rake test TEST=test/test_collector_streaming.rb
```

Expected: `NameError: uninitialized constant` 系、または Collector#initialize が `translator:` を要求して fail、確認。

---

### Task A6: Collector.rb を簡略化（translator 撤去 + serial 化）

**Files:**
- Modify: `collector/lib/ruby_rdoc_collector/collector.rb`

- [ ] **Step 1: ファイル全体を置換**

```ruby
require 'fileutils'

module RubyRdocCollector
  class Collector
    SOURCE_PREFIX = 'ruby/ruby:rdoc/trunk'

    attr_reader :output_dir

    def initialize(config,
                   fetcher:     nil,
                   parser:      nil,
                   formatter:   nil,
                   baseline:    nil,
                   output_dir:  nil,
                   file_writer: nil)
      @config      = config || {}
      @fetcher     = fetcher    || TarballFetcher.new(
        url: @config['url'] || TarballFetcher::DEFAULT_URL
      )
      @parser      = parser     || HtmlParser.new
      @formatter   = formatter  || MarkdownFormatter.new
      @baseline    = baseline   || SourceHashBaseline.new
      @output_dir  = output_dir || default_output_dir
      @file_writer = file_writer || method(:default_file_write)
    end

    def collect(since: nil, before: nil, &block)
      return enum_for(:collect, since: since, before: before) unless block_given?

      content_dir = @fetcher.fetch

      return if @fetcher.unchanged? && @baseline.completed? && !smoke_filter_active?

      smoke = smoke_filter_active?
      @baseline.mark_started unless smoke

      targets  = smoke_targets
      entities = @parser.parse(content_dir, targets: targets)
      entities = apply_max_methods_filter(entities)

      entities.each { |entity| process_entity(entity, &block) }

      unless smoke
        @baseline.cleanup_orphans unless entities.empty?
        @baseline.mark_completed
      end
    end

    private

    def smoke_targets
      raw = ENV['RUBY_RDOC_TARGETS']
      return nil if raw.nil? || raw.strip.empty?
      raw.split(',').map(&:strip)
    end

    def smoke_filter_active?
      return true if smoke_targets
      max_methods = ENV['RUBY_RDOC_MAX_METHODS']&.to_i
      max_methods && max_methods > 0
    end

    def process_entity(entity, &block)
      @baseline.mark_seen(entity.name)
      new_hash = @baseline.hash_for(entity)
      return unless @baseline.changed?(entity.name, new_hash)

      content  = @formatter.format(entity)
      record   = { content: content, source: "#{SOURCE_PREFIX}/#{entity.name}" }

      filename = sanitize_filename(entity.name) + '.md'
      begin
        @file_writer.call(@output_dir, filename, record[:content])
      rescue => e
        warn "[RubyRdocCollector::Collector] file save failed for #{entity.name}: #{e.message}"
        return
      end

      begin
        block.call(record)
      rescue => e
        warn "[RubyRdocCollector::Collector] yield failed for #{entity.name}: #{e.message}"
        return
      end

      @baseline.persist_one(entity.name, new_hash)
    end

    def sanitize_filename(class_name)
      class_name.gsub('::', '__').gsub(/[^A-Za-z0-9_\-]/, '_')
    end

    def default_output_dir
      "/tmp/ruby-rdoc-#{Time.now.strftime('%Y%m%d%H%M%S')}"
    end

    def default_file_write(dir, filename, content)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, filename), content)
    end

    def apply_max_methods_filter(entities)
      max_methods = ENV['RUBY_RDOC_MAX_METHODS']&.to_i
      return entities unless max_methods && max_methods > 0
      entities.map { |e| e.with(methods: e.methods.first(max_methods)) }
    end
  end
end
```

**削除した要素:** `THREAD_POOL_SIZE` / `CLASS_POOL_SIZE` 定数、`translator:` kwarg + `@translator` ivar、`process_entities_in_pool` (→ `entities.each` に置換)、`yield_mutex` 引数、`safe_translate_and_format`、`parallel_translate`、`Translator::TranslationError` rescue、了解。

- [ ] **Step 2: collector 系 3 テスト実行で green 確認**

```bash
bundle exec rake test TEST=test/test_collector.rb
bundle exec rake test TEST=test/test_collector_streaming.rb
```

Expected: 全 pass、確認。

- [ ] **Step 3: commit**

```bash
git add lib/ruby_rdoc_collector/collector.rb test/test_collector.rb test/test_collector_streaming.rb test/test_helper.rb
git commit -m "$(cat <<'EOF'
refactor: remove translation pipeline from Collector

Strip translator: kwarg, safe_translate_and_format, parallel_translate,
THREAD_POOL_SIZE, CLASS_POOL_SIZE, and class-level threading pool.
Collector now processes entities serially via entities.each and calls
MarkdownFormatter#format(entity) directly. English RDoc content flows
through unchanged; no haiku calls.

Also trim test_helper of EchoRunner/FailingRunner/StubRunner and drop
translator: wiring from build_collector factory.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task A7: Translator / TranslationCache / ClaudeSemaphore の lib + test を削除

**Files:**
- Delete: `collector/lib/ruby_rdoc_collector/translator.rb`
- Delete: `collector/lib/ruby_rdoc_collector/translation_cache.rb`
- Delete: `collector/lib/ruby_rdoc_collector/claude_semaphore.rb`
- Delete: `collector/test/test_translator.rb`
- Delete: `collector/test/test_translation_cache.rb`
- Delete: `collector/test/test_claude_semaphore.rb`

- [ ] **Step 1: 6 ファイルを削除**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector
rm lib/ruby_rdoc_collector/translator.rb \
   lib/ruby_rdoc_collector/translation_cache.rb \
   lib/ruby_rdoc_collector/claude_semaphore.rb \
   test/test_translator.rb \
   test/test_translation_cache.rb \
   test/test_claude_semaphore.rb
```

- [ ] **Step 2: lib/ruby_rdoc_collector.rb から require を除去**

**変更前:**
```ruby
require_relative 'ruby_rdoc_collector/class_entity'
require_relative 'ruby_rdoc_collector/translation_cache'
require_relative 'ruby_rdoc_collector/claude_semaphore'
require_relative 'ruby_rdoc_collector/markdown_formatter'
require_relative 'ruby_rdoc_collector/translator'
require_relative 'ruby_rdoc_collector/tarball_fetcher'
require_relative 'ruby_rdoc_collector/html_parser'
require_relative 'ruby_rdoc_collector/source_hash_baseline'
require_relative 'ruby_rdoc_collector/collector'
```

**変更後:**
```ruby
require_relative 'ruby_rdoc_collector/class_entity'
require_relative 'ruby_rdoc_collector/markdown_formatter'
require_relative 'ruby_rdoc_collector/tarball_fetcher'
require_relative 'ruby_rdoc_collector/html_parser'
require_relative 'ruby_rdoc_collector/source_hash_baseline'
require_relative 'ruby_rdoc_collector/collector'
```

- [ ] **Step 3: 全テスト実行で green 確認**

```bash
bundle exec rake test
```

Expected: 全テスト pass、了解。失敗する場合は Translator / TranslationCache / ClaudeSemaphore への残存参照があるので grep して除去。

```bash
grep -rn "Translator\|TranslationCache\|ClaudeSemaphore\|translation_cache\|claude_semaphore" lib/ test/
```

Expected: 何もヒットせず、確認。

- [ ] **Step 4: commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore: delete translator / translation_cache / claude_semaphore

Upfront Japanese translation is no longer part of the pipeline.
On-demand JP query translation and bilingual display moved to the
host LLM (Claude Code) agent, guided by chiebukuro-mcp meta hints.

Remove:
- lib/ruby_rdoc_collector/translator.rb
- lib/ruby_rdoc_collector/translation_cache.rb
- lib/ruby_rdoc_collector/claude_semaphore.rb
- matching test files
- require_relative lines in lib/ruby_rdoc_collector.rb

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task A8: README.md を英語 only パイプラインに書き換え

**Files:**
- Modify: `collector/README.md`

- [ ] **Step 1: README.md 全体を置換**

```markdown
# ruby_rdoc_collector

Collector that downloads pre-built RDoc darkfish HTML from `cache.ruby-lang.org`, parses per-class data, and streams `{content:, source:}` records to the [ruby-knowledge-db](https://github.com/bash0C7/ruby-knowledge-db) pipeline. Content is stored in English as-is; on-demand Japanese translation for queries and display is handled by the host LLM agent downstream (see chiebukuro-mcp meta hints).

## Data source

`https://cache.ruby-lang.org/pub/ruby/doc/ruby-docs-en-master.tar.xz`

Generated daily by [ruby/actions docs.yml](https://github.com/ruby/actions/blob/master/.github/workflows/docs.yml) — `make html` on ruby/ruby master.

## DB source value

`ruby/ruby:rdoc/trunk/{ClassName}` — one record per class.

## Streaming API

```ruby
require 'ruby_rdoc_collector'

collector = RubyRdocCollector::Collector.new({})

# Block form: one record streamed per yield
collector.collect do |record|
  store.store(record[:content], source: record[:source])
end

# No-block form: lazy Enumerator
collector.collect.each { |record| ... }

# Discover the run's intermediate MD directory (for debugging)
collector.output_dir
```

## Intermediate MD files

Each yielded record's content is also written to `/tmp/ruby-rdoc-<YYYYmmddHHMMSS>/<SanitizedClassName>.md` as a debug artifact. Filenames sanitize `::` → `__` and non-`[A-Za-z0-9_-]` → `_`.

## source_hash baseline

Per-class SHA256 (description + superclass + each method's name/call_seq/description) is persisted to `~/.cache/ruby-rdoc-collector/source_hashes.yml`. Unchanged classes are skipped silently; yield-failure leaves the baseline untouched so the next run retries.

The baseline file is a two-phase bookmark: `mark_started` is written at the top of a non-smoke collect, `mark_completed` only after `cleanup_orphans` finishes. A run that is started but not completed is treated as WIP and re-processed on the next call.

## Fast path

If `fetcher.unchanged?` (tarball SHA matches the last run) AND `baseline.completed?` AND smoke filters are inactive, `collect` returns immediately without parsing. Any change to either the tarball or baseline WIP state re-engages the full pipeline.

## Smoke / escape hatches

- `RUBY_RDOC_TARGETS=ClassA,ClassB` — only parse listed classes
- `RUBY_RDOC_MAX_METHODS=N` — cap methods per class to first N

Smoke runs never advance the completion marker and never orphan-cleanup.

## Cache

`~/.cache/ruby-rdoc-collector/tarball/` holds the downloaded `ruby-docs-en-master.tar.xz` and its extracted content. Subsequent runs reuse it unless the upstream SHA changes.
```

- [ ] **Step 2: commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs(readme): rewrite for English-only on-demand translation pipeline

Drop mentions of Claude CLI haiku translation, translation cache,
claude semaphore, class-level parallelism, and chdir persona escape.
Add note that Japanese translation is downstream (host LLM agent
responsibility via chiebukuro-mcp meta hints).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task A9: push collector changes

- [ ] **Step 1: push**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector
git push origin main
```

---

## Phase B: dotfiles meta YAML update

### Task B1: ruby_knowledge.yml の hints.note を書き換え

**Files:**
- Modify: `dotfiles/scripts/meta_patches/ruby_knowledge.yml`

- [ ] **Step 1: `columns.memories.source.hints.note` ブロック (L29-37 付近) を置換**

**変更前 (抜粋):**
```yaml
      note: |
        「Ruby」といえば CRuby。PicoRuby は必ず source='picoruby/picoruby:trunk/%' 等で明示。
        semantic_search は trunk/article(AI 生成変更記事)に最も効果的。
        rurema ドキュメントは FTS5 (WHERE source LIKE 'rurema%') が正確。
        rdoc/trunk/ は Ruby master の英語 RDoc API ドキュメントの日本語翻訳版。
        rurema(手書き詳細ドキュメント)と rdoc(最新 API 機械翻訳)は相補的に使い分ける。
        rdoc は Ruby::Box など rurema 未収録の最新クラスもカバーする。
        rdoc/trunk/ のコード例は Prism(Ruby 標準ライブラリ)で解析可能な構文。
        C 拡張メソッドの RDoc コメントは rdoc/parser(Ruby 標準ライブラリ)形式。
```

**変更後:**
```yaml
      note: |
        「Ruby」といえば CRuby。PicoRuby は必ず source='picoruby/picoruby:trunk/%' 等で明示。
        semantic_search は trunk/article(AI 生成変更記事)に最も効果的。
        rurema ドキュメントは FTS5 (WHERE source LIKE 'rurema%') が正確。
        rdoc/trunk/ は Ruby master の英語 RDoc API ドキュメント原文を格納(翻訳なし)。
        rdoc を検索するときは: (1) 日本語 query は先に英訳してから FTS5 / source LIKE に投げる、
        (2) description の和訳が必要なら agent 側で表示時にオンデマンド翻訳し、
        日本語と英語の両表記で提示する。MCP tool 側では翻訳しない(読むだけ原則)。
        rurema(手書き詳細ドキュメント)と rdoc(最新 API 英語原文)は相補的に使い分ける。
        rdoc は Ruby::Box など rurema 未収録の最新クラスもカバーする。
        rdoc/trunk/ のコード例は Prism(Ruby 標準ライブラリ)で解析可能な構文。
        C 拡張メソッドの RDoc コメントは rdoc/parser(Ruby 標準ライブラリ)形式。
```

- [ ] **Step 2: dotfiles リポジトリで commit**

```bash
cd "/Users/bash/Library/Mobile Documents/com~apple~CloudDocs/dotfiles"
git add chiebukuro-mcp/chiebukuro-mcp/scripts/meta_patches/ruby_knowledge.yml
git commit -m "$(cat <<'EOF'
chore(meta): mark ruby_knowledge rdoc source as English-only

rdoc/trunk/ now stores English RDoc verbatim (no upfront translation).
Instruct agents to translate JP queries to EN before FTS5 / source LIKE
and to render bilingual on-demand when displaying description.
MCP tools do not translate (read-only principle).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task B2: apply_meta_patches で production DB の `_sqlite_mcp_meta` 更新

- [ ] **Step 1: apply_meta_patches 実行 (chiebukuro-mcp リポジトリに script あり)**

```bash
cd "/Users/bash/Library/Mobile Documents/com~apple~CloudDocs/dotfiles/chiebukuro-mcp/chiebukuro-mcp"
# scripts/apply_meta_patches.rb がある前提。path 要確認
ls scripts/apply_meta_patches.rb
```

Expected: ファイル存在確認、了解。

- [ ] **Step 2: production DB に対して apply**

```bash
cd "/Users/bash/Library/Mobile Documents/com~apple~CloudDocs/dotfiles/chiebukuro-mcp/chiebukuro-mcp"
APP_ENV=production bundle exec ruby scripts/apply_meta_patches.rb \
  --db /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/db/ruby_knowledge.db \
  --patch scripts/meta_patches/ruby_knowledge.yml
```

Expected: `INSERT OR REPLACE` 行数が出力される、確認。実際の invocation 形式は apply_meta_patches.rb の help に従うこと — 形式がこれと違う場合はスクリプトを `ruby scripts/apply_meta_patches.rb --help` で確認、了解。

**Note:** apply_meta_patches.rb は dotfiles 側資産で本 plan の scope 外、インタラクティブ形式は script 側の契約に従う、確認。

---

## Phase C: ruby-knowledge-db cleanup rake task

### Task C1: test_ruby_rdoc_update.rb を英語 only に整合

**Files:**
- Modify: `db/test/test_ruby_rdoc_update.rb`

- [ ] **Step 1: setup から Translator / TranslationCache 依存を削除**

`setup` を以下に置換:

```ruby
def setup
  @dir         = Dir.mktmpdir('rdoc_update')
  @baseline    = RubyRdocCollector::SourceHashBaseline.new(path: File.join(@dir, 'baseline.yml'))
  @output_dir  = File.join(@dir, 'out')
end
```

- [ ] **Step 2: build_collector ヘルパーおよびテスト内で `translator:` 参照を削除**

該当ファイル内全箇所の `translator: @translator` / `RubyRdocCollector::Translator.new(...)` を除去、確認。

- [ ] **Step 3: テスト実行で green 確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
bundle exec rake test TEST=test/test_ruby_rdoc_update.rb
```

Expected: 全 pass、了解。

---

### Task C2: db:delete_rdoc rake task — 失敗するテストを追加

**Files:**
- Create: `db/test/test_rake_db_delete_rdoc.rb`

- [ ] **Step 1: 新規テストファイル作成**

```ruby
# frozen_string_literal: true

require_relative 'test_helper'
require 'sqlite3'
require 'sqlite_vec'

# Integration test for the `rake db:delete_rdoc` contract:
# Deletes all rows in memories / memories_vec / memories_fts where
# source LIKE 'ruby/ruby:rdoc/trunk/%'. Non-rdoc rows are preserved.

class TestRakeDbDeleteRdoc < Test::Unit::TestCase
  def setup
    @dir     = Dir.mktmpdir('delete_rdoc')
    @db_path = File.join(@dir, 'test.db')
    # Build a minimal schema compatible with ruby-knowledge-store 001_schema.sql
    db = SQLite3::Database.new(@db_path)
    db.enable_load_extension(true); SqliteVec.load(db); db.enable_load_extension(false)
    db.execute_batch(<<~SQL)
      CREATE TABLE memories (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        content      TEXT    NOT NULL,
        source       TEXT    NOT NULL,
        content_hash TEXT    NOT NULL UNIQUE,
        embedding    BLOB,
        created_at   TEXT    NOT NULL
      );
      CREATE VIRTUAL TABLE memories_fts USING fts5(content, content='memories', content_rowid='id', tokenize='trigram');
      CREATE VIRTUAL TABLE memories_vec USING vec0(memory_id INTEGER PRIMARY KEY, embedding FLOAT[768]);
      CREATE TRIGGER memories_ai AFTER INSERT ON memories BEGIN
        INSERT INTO memories_fts(rowid, content) VALUES (new.id, new.content);
      END;
      CREATE TRIGGER memories_ad AFTER DELETE ON memories BEGIN
        INSERT INTO memories_fts(memories_fts, rowid, content) VALUES('delete', old.id, old.content);
      END;
    SQL
    # Seed 3 rows: 2 rdoc + 1 rurema
    emb = Array.new(768, 0.1).pack('f*')
    db.execute("INSERT INTO memories(content, source, content_hash, created_at) VALUES(?, ?, ?, datetime('now'))",
      ['# ARGF', 'ruby/ruby:rdoc/trunk/ARGF', 'hash_argf'])
    db.execute("INSERT INTO memories_vec(memory_id, embedding) VALUES(?, ?)", [db.last_insert_row_id, emb])
    db.execute("INSERT INTO memories(content, source, content_hash, created_at) VALUES(?, ?, ?, datetime('now'))",
      ['# Addrinfo', 'ruby/ruby:rdoc/trunk/Addrinfo', 'hash_addrinfo'])
    db.execute("INSERT INTO memories_vec(memory_id, embedding) VALUES(?, ?)", [db.last_insert_row_id, emb])
    db.execute("INSERT INTO memories(content, source, content_hash, created_at) VALUES(?, ?, ?, datetime('now'))",
      ['rurema content', 'rurema/doctree:ruby4.0/core', 'hash_rurema'])
    db.execute("INSERT INTO memories_vec(memory_id, embedding) VALUES(?, ?)", [db.last_insert_row_id, emb])
    db.close
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def count_rows
    db = SQLite3::Database.new(@db_path)
    db.enable_load_extension(true); SqliteVec.load(db); db.enable_load_extension(false)
    m   = db.get_first_value('SELECT count(*) FROM memories')
    v   = db.get_first_value('SELECT count(*) FROM memories_vec')
    fts = db.get_first_value('SELECT count(*) FROM memories_fts')
    db.close
    [m, v, fts]
  end

  def test_delete_rdoc_removes_rdoc_rows_only
    # Load the Rake file so that the task is registered
    Rake.application.rake_require('Rakefile', [Dir.pwd], [])
    # Stub ensure_write_host! for test env
    RubyKnowledgeDb::Config.define_singleton_method(:ensure_write_host!) { nil }
    # Stub db_path to our test DB via Config load
    original = RubyKnowledgeDb::Config.method(:load)
    RubyKnowledgeDb::Config.define_singleton_method(:load) { { 'db_path' => @db_path } }

    before = count_rows
    assert_equal [3, 3, 3], before

    Rake::Task['db:delete_rdoc'].reenable
    Rake::Task['db:delete_rdoc'].invoke

    after = count_rows
    assert_equal [1, 1, 1], after, "only rurema row should remain"

    # Confirm remaining row is rurema
    db = SQLite3::Database.new(@db_path)
    source = db.get_first_value("SELECT source FROM memories")
    db.close
    assert_equal 'rurema/doctree:ruby4.0/core', source
  ensure
    RubyKnowledgeDb::Config.define_singleton_method(:load, &original) if original
  end
end
```

**Note:** `RubyKnowledgeDb::Config.load` の stub 形式が既存コードと合わない場合、既存 `test_helper.rb` や `test_ruby_rdoc_update.rb` のパターンを参照して合わせること、確認。特に `ensure_write_host!` の stub 方法は既存テストを模倣、了解。

- [ ] **Step 2: テスト実行で red 確認**

```bash
bundle exec rake test TEST=test/test_rake_db_delete_rdoc.rb
```

Expected: `Don't know how to build task 'db:delete_rdoc'`、確認。

---

### Task C3: rake db:delete_rdoc を実装

**Files:**
- Modify: `db/Rakefile` (namespace `:db` 内に追加)

- [ ] **Step 1: Rakefile の `namespace :db` 内、`delete_polluted` の直下に追加**

```ruby
  desc "Delete all rdoc rows (memories + memories_vec + memories_fts). WHERE source LIKE 'ruby/ruby:rdoc/trunk/%'"
  task :delete_rdoc do
    require_base
    require 'sqlite3'
    require 'sqlite_vec'
    RubyKnowledgeDb::Config.ensure_write_host!

    cfg = RubyKnowledgeDb::Config.load
    db_path = File.expand_path(cfg['db_path'], __dir__)
    abort "DB not found: #{db_path}" unless File.exist?(db_path)

    db = SQLite3::Database.new(db_path)
    db.enable_load_extension(true); SqliteVec.load(db); db.enable_load_extension(false)

    before_m = db.get_first_value('SELECT count(*) FROM memories')
    before_rdoc = db.get_first_value("SELECT count(*) FROM memories WHERE source LIKE 'ruby/ruby:rdoc/trunk/%'")
    puts "before: memories=#{before_m} (rdoc=#{before_rdoc})"

    ids = db.execute("SELECT id FROM memories WHERE source LIKE 'ruby/ruby:rdoc/trunk/%'").flatten
    ids.each do |id|
      db.execute('DELETE FROM memories_vec WHERE memory_id=?', id)
      db.execute('DELETE FROM memories WHERE id=?', id)
    end

    after_m   = db.get_first_value('SELECT count(*) FROM memories')
    after_v   = db.get_first_value('SELECT count(*) FROM memories_vec')
    after_fts = db.get_first_value('SELECT count(*) FROM memories_fts')
    puts "after:  memories=#{after_m} memories_vec=#{after_v} memories_fts=#{after_fts} (deleted=#{ids.size})"
    if after_m == after_v && after_m == after_fts
      puts "OK: all three tables aligned"
    else
      warn "WARN: table counts diverged — investigate"
    end
    db.close
  end
```

- [ ] **Step 2: テスト実行で green 確認**

```bash
bundle exec rake test TEST=test/test_rake_db_delete_rdoc.rb
```

Expected: 全 pass、確認。

- [ ] **Step 3: 全テスト実行で regression 無いことを確認**

```bash
bundle exec rake test
```

Expected: 全 pass、了解。

- [ ] **Step 4: commit**

```bash
git add Rakefile test/test_rake_db_delete_rdoc.rb test/test_ruby_rdoc_update.rb
git commit -m "$(cat <<'EOF'
feat(rake): add db:delete_rdoc and drop translator stubs from rdoc tests

- Add db:delete_rdoc task that removes all ruby/ruby:rdoc/trunk/%
  rows from memories + memories_vec (memories_fts cleaned via trigger)
- Host guard via Config.ensure_write_host! prevents accidental
  production mutation from a dev machine
- Update test_ruby_rdoc_update.rb setup to match Translator-less
  collector after upstream refactor

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task C4: CLAUDE.md の rdoc 記述を更新

**Files:**
- Modify: `db/CLAUDE.md`

- [ ] **Step 1: `ruby/ruby:rdoc/trunk/{ClassName}` の source 説明を更新**

**変更前 (`## source 値の規約` テーブル内):**
```
| `ruby/ruby:rdoc/trunk/{ClassName}` | ruby/ruby trunk RDoc の日本語翻訳版(ruby-rdoc-collector)|
```

**変更後:**
```
| `ruby/ruby:rdoc/trunk/{ClassName}` | ruby/ruby trunk RDoc の英語原文(ruby-rdoc-collector)。JP query の英訳と和訳表示は chiebukuro-mcp 経由のホスト LLM agent が担当 |
```

- [ ] **Step 2: `ruby-rdoc-collector` の ### 節を更新**

該当節（`ruby-rdoc-collector は ...` で始まるブロック）で `Claude CLI haiku で日本語翻訳` / `翻訳キャッシュ` / `chdir:'/tmp'` / `v3 キー` に関する記述を以下に圧縮:

**変更前 (該当段落):**
```
`ruby-rdoc-collector` は `https://cache.ruby-lang.org/pub/ruby/doc/ruby-docs-en-master.tar.xz` を `~/.cache/ruby-rdoc-collector/tarball/` にダウンロード・展開する。ruby/ruby clone は不要(`cache:prepare` 依存なし)。翻訳キャッシュは `~/.cache/ruby-rdoc-collector/translations/` に SHA256 キー(`v2|haiku|<text>` フォーマット)で保存。Translator は `claude --model haiku -p -` を `chdir: '/tmp'` で起動し `~/CLAUDE.md` の persona 漏洩を防ぐ。smoke test 用エスケープハッチとして `RUBY_RDOC_TARGETS=ClassA,ClassB` / `RUBY_RDOC_MAX_METHODS=20` env var を Collector が認識する(default は無制限)。
```

**変更後:**
```
`ruby-rdoc-collector` は `https://cache.ruby-lang.org/pub/ruby/doc/ruby-docs-en-master.tar.xz` を `~/.cache/ruby-rdoc-collector/tarball/` にダウンロード・展開する。ruby/ruby clone は不要(`cache:prepare` 依存なし)。**コンテンツは英語原文のまま格納**され、翻訳は chiebukuro-mcp 経由のホスト LLM agent がオンデマンドで行う(meta YAML の `columns.memories.source.hints.note` に指示)。smoke test 用エスケープハッチとして `RUBY_RDOC_TARGETS=ClassA,ClassB` / `RUBY_RDOC_MAX_METHODS=20` env var を Collector が認識する(default は無制限)。
```

- [ ] **Step 2b: `db:delete_rdoc` について記述を追加**

`## 重要な実装メモ` セクションの適切な位置（`### sqlite3 CLI 禁止(sqlite_vec 経由必須)` の直前）に追加:

```markdown
### db:delete_rdoc: rdoc ソース全削除

```bash
APP_ENV=production bundle exec rake db:delete_rdoc
```

`ruby/ruby:rdoc/trunk/%` な行を memories + memories_vec から削除(memories_fts は trigger で自動追従)。パイプライン設計変更(日本語翻訳 → 英語原文)に伴う一括切り替え時や、baseline が壊れた時の escape hatch として使用。host guard 有効(`ensure_write_host!`)。
```

- [ ] **Step 3: commit**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(claude-md): update rdoc description for English-only pipeline

- rdoc source now stores English verbatim; query translation and
  bilingual rendering moved to chiebukuro-mcp host LLM agent
- Add db:delete_rdoc to the implementation memo section

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task C5: push db changes

- [ ] **Step 1: push**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
git push origin main
```

---

## Phase D: Production rollout

### Task D1: production DB の rdoc 行を削除

- [ ] **Step 1: 削除前の行数を確認**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
APP_ENV=production bundle exec rake db:stats 2>&1 | grep -E "rdoc|memories total"
```

Expected: `ruby/ruby:rdoc/trunk/%` で 4 行くらい、確認。

- [ ] **Step 2: delete_rdoc 実行**

```bash
APP_ENV=production bundle exec rake db:delete_rdoc
```

Expected: `before: memories=N (rdoc=4)` → `after: memories=N-4 ... (deleted=4)` → `OK: all three tables aligned`、了解。

---

### Task D2: baseline + translation キャッシュ削除

- [ ] **Step 1: baseline YAML 3 種削除（APP_ENV 別）**

```bash
rm -f ~/.cache/ruby-rdoc-collector/source_hashes.production.yml \
      ~/.cache/ruby-rdoc-collector/source_hashes.development.yml \
      ~/.cache/ruby-rdoc-collector/source_hashes.test.yml \
      ~/.cache/ruby-rdoc-collector/source_hashes.yml
ls ~/.cache/ruby-rdoc-collector/
```

Expected: `tarball/` のみ残る、確認。

- [ ] **Step 2: 旧 translation キャッシュ削除**

```bash
rm -rf ~/.cache/ruby-rdoc-collector/translations/
ls ~/.cache/ruby-rdoc-collector/
```

Expected: `tarball/` のみ、了解。

---

### Task D3: 英語 only パイプラインでフルラン

- [ ] **Step 1: rake update:ruby_rdoc をバックグラウンド実行**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
APP_ENV=production bundle exec rake update:ruby_rdoc 2>&1 | tee /tmp/update_ruby_rdoc_en.log
```

Expected: haiku 呼び出しゼロ、embedder (ruri-v3) 呼び出しのみ、完走まで数分、確認。

- [ ] **Step 2: 結果確認**

```bash
tail -3 /tmp/update_ruby_rdoc_en.log
```

Expected: `ruby_rdoc: stored=<N>, skipped=0, errors=0`、了解。

- [ ] **Step 3: DB stats で反映確認**

```bash
APP_ENV=production bundle exec rake db:stats 2>&1 | grep -E "rdoc|memories total"
```

Expected: rdoc source 数百件に増えてる、確認。

---

## Phase E: Agent 振る舞い検証（manual）

### Task E1: chiebukuro-mcp 経由で日本語クエリ挙動確認

**Files:** なし(manual verification)

- [ ] **Step 1: Claude Code で chiebukuro-mcp を使って日本語クエリ実行**

例:
> chiebukuro-mcp で「Array クラスの first メソッドの説明を教えて」を日本語で query してみる。

Expected:
- agent が `schema://` / `hints://` を参照して `columns.memories.source.hints.note` を読み取り、
- 日本語 query の中のキーワード `Array` / `first` を英訳してから `chiebukuro_query` or `chiebukuro_semantic_search` に投げる、
- 結果の英語 description を取得して、agent が和訳 + 英語両表記で提示する、
- 確認。

- [ ] **Step 2: 振る舞いが期待通りでない場合の調整**

もし agent が和訳せずに英語結果を素でそのまま投げ返す場合は、`hints.note` の文面を強化する（Task B1 に戻って修正）、了解。

---

## Self-Review Notes

- [x] **Spec coverage:** spec 5 項目（メタ YAML 更新、Collector 簡略化、既存データ cleanup、ruri-v3 embedding、agent 振る舞い指示）に対し、Phase A/B/C/D/E が 1:1 対応、確認。
- [x] **Placeholder scan:** TBD / TODO なし、コードブロックは全て完全、了解。
- [x] **Type consistency:** `MarkdownFormatter#format(entity)` 新 signature は Task A2 で定義、Task A6 の Collector で参照、Task A4 テストで検証、整合。`db:delete_rdoc` は Task C2 test → C3 実装で符号、了解。
- [x] **Scope:** 単一パイプラインの書き換え、3 リポジトリに跨るが独立ユニット、評価。
