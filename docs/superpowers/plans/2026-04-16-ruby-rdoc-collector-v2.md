# ruby-rdoc-collector Implementation Plan (v2 — Tarball-based)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new docs collector `ruby-rdoc-collector` that downloads the pre-built RDoc darkfish HTML tarball from `cache.ruby-lang.org`, parses class/method data from `search_data.js` + HTML files, translates English descriptions to Japanese via Claude CLI (sonnet) with SHA256 cache, and stores class-unit Markdown into the knowledge DB under `ruby/ruby:rdoc/trunk/{ClassName}`.

**Architecture:** Tarball-first approach. The `ruby/actions` GitHub Actions pipeline already generates RDoc HTML for all Ruby versions daily and uploads to S3. We download `ruby-docs-en-master.tar.xz`, extract it, parse `search_data.js` (13k+ entries index) for class/method discovery, then parse individual darkfish HTML files for full descriptions and `call_seq`. Translation goes through Claude CLI (sonnet) with per-text-block SHA256 cache. No rdoc gem, no ruby/ruby clone, no `cache:prepare` dependency.

**Tech Stack:** Ruby 3.2+ (`Data.define`), Oga (Pure Ruby HTML parser, no native extensions), Claude CLI (`claude --model sonnet -p -`), plain-file cache with atomic rename, `test-unit` xUnit style, `Open3.capture2e`/`capture3` for subprocess.

**Key change from v1:** `rdoc --format=json` does not exist. RDoc only generates darkfish HTML. The official `docs.ruby-lang.org/en/` pipeline (see `ruby/actions/.github/workflows/docs.yml`) runs `make html` and uploads tarballs to S3. We consume those tarballs directly.

**Translation context:** 翻訳プロンプトには、ドキュメント中の Ruby コードは [Prism](https://docs.ruby-lang.org/en/master/Prism.html)（標準ライブラリ）で解析可能な構文であること、C 言語の RDoc コメントは [rdoc/parser](https://docs.ruby-lang.org/ja/latest/library/rdoc=2fparser.html)（標準ライブラリ）形式であることをコンテキストとして与える。これにより Claude がコード片の構造を正しく理解した上で翻訳を行える。

---

## Repository layout

Two repositories are touched by this plan:

1. **New gem:** `/Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector/` (brand new `git init`)
2. **Integration:** `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/` (Stage 3 wiring), in worktree `../ruby-knowledge-db-rdoc/`

Plus one satellite repo:

3. **Store source_prefix:** `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-store/` (Stage 3 Task 3.5)

---

## File Structure

### New gem `../ruby-rdoc-collector/`

| File | Responsibility |
|------|----------------|
| `ruby_rdoc_collector.gemspec` | gem metadata (deps: oga) |
| `Gemfile` | local deps (test-unit, rake) |
| `Rakefile` | `rake test` default |
| `README.md` | usage, data source, cache invariants |
| `.gitignore` | vendor/bundle, *.gem, .bundle |
| `lib/ruby_rdoc_collector.rb` | require aggregation |
| `lib/ruby_rdoc_collector/class_entity.rb` | `ClassEntity` / `MethodEntry` (Data.define) |
| `lib/ruby_rdoc_collector/translation_cache.rb` | SHA256-keyed file cache with atomic write |
| `lib/ruby_rdoc_collector/markdown_formatter.rb` | pure formatter: `ClassEntity` + JP description → Markdown |
| `lib/ruby_rdoc_collector/translator.rb` | Claude CLI wrapper, cache read/write, runner DI, retry |
| `lib/ruby_rdoc_collector/tarball_fetcher.rb` | download tar.xz from cache.ruby-lang.org, extract to cache dir |
| `lib/ruby_rdoc_collector/html_parser.rb` | parse search_data.js + darkfish HTML → `Array<ClassEntity>` |
| `lib/ruby_rdoc_collector/collector.rb` | thin façade implementing the unified `collect(since:, before:)` IF |
| `test/test_helper.rb` | StubRunner, EchoRunner, FailingRunner, fixture loader |
| `test/test_class_entity.rb` | Data struct field check |
| `test/test_translation_cache.rb` | read/write/miss, atomic write |
| `test/test_markdown_formatter.rb` | pure-function snapshot test |
| `test/test_translator.rb` | cache hit/miss, runner retry |
| `test/test_tarball_fetcher.rb` | download DI, extraction, path resolution |
| `test/test_html_parser.rb` | fixture HTML → ClassEntity mapping |
| `test/test_collector.rb` | full DI, partial failure (1 class error skipped) |
| `test/fixtures/search_data.js` | minimal search_data.js with 2 classes + methods |
| `test/fixtures/TestClass.html` | minimal darkfish HTML fixture |
| `test/fixtures/Ruby/Box.html` | minimal darkfish HTML fixture (nested namespace) |
| `bin/poc_smoke.rb` | real Claude CLI PoC smoke script (Stage 2.9) |

### ruby-knowledge-db (modifications, in worktree)

| File | Change |
|------|--------|
| `Gemfile` | **Modify** — add `gem 'ruby_rdoc_collector', path: '../ruby-rdoc-collector'` |
| `config/sources.yml` | **Modify** — add `ruby_rdoc:` key |
| `Rakefile` | **Modify** — `require_update_deps` + `namespace :update` task |
| `scripts/update_all.rb` | **Modify** — require + collectors array entry |
| `CLAUDE.md` | **Modify** — add source 値規約行、依存 repo 表行 |

### ruby-knowledge-store (Stage 3 Task 3.5)

| File | Change |
|------|--------|
| `lib/ruby_knowledge_store/store.rb` | **Modify** — add `when /\Aruby\/ruby:rdoc\/trunk\//` case |
| `test/test_store.rb` | **Modify** — add case coverage test |

---

## Darkfish HTML structure reference

These are the key CSS selectors used by `HtmlParser`:

| Data | Source | Selector / Pattern |
|------|--------|--------------------|
| Class/method index | `js/search_data.js` | `var search_data = {JSON};` → `parsed["index"]` |
| Class description | `{ClassName}.html` | `section.description` → `inner_html` |
| Superclass | `{ClassName}.html` | `#parent-class-section ul > li > a:first` → text |
| Method call_seq | `{ClassName}.html` | `#method-{c,i}-{name} .method-callseq` → text |
| Method description | `{ClassName}.html` | `#method-{c,i}-{name} .method-description` → `inner_html` |

`search_data.js` entry schema:
```json
{"name": "Box", "full_name": "Ruby::Box", "type": "class", "path": "Ruby/Box.html", "snippet": "<p>..."}
```

Types: `class`, `module`, `class_method`, `instance_method`, `constant`.

---

## Stage 0: Worktree setup — DONE

Worktree created at `../ruby-knowledge-db-rdoc/` on branch `feature/ruby-rdoc-collector`.

---

## Stage 1: Probe findings — DONE

Key findings:
- `rdoc --format=json` does not exist
- Data source: `https://cache.ruby-lang.org/pub/ruby/doc/ruby-docs-en-master.tar.xz` (~2.2MB)
- Contains 1,244 HTML files, 1,014 classes, 10,391 methods
- `Ruby::Box` present at `master/Ruby/Box.html`
- Descriptions are HTML (darkfish-rendered from RDoc markup)
- `search_data.js` provides full index with snippets

---

## Stage 2: Gem skeleton (TDD)

**All Stage 2 tasks operate inside `/Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector/` (brand new repo).**

### Task 2.1: Initialize gem repository

**Files:**
- Create: `ruby_rdoc_collector.gemspec`
- Create: `Gemfile`
- Create: `Rakefile`
- Create: `README.md`
- Create: `.gitignore`
- Create: `lib/ruby_rdoc_collector.rb`
- Create: `test/test_helper.rb`

- [ ] **Step 1: Create repo skeleton**

Run:
```bash
mkdir -p /Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector
cd /Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector
git init -b main
mkdir -p lib/ruby_rdoc_collector test/fixtures/Ruby bin
```

- [ ] **Step 2: Write gemspec**

File: `ruby_rdoc_collector.gemspec`

```ruby
Gem::Specification.new do |spec|
  spec.name          = 'ruby_rdoc_collector'
  spec.version       = '0.1.0'
  spec.summary       = 'RDoc HTML collector with JP translation for ruby knowledge DB'
  spec.authors       = ['bash0C7']
  spec.files         = Dir['lib/**/*.rb']
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.2.0'
  spec.add_dependency 'oga'
end
```

- [ ] **Step 3: Write Gemfile**

File: `Gemfile`

```ruby
source 'https://rubygems.org'
gemspec

group :development, :test do
  gem 'test-unit'
  gem 'rake'
end
```

- [ ] **Step 4: Write Rakefile**

File: `Rakefile`

```ruby
require 'rake/testtask'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib' << 'test'
  t.pattern = 'test/test_*.rb'
end
task default: :test
```

- [ ] **Step 5: Write .gitignore**

File: `.gitignore`

```
vendor/bundle
Gemfile.lock
*.gem
.bundle
```

- [ ] **Step 6: Write README**

File: `README.md`

````markdown
# ruby_rdoc_collector

Collector that downloads pre-built RDoc darkfish HTML from `cache.ruby-lang.org`, parses class/method data, translates English descriptions into Japanese via Claude CLI (sonnet), and emits `{content:, source:}` pairs for the [ruby-knowledge-db](https://github.com/bash0C7/ruby-knowledge-db) pipeline.

## Data Source

`https://cache.ruby-lang.org/pub/ruby/doc/ruby-docs-en-master.tar.xz`

Generated daily by [ruby/actions docs.yml](https://github.com/ruby/actions/blob/master/.github/workflows/docs.yml) — `make html` on ruby/ruby master.

## Source value

`ruby/ruby:rdoc/trunk/{ClassName}` — one record per class.

## Caches

| Path | Owner | Content |
|------|-------|---------|
| `~/.cache/ruby-rdoc-collector/tarball/` | this gem | downloaded tar.xz + extracted HTML |
| `~/.cache/ruby-rdoc-collector/translations/` | this gem | SHA256-keyed translation cache |

## Translation cache key

```
SHA256("claude-sonnet::" + html_text)
```

Re-running the collector with unchanged upstream descriptions is a full cache hit with zero Claude CLI calls.

## Usage

```ruby
require 'ruby_rdoc_collector'

collector = RubyRdocCollector::Collector.new(
  'url' => 'https://cache.ruby-lang.org/pub/ruby/doc/ruby-docs-en-master.tar.xz'
)
collector.collect # => [{content:, source:}, ...]
```

## Test

```bash
bundle exec rake test
```
````

- [ ] **Step 7: Write entry point**

File: `lib/ruby_rdoc_collector.rb`

```ruby
require_relative 'ruby_rdoc_collector/class_entity'
require_relative 'ruby_rdoc_collector/translation_cache'
require_relative 'ruby_rdoc_collector/markdown_formatter'
require_relative 'ruby_rdoc_collector/translator'
require_relative 'ruby_rdoc_collector/tarball_fetcher'
require_relative 'ruby_rdoc_collector/html_parser'
require_relative 'ruby_rdoc_collector/collector'

module RubyRdocCollector
end
```

- [ ] **Step 8: Write test helper**

File: `test/test_helper.rb`

```ruby
require 'test/unit'
require 'fileutils'
require 'tmpdir'
require 'json'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'ruby_rdoc_collector'

FIXTURE_DIR = File.expand_path('fixtures', __dir__)

StubRunner = ->(_prompt) { 'これは翻訳されたテキスト。' }

class EchoRunner
  attr_reader :calls

  def initialize(response: 'JP')
    @response = response
    @calls    = 0
  end

  def call(_prompt)
    @calls += 1
    @response
  end
end

class FailingRunner
  attr_reader :calls

  def initialize(fail_count: 1, eventual: 'JP')
    @fail_count = fail_count
    @eventual   = eventual
    @calls      = 0
  end

  def call(_prompt)
    @calls += 1
    if @calls <= @fail_count
      raise RubyRdocCollector::Translator::TranslationError, 'transient'
    end
    @eventual
  end
end
```

- [ ] **Step 9: Install bundle (NOTE: requires all lib files to exist, comment out requires first)**

Temporarily comment out all `require_relative` lines in `lib/ruby_rdoc_collector.rb`, then:

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector
bundle config set --local path 'vendor/bundle'
bundle install
bundle exec rake test
```

Expected: 0 tests, 0 assertions, 0 failures. Exit 0.

Then uncomment the `require_relative` lines (they'll be satisfied as each component is implemented).

- [ ] **Step 10: Commit**

Run:
```bash
git add .
git commit -m "chore: initialize ruby_rdoc_collector gem skeleton"
```

### Task 2.2: `ClassEntity` + `MethodEntry` data classes

**Files:**
- Create: `lib/ruby_rdoc_collector/class_entity.rb`
- Test: `test/test_class_entity.rb`

- [ ] **Step 1: Write failing test**

File: `test/test_class_entity.rb`

```ruby
require_relative 'test_helper'

class TestClassEntity < Test::Unit::TestCase
  def test_class_entity_fields
    m = RubyRdocCollector::MethodEntry.new(name: 'length', call_seq: 'length -> int', description: 'Returns the length.')
    e = RubyRdocCollector::ClassEntity.new(
      name:        'String',
      description: 'A string is a sequence of bytes.',
      methods:     [m],
      constants:   [],
      superclass:  'Object'
    )
    assert_equal 'String', e.name
    assert_equal 1, e.methods.size
    assert_equal 'length', e.methods.first.name
    assert_equal 'Object', e.superclass
  end

  def test_method_entry_accepts_nil_call_seq
    m = RubyRdocCollector::MethodEntry.new(name: 'hash', call_seq: nil, description: '')
    assert_nil m.call_seq
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rake test TESTOPTS="--name=/ClassEntity/"`

Expected: FAIL with `NameError: uninitialized constant RubyRdocCollector::ClassEntity`.

- [ ] **Step 3: Implement**

File: `lib/ruby_rdoc_collector/class_entity.rb`

```ruby
module RubyRdocCollector
  MethodEntry = Data.define(:name, :call_seq, :description)
  ClassEntity = Data.define(:name, :description, :methods, :constants, :superclass)
end
```

- [ ] **Step 4: Run test**

Run: `bundle exec rake test TESTOPTS="--name=/ClassEntity/"`

Expected: 2 tests, 3 assertions, PASS.

- [ ] **Step 5: Commit**

Run:
```bash
git add lib/ruby_rdoc_collector/class_entity.rb test/test_class_entity.rb
git commit -m "feat: add ClassEntity/MethodEntry data classes"
```

### Task 2.3: `TranslationCache`

**Files:**
- Create: `lib/ruby_rdoc_collector/translation_cache.rb`
- Test: `test/test_translation_cache.rb`

- [ ] **Step 1: Write failing test**

File: `test/test_translation_cache.rb`

```ruby
require_relative 'test_helper'

class TestTranslationCache < Test::Unit::TestCase
  def setup
    @dir   = Dir.mktmpdir('cache')
    @cache = RubyRdocCollector::TranslationCache.new(cache_dir: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_miss_returns_nil
    assert_nil @cache.read('abc123')
  end

  def test_write_then_read
    @cache.write('abc123', '日本語訳')
    assert_equal '日本語訳', @cache.read('abc123')
  end

  def test_write_leaves_no_tmp_file
    @cache.write('key1', 'final content')
    shard_dir = File.join(@dir, 'ke')
    assert_equal ['key1'], Dir.children(shard_dir)
  end

  def test_shards_by_first_two_chars
    @cache.write('ffaa00', 'v')
    assert Dir.exist?(File.join(@dir, 'ff')), 'should shard by first 2 chars'
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rake test TESTOPTS="--name=/TranslationCache/"`

Expected: FAIL with load error.

- [ ] **Step 3: Implement**

File: `lib/ruby_rdoc_collector/translation_cache.rb`

```ruby
require 'fileutils'
require 'tempfile'

module RubyRdocCollector
  class TranslationCache
    DEFAULT_DIR = File.expand_path('~/.cache/ruby-rdoc-collector/translations')

    def initialize(cache_dir: DEFAULT_DIR)
      @cache_dir = cache_dir
      FileUtils.mkdir_p(@cache_dir)
    end

    def read(key)
      path = path_for(key)
      File.exist?(path) ? File.read(path) : nil
    end

    def write(key, value)
      path = path_for(key)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = Tempfile.new(['rdoc_cache_', '.tmp'], File.dirname(path))
      begin
        tmp.write(value)
        tmp.close
        File.rename(tmp.path, path)
      ensure
        tmp.close unless tmp.closed?
        File.unlink(tmp.path) if File.exist?(tmp.path)
      end
    end

    private

    def path_for(key)
      File.join(@cache_dir, key[0, 2], key)
    end
  end
end
```

- [ ] **Step 4: Run test**

Run: `bundle exec rake test TESTOPTS="--name=/TranslationCache/"`

Expected: 4 tests, PASS.

- [ ] **Step 5: Commit**

Run:
```bash
git add lib/ruby_rdoc_collector/translation_cache.rb test/test_translation_cache.rb
git commit -m "feat: add TranslationCache with atomic write and sharded keys"
```

### Task 2.4: `MarkdownFormatter`

**Files:**
- Create: `lib/ruby_rdoc_collector/markdown_formatter.rb`
- Test: `test/test_markdown_formatter.rb`

- [ ] **Step 1: Write failing test**

File: `test/test_markdown_formatter.rb`

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
    md = @formatter.format(@entity, jp_description: 'Ruby::Box は単一の値をラップする。', jp_method_descriptions: {})
    assert_match(/\A# Ruby::Box/, md)
    assert_include md, '(< Module)'
  end

  def test_includes_jp_description_in_overview
    md = @formatter.format(@entity, jp_description: 'Ruby::Box は単一の値をラップする。', jp_method_descriptions: {})
    assert_include md, 'Ruby::Box は単一の値をラップする。'
    refute_include md, 'A Ruby::Box wraps a single value.'
  end

  def test_method_section_keeps_original_call_seq
    md = @formatter.format(@entity, jp_description: 'JP', jp_method_descriptions: {})
    assert_include md, 'box.value -> object'
    assert_include md, 'box.replace(obj) -> obj'
  end

  def test_jp_method_descriptions_override_when_provided
    md = @formatter.format(@entity,
      jp_description: 'JP',
      jp_method_descriptions: { 'value' => '包んだ値を返す。' })
    assert_include md, '包んだ値を返す。'
  end

  def test_empty_methods_omits_methods_section
    entity = RubyRdocCollector::ClassEntity.new(
      name: 'Empty', description: '', methods: [], constants: [], superclass: 'Object'
    )
    md = @formatter.format(entity, jp_description: '空。', jp_method_descriptions: {})
    refute_match(/^## Methods/, md)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rake test TESTOPTS="--name=/MarkdownFormatter/"`

Expected: FAIL with load error.

- [ ] **Step 3: Implement**

File: `lib/ruby_rdoc_collector/markdown_formatter.rb`

```ruby
module RubyRdocCollector
  class MarkdownFormatter
    # @param entity [ClassEntity]
    # @param jp_description [String]
    # @param jp_method_descriptions [Hash<String, String>] method_name => JP description (optional)
    # @return [String]
    def format(entity, jp_description:, jp_method_descriptions:)
      lines = []
      header = "# #{entity.name}"
      header += " (< #{entity.superclass})" if entity.superclass && !entity.superclass.empty?
      lines << header
      lines << ''
      lines << '## 概要'
      lines << ''
      lines << jp_description
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
          jp = jp_method_descriptions[m.name]
          lines << (jp && !jp.empty? ? jp : (m.description || ''))
          lines << ''
        end
      end

      lines.join("\n").rstrip + "\n"
    end
  end
end
```

- [ ] **Step 4: Run test**

Run: `bundle exec rake test TESTOPTS="--name=/MarkdownFormatter/"`

Expected: 5 tests, PASS.

- [ ] **Step 5: Commit**

Run:
```bash
git add lib/ruby_rdoc_collector/markdown_formatter.rb test/test_markdown_formatter.rb
git commit -m "feat: add MarkdownFormatter pure function"
```

### Task 2.5: `Translator`

**Files:**
- Create: `lib/ruby_rdoc_collector/translator.rb`
- Test: `test/test_translator.rb`

- [ ] **Step 1: Write failing test**

File: `test/test_translator.rb`

```ruby
require_relative 'test_helper'

class TestTranslator < Test::Unit::TestCase
  def setup
    @dir   = Dir.mktmpdir('tcache')
    @cache = RubyRdocCollector::TranslationCache.new(cache_dir: @dir)
    @no_sleep = ->(_sec) {}
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_returns_runner_output_and_caches_it
    runner = EchoRunner.new(response: 'JP output')
    t = RubyRdocCollector::Translator.new(runner: runner, cache: @cache, sleeper: @no_sleep)
    result = t.translate('English input')
    assert_equal 'JP output', result
    assert_equal 1, runner.calls
  end

  def test_second_call_with_same_input_hits_cache
    runner = EchoRunner.new(response: 'JP output')
    t = RubyRdocCollector::Translator.new(runner: runner, cache: @cache, sleeper: @no_sleep)
    t.translate('Same input')
    t.translate('Same input')
    assert_equal 1, runner.calls
  end

  def test_different_input_misses_cache
    runner = EchoRunner.new(response: 'JP')
    t = RubyRdocCollector::Translator.new(runner: runner, cache: @cache, sleeper: @no_sleep)
    t.translate('input A')
    t.translate('input B')
    assert_equal 2, runner.calls
  end

  def test_retries_on_transient_failure
    runner = FailingRunner.new(fail_count: 2, eventual: 'JP ok')
    t = RubyRdocCollector::Translator.new(runner: runner, cache: @cache, max_retries: 3, sleeper: @no_sleep)
    assert_equal 'JP ok', t.translate('x')
    assert_equal 3, runner.calls
  end

  def test_raises_after_max_retries
    runner = FailingRunner.new(fail_count: 99)
    t = RubyRdocCollector::Translator.new(runner: runner, cache: @cache, max_retries: 2, sleeper: @no_sleep)
    assert_raise(RubyRdocCollector::Translator::TranslationError) do
      t.translate('x')
    end
  end

  def test_empty_input_returns_empty_without_runner_call
    runner = EchoRunner.new
    t = RubyRdocCollector::Translator.new(runner: runner, cache: @cache, sleeper: @no_sleep)
    assert_equal '', t.translate('')
    assert_equal 0, runner.calls
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rake test TESTOPTS="--name=/TestTranslator/"`

Expected: FAIL with load error.

- [ ] **Step 3: Implement**

File: `lib/ruby_rdoc_collector/translator.rb`

```ruby
require 'digest'
require 'open3'

module RubyRdocCollector
  class Translator
    class TranslationError < StandardError; end

    MODEL_TAG = 'claude-sonnet'
    DEFAULT_MAX_RETRIES = 3
    RETRY_WAIT_SECONDS = 10

    PROMPT_HEADER = <<~HEADER
      あなたは Ruby の公式ドキュメント翻訳者です。

      ## コンテキスト
      - 入力は Ruby (CRuby) の RDoc ドキュメントから抽出された英語テキスト（HTML形式の場合あり）です
      - Ruby のソースコードは Prism（Ruby 標準ライブラリ）で解析可能な構文です
      - C 言語で記述されたメソッドの RDoc コメントは rdoc/parser（Ruby 標準ライブラリ）形式に従っています
      - call-seq: 記法、+code+ 記法、<code>code</code> タグなど RDoc 特有のマークアップが含まれることがあります

      ## 翻訳ルール
      - コードブロック、メソッドシグネチャ、識別子（クラス名・メソッド名・定数名・引数名）は**原文のまま**保持
      - 散文（説明文）のみを自然な日本語に翻訳
      - 出力はプレーンテキスト（HTMLタグは除去して出力）
      - 出力は翻訳された本文のみ。前置き・後書き・「翻訳結果:」などの注釈は不要

      --- 入力ここから ---
    HEADER

    def initialize(runner: nil, cache: TranslationCache.new, max_retries: DEFAULT_MAX_RETRIES, sleeper: ->(sec) { sleep(sec) })
      @runner      = runner || default_runner
      @cache       = cache
      @max_retries = max_retries
      @sleeper     = sleeper
    end

    def translate(en_text)
      return '' if en_text.nil? || en_text.strip.empty?

      key = cache_key(en_text)
      cached = @cache.read(key)
      return cached if cached

      result = run_with_retry(en_text)
      @cache.write(key, result)
      result
    end

    private

    def cache_key(en_text)
      Digest::SHA256.hexdigest("#{MODEL_TAG}::#{en_text}")
    end

    def run_with_retry(en_text)
      prompt = "#{PROMPT_HEADER}#{en_text}\n--- 入力ここまで ---"
      attempts = 0
      last_error = nil
      while attempts < @max_retries
        attempts += 1
        begin
          result = @runner.call(prompt)
          raise TranslationError, 'empty response' if result.nil? || result.strip.empty?
          return result
        rescue TranslationError => e
          last_error = e
          @sleeper.call(RETRY_WAIT_SECONDS) if attempts < @max_retries
        end
      end
      raise TranslationError, "failed after #{attempts} attempts: #{last_error&.message}"
    end

    def default_runner
      lambda do |prompt|
        out, status = Open3.capture2e('claude', '--model', 'sonnet', '-p', '-', stdin_data: prompt)
        raise TranslationError, "claude exit #{status.exitstatus}: #{out[0, 500]}" unless status.success?
        out
      end
    end
  end
end
```

- [ ] **Step 4: Run test**

Run: `bundle exec rake test TESTOPTS="--name=/TestTranslator/"`

Expected: 6 tests, PASS.

- [ ] **Step 5: Commit**

Run:
```bash
git add lib/ruby_rdoc_collector/translator.rb test/test_translator.rb
git commit -m "feat: add Translator with SHA256 cache and retry"
```

### Task 2.6: `TarballFetcher`

**Files:**
- Create: `lib/ruby_rdoc_collector/tarball_fetcher.rb`
- Test: `test/test_tarball_fetcher.rb`

**Design note:** TarballFetcher downloads from `cache.ruby-lang.org` and extracts to a local cache directory. The download step is DI-injectable for testing (stub downloader that copies a local file). Extraction uses `tar xf` via system call.

- [ ] **Step 1: Write failing test**

File: `test/test_tarball_fetcher.rb`

```ruby
require_relative 'test_helper'

class TestTarballFetcher < Test::Unit::TestCase
  def test_raises_on_download_failure
    failing_downloader = ->(_url, _dest) { raise RubyRdocCollector::TarballFetcher::FetchError, 'network down' }
    Dir.mktmpdir do |dir|
      fetcher = RubyRdocCollector::TarballFetcher.new(
        url: 'https://example.com/fake.tar.xz',
        cache_dir: dir,
        downloader: failing_downloader
      )
      assert_raise(RubyRdocCollector::TarballFetcher::FetchError) { fetcher.fetch }
    end
  end

  def test_extracts_tarball_and_returns_content_dir
    Dir.mktmpdir do |dir|
      # Create a test tarball
      content_dir = File.join(dir, 'build', 'master')
      FileUtils.mkdir_p(content_dir)
      File.write(File.join(content_dir, 'index.html'), '<h1>test</h1>')
      tarball_src = File.join(dir, 'test.tar.xz')
      system('tar', 'cJf', tarball_src, '-C', File.join(dir, 'build'), 'master')

      cache_dir = File.join(dir, 'cache')
      stub_downloader = lambda do |_url, dest|
        FileUtils.cp(tarball_src, dest)
      end

      fetcher = RubyRdocCollector::TarballFetcher.new(
        url: 'https://example.com/fake.tar.xz',
        cache_dir: cache_dir,
        downloader: stub_downloader
      )
      result = fetcher.fetch
      assert File.exist?(File.join(result, 'index.html')), "extracted content should contain index.html"
    end
  end

  def test_returns_top_level_subdir_when_single_entry
    Dir.mktmpdir do |dir|
      content_dir = File.join(dir, 'build', 'master')
      FileUtils.mkdir_p(content_dir)
      File.write(File.join(content_dir, 'test.html'), 'ok')
      tarball_src = File.join(dir, 'test.tar.xz')
      system('tar', 'cJf', tarball_src, '-C', File.join(dir, 'build'), 'master')

      cache_dir = File.join(dir, 'cache')
      fetcher = RubyRdocCollector::TarballFetcher.new(
        url: 'https://example.com/fake.tar.xz',
        cache_dir: cache_dir,
        downloader: ->(_url, dest) { FileUtils.cp(tarball_src, dest) }
      )
      result = fetcher.fetch
      assert result.end_with?('/master'), "should resolve to the 'master' subdirectory, got: #{result}"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rake test TESTOPTS="--name=/TestTarballFetcher/"`

Expected: FAIL with load error.

- [ ] **Step 3: Implement**

File: `lib/ruby_rdoc_collector/tarball_fetcher.rb`

```ruby
require 'fileutils'
require 'open3'

module RubyRdocCollector
  class TarballFetcher
    class FetchError < StandardError; end

    DEFAULT_URL = 'https://cache.ruby-lang.org/pub/ruby/doc/ruby-docs-en-master.tar.xz'
    DEFAULT_CACHE_DIR = File.expand_path('~/.cache/ruby-rdoc-collector/tarball')

    def initialize(url: DEFAULT_URL, cache_dir: DEFAULT_CACHE_DIR, downloader: nil)
      @url        = url
      @cache_dir  = cache_dir
      @downloader = downloader || method(:default_download)
    end

    # @return [String] path to extracted content directory
    def fetch
      FileUtils.mkdir_p(@cache_dir)
      tarball_path  = File.join(@cache_dir, File.basename(@url))
      extracted_dir = File.join(@cache_dir, 'extracted')

      begin
        @downloader.call(@url, tarball_path)
      rescue => e
        raise FetchError, "download failed: #{e.message}"
      end

      extract(tarball_path, extracted_dir)
      resolve_content_dir(extracted_dir)
    end

    private

    def extract(tarball_path, dest)
      FileUtils.rm_rf(dest)
      FileUtils.mkdir_p(dest)
      out, status = Open3.capture2e('tar', 'xf', tarball_path, '-C', dest)
      raise FetchError, "tar extraction failed: #{out}" unless status.success?
    end

    def resolve_content_dir(extracted_dir)
      entries = Dir.children(extracted_dir)
      if entries.size == 1 && File.directory?(File.join(extracted_dir, entries.first))
        File.join(extracted_dir, entries.first)
      else
        extracted_dir
      end
    end

    def default_download(url, dest)
      out, status = Open3.capture2e('curl', '-sSL', '-o', dest, url)
      raise FetchError, "curl failed: #{out}" unless status.success?
    end
  end
end
```

- [ ] **Step 4: Run test**

Run: `bundle exec rake test TESTOPTS="--name=/TestTarballFetcher/"`

Expected: 3 tests, PASS.

- [ ] **Step 5: Commit**

Run:
```bash
git add lib/ruby_rdoc_collector/tarball_fetcher.rb test/test_tarball_fetcher.rb
git commit -m "feat: add TarballFetcher (download + extract darkfish HTML tarball)"
```

### Task 2.7: `HtmlParser`

**Files:**
- Create: `lib/ruby_rdoc_collector/html_parser.rb`
- Create: `test/fixtures/search_data.js`
- Create: `test/fixtures/TestClass.html`
- Create: `test/fixtures/Ruby/Box.html`
- Test: `test/test_html_parser.rb`

**Design note:** `HtmlParser` takes a directory path (the extracted tarball content) and returns `Array<ClassEntity>`. It reads `js/search_data.js` for the class/method index, then parses individual HTML files for full descriptions and `call_seq`. Oga is used for robust HTML parsing.

- [ ] **Step 1: Create fixture files**

File: `test/fixtures/search_data.js`

```javascript
var search_data = {"index":[
  {"name":"TestClass","full_name":"TestClass","type":"class","path":"TestClass.html","snippet":"<p>A test class for unit testing.</p>"},
  {"name":"Box","full_name":"Ruby::Box","type":"class","path":"Ruby/Box.html","snippet":"<p>Ruby Box provides in-process separation.</p>"},
  {"name":"new","full_name":"TestClass::new","type":"class_method","path":"TestClass.html#method-c-new","snippet":"<p>Creates a new instance.</p>"},
  {"name":"value","full_name":"TestClass#value","type":"instance_method","path":"TestClass.html#method-i-value","snippet":"<p>Returns the value.</p>"},
  {"name":"current","full_name":"Ruby::Box::current","type":"class_method","path":"Ruby/Box.html#method-c-current","snippet":"<p>Returns the current box.</p>"}
]};
```

File: `test/fixtures/TestClass.html`

```html
<!DOCTYPE html>
<html><head><title>class TestClass</title></head>
<body>
<h1 id="class-testclass" class="anchor-link class">class TestClass</h1>
<div id="parent-class-section" class="nav-section">
  <ul><li><a href="Object.html">Object</a></li></ul>
</div>
<section class="description">
<p>A test class for unit testing. It demonstrates the basic structure.</p>
</section>
<section class="documentation-section">
  <section class="method-section">
    <div id="method-c-new" class="method-detail">
      <div class="method-heading">
        <span class="method-callseq">TestClass.new(val) &rarr; obj</span>
      </div>
      <div class="method-description">
        <p>Creates a new TestClass instance with the given value.</p>
      </div>
    </div>
    <div id="method-i-value" class="method-detail">
      <div class="method-heading">
        <span class="method-callseq">value &rarr; object</span>
      </div>
      <div class="method-description">
        <p>Returns the stored value.</p>
      </div>
    </div>
  </section>
</section>
</body></html>
```

File: `test/fixtures/Ruby/Box.html`

```html
<!DOCTYPE html>
<html><head><title>class Ruby::Box</title></head>
<body>
<h1 id="class-ruby-box" class="anchor-link class">class Ruby::Box</h1>
<div id="parent-class-section" class="nav-section">
  <ul><li><a href="../Module.html">Module</a></li></ul>
</div>
<section class="description">
<p>Ruby Box provides in-process separation of Classes and Modules.</p>
</section>
<section class="documentation-section">
  <section class="method-section">
    <div id="method-c-current" class="method-detail">
      <div class="method-heading">
        <span class="method-callseq">Ruby::Box.current &rarr; box, nil or false</span>
      </div>
      <div class="method-description">
        <p>Returns the current box. Returns <code>nil</code> if Ruby Box is not enabled.</p>
      </div>
    </div>
  </section>
</section>
</body></html>
```

- [ ] **Step 2: Write failing test**

File: `test/test_html_parser.rb`

```ruby
require_relative 'test_helper'

class TestHtmlParser < Test::Unit::TestCase
  def setup
    @parser = RubyRdocCollector::HtmlParser.new
  end

  def test_parses_classes_from_fixtures
    entities = @parser.parse(FIXTURE_DIR)
    names = entities.map(&:name)
    assert_include names, 'TestClass'
    assert_include names, 'Ruby::Box'
  end

  def test_extracts_class_description_from_html
    entities = @parser.parse(FIXTURE_DIR)
    tc = entities.find { |e| e.name == 'TestClass' }
    assert_match(/test class for unit testing/, tc.description)
  end

  def test_extracts_superclass
    entities = @parser.parse(FIXTURE_DIR)
    tc = entities.find { |e| e.name == 'TestClass' }
    assert_equal 'Object', tc.superclass

    box = entities.find { |e| e.name == 'Ruby::Box' }
    assert_equal 'Module', box.superclass
  end

  def test_extracts_methods_with_call_seq
    entities = @parser.parse(FIXTURE_DIR)
    tc = entities.find { |e| e.name == 'TestClass' }
    method_names = tc.methods.map(&:name)
    assert_include method_names, 'new'
    assert_include method_names, 'value'

    new_method = tc.methods.find { |m| m.name == 'new' }
    assert_match(/TestClass\.new/, new_method.call_seq)
  end

  def test_extracts_method_description_from_html
    entities = @parser.parse(FIXTURE_DIR)
    tc = entities.find { |e| e.name == 'TestClass' }
    new_method = tc.methods.find { |m| m.name == 'new' }
    assert_match(/Creates a new TestClass instance/, new_method.description)
  end

  def test_handles_nested_namespace_path
    entities = @parser.parse(FIXTURE_DIR)
    box = entities.find { |e| e.name == 'Ruby::Box' }
    assert_not_nil box
    assert_equal 1, box.methods.size
    assert_equal 'current', box.methods.first.name
    assert_match(/Ruby::Box\.current/, box.methods.first.call_seq)
  end

  def test_skips_entries_without_html_file
    # Modules/methods that have no matching HTML file should be silently skipped
    entities = @parser.parse(FIXTURE_DIR)
    entities.each do |e|
      assert_not_nil e.name
      assert_not_nil e.description
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rake test TESTOPTS="--name=/TestHtmlParser/"`

Expected: FAIL with load error.

- [ ] **Step 4: Implement**

File: `lib/ruby_rdoc_collector/html_parser.rb`

```ruby
require 'json'
require 'oga'
require 'cgi'

module RubyRdocCollector
  class HtmlParser
    class ParseError < StandardError; end

    # @param extracted_dir [String] path to the extracted tarball content (contains js/, *.html)
    # @return [Array<ClassEntity>]
    def parse(extracted_dir)
      index = load_search_index(extracted_dir)
      class_entries = index.select { |e| e['type'] == 'class' || e['type'] == 'module' }
      method_entries = index.select { |e| %w[class_method instance_method].include?(e['type']) }

      class_entries.filter_map do |cls|
        html_path = File.join(extracted_dir, cls['path'])
        next unless File.exist?(html_path)

        doc = Oga.parse_html(File.read(html_path))
        methods = build_methods(cls['full_name'], method_entries, doc)

        ClassEntity.new(
          name:        cls['full_name'],
          description: extract_description(doc),
          methods:     methods,
          constants:   [],
          superclass:  extract_superclass(doc)
        )
      end
    end

    private

    def load_search_index(dir)
      js_path = File.join(dir, 'js', 'search_data.js')
      # Also try without js/ prefix (for test fixtures)
      js_path = File.join(dir, 'search_data.js') unless File.exist?(js_path)
      raise ParseError, "search_data.js not found in #{dir}" unless File.exist?(js_path)

      content = File.read(js_path)
      json_str = content.sub(/\Avar search_data = /, '').sub(/;\s*\z/, '')
      JSON.parse(json_str)['index']
    rescue JSON::ParserError => e
      raise ParseError, "search_data.js parse error: #{e.message}"
    end

    def extract_description(doc)
      section = doc.css('section.description').first
      section ? inner_html(section).strip : ''
    end

    def extract_superclass(doc)
      parent_section = doc.css('#parent-class-section').first
      return nil unless parent_section

      first_link = parent_section.css('a').first
      first_link ? first_link.text.strip : nil
    end

    def build_methods(class_full_name, all_method_entries, doc)
      class_methods = all_method_entries.select do |m|
        m['full_name'].start_with?("#{class_full_name}#") ||
          m['full_name'].start_with?("#{class_full_name}::")
      end

      class_methods.filter_map do |m|
        fragment = m['path'].split('#', 2).last
        next unless fragment

        method_div = doc.css("##{fragment}").first

        call_seq = nil
        description = m['snippet'] || ''

        if method_div
          cs_el = method_div.css('.method-callseq').first
          call_seq = CGI.unescapeHTML(cs_el.text.strip) if cs_el

          desc_el = method_div.css('.method-description').first
          description = inner_html(desc_el).strip if desc_el
        end

        MethodEntry.new(
          name:        m['name'],
          call_seq:    call_seq,
          description: description
        )
      end
    end

    # Oga does not have inner_html; serialize children manually.
    def inner_html(node)
      node.children.map { |c| c.to_xml }.join
    end
  end
end
```

- [ ] **Step 5: Run test**

Run: `bundle exec rake test TESTOPTS="--name=/TestHtmlParser/"`

Expected: 7 tests, PASS.

- [ ] **Step 6: Commit**

Run:
```bash
git add lib/ruby_rdoc_collector/html_parser.rb test/test_html_parser.rb test/fixtures/
git commit -m "feat: add HtmlParser (search_data.js + darkfish HTML → ClassEntity)"
```

### Task 2.8: `Collector` (unified IF)

**Files:**
- Create: `lib/ruby_rdoc_collector/collector.rb`
- Test: `test/test_collector.rb`

- [ ] **Step 1: Write failing test**

File: `test/test_collector.rb`

```ruby
require_relative 'test_helper'

class TestCollector < Test::Unit::TestCase
  class StubFetcher
    def initialize(dir); @dir = dir; end
    def fetch; @dir; end
  end

  class StubParser
    def initialize(entities); @entities = entities; end
    def parse(_dir); @entities; end
  end

  def setup
    @dir   = Dir.mktmpdir('collector')
    cache  = RubyRdocCollector::TranslationCache.new(cache_dir: @dir)
    @translator = RubyRdocCollector::Translator.new(runner: EchoRunner.new(response: 'JP'), cache: cache, sleeper: ->(_s) {})
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
    c = RubyRdocCollector::Collector.new({},
      fetcher:    StubFetcher.new('/fake'),
      parser:     StubParser.new(entities),
      translator: @translator,
      formatter:  RubyRdocCollector::MarkdownFormatter.new)
    results = c.collect
    assert_equal 2, results.size
    results.each do |r|
      assert_kind_of String, r[:content]
      assert_match %r{\Aruby/ruby:rdoc/trunk/}, r[:source]
    end
    sources = results.map { |r| r[:source] }
    assert_include sources, 'ruby/ruby:rdoc/trunk/String'
  end

  def test_partial_failure_skips_single_class_not_whole_batch
    entities = [build_entity('String'), build_entity('Integer')]
    always_fail_on_integer = lambda do |prompt|
      raise RubyRdocCollector::Translator::TranslationError, 'always' if prompt.include?('desc of Integer')
      'JP'
    end
    boom_translator = RubyRdocCollector::Translator.new(
      runner: always_fail_on_integer,
      cache:  RubyRdocCollector::TranslationCache.new(cache_dir: Dir.mktmpdir('c2')),
      max_retries: 1,
      sleeper: ->(_s) {}
    )
    c = RubyRdocCollector::Collector.new({},
      fetcher:    StubFetcher.new('/fake'),
      parser:     StubParser.new(entities),
      translator: boom_translator,
      formatter:  RubyRdocCollector::MarkdownFormatter.new)
    results = c.collect
    sources = results.map { |r| r[:source] }
    assert_equal 1, results.size
    assert_include sources, 'ruby/ruby:rdoc/trunk/String'
    refute_include sources, 'ruby/ruby:rdoc/trunk/Integer'
  end

  def test_since_and_before_are_ignored
    entities = [build_entity('A')]
    c = RubyRdocCollector::Collector.new({},
      fetcher:    StubFetcher.new('/fake'),
      parser:     StubParser.new(entities),
      translator: @translator,
      formatter:  RubyRdocCollector::MarkdownFormatter.new)
    r1 = c.collect(since: '2020-01-01', before: '2020-01-02')
    r2 = c.collect
    assert_equal r1, r2
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rake test TESTOPTS="--name=/TestCollector/"`

Expected: FAIL with load error.

- [ ] **Step 3: Implement**

File: `lib/ruby_rdoc_collector/collector.rb`

```ruby
module RubyRdocCollector
  class Collector
    SOURCE_PREFIX = 'ruby/ruby:rdoc/trunk'

    def initialize(config,
                   fetcher:    nil,
                   parser:     nil,
                   translator: nil,
                   formatter:  nil)
      @config     = config || {}
      @fetcher    = fetcher    || TarballFetcher.new(
        url: @config['url'] || TarballFetcher::DEFAULT_URL
      )
      @parser     = parser     || HtmlParser.new
      @translator = translator || Translator.new
      @formatter  = formatter  || MarkdownFormatter.new
    end

    # since/before are ignored. content_hash idempotency upstream.
    def collect(since: nil, before: nil)
      content_dir = @fetcher.fetch
      entities = @parser.parse(content_dir)
      entities.filter_map { |e| safe_translate_and_format(e) }
    end

    private

    def safe_translate_and_format(entity)
      jp_desc    = @translator.translate(entity.description)
      jp_methods = entity.methods.to_h do |m|
        [m.name, @translator.translate(m.description)]
      end
      content = @formatter.format(entity, jp_description: jp_desc, jp_method_descriptions: jp_methods)
      { content: content, source: "#{SOURCE_PREFIX}/#{entity.name}" }
    rescue Translator::TranslationError => e
      warn "[RubyRdocCollector::Collector] skip #{entity.name}: #{e.message}"
      nil
    end
  end
end
```

- [ ] **Step 4: Run test**

Run: `bundle exec rake test TESTOPTS="--name=/TestCollector/"`

Expected: 3 tests, PASS.

- [ ] **Step 5: Run full suite**

Run: `bundle exec rake test`

Expected: ~30 tests across 8 files, all PASS.

- [ ] **Step 6: Commit**

Run:
```bash
git add lib/ruby_rdoc_collector/collector.rb test/test_collector.rb
git commit -m "feat: add Collector facade with partial-failure handling"
```

### Task 2.9: PoC smoke run (manual, real Claude CLI)

**Files:**
- Create: `bin/poc_smoke.rb`

- [ ] **Step 1: Write smoke script**

File: `bin/poc_smoke.rb`

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# Usage: bundle exec ruby bin/poc_smoke.rb [Ruby::Box] [String] [Integer]
# Downloads the master tarball from cache.ruby-lang.org and runs the full pipeline.
# This invokes real Claude CLI — costs $ and takes minutes.

require 'bundler/setup'
require 'ruby_rdoc_collector'

targets = ARGV.empty? ? ['Ruby::Box', 'String', 'Integer'] : ARGV

collector = RubyRdocCollector::Collector.new({})
puts "Running collector (real Claude CLI — this will take minutes and cost $)..."
all = collector.collect
selected = all.select { |r| targets.any? { |t| r[:source].end_with?("/#{t}") } }

selected.each do |r|
  puts "\n\n==========================\n#{r[:source]}\n==========================\n\n"
  puts r[:content]
end

puts "\n---\nclasses collected: #{all.size}, printed: #{selected.size}"
```

- [ ] **Step 2: Run smoke test (cost incurred)**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector
time bundle exec ruby bin/poc_smoke.rb Ruby::Box String Integer 2>&1 | tee /tmp/ruby_rdoc_poc.log
```

Expected: 3 Markdown blocks with JP descriptions.

- [ ] **Step 3: Re-run to verify cache**

Run:
```bash
time bundle exec ruby bin/poc_smoke.rb Ruby::Box String Integer > /dev/null
```

Expected: elapsed seconds ≪ first run (cache hit on translations, tarball re-downloaded but extraction is fast).

- [ ] **Step 4: Record PoC findings**

Edit `bin/poc_smoke.rb` top comment block with wall-clock time, call count, quality verdict, estimated $/class.

**CHECKPOINT: Report findings to user. If quality fails or cost is unacceptable, stop before Stage 3.**

- [ ] **Step 5: Commit**

Run:
```bash
git add bin/poc_smoke.rb
git commit -m "chore: add PoC smoke script with cache verification"
```

### Task 2.10: Publish gem repo to GitHub

- [ ] **Step 1: Create GitHub repo**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector
gh repo create bash0C7/ruby-rdoc-collector --public --source=. --remote=origin --push
```

Expected: repo created on GitHub, `main` pushed.

---

## Stage 3: ruby-knowledge-db integration

**All Stage 3 tasks (except 3.5) operate in `../ruby-knowledge-db-rdoc/` worktree.**

### Task 3.1: Add gem to Gemfile

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add gem entry**

In `Gemfile`, near the existing `rurema_collector` / `picoruby_docs_collector` entries, add:

```ruby
gem 'ruby_rdoc_collector', path: '../ruby-rdoc-collector'
```

- [ ] **Step 2: Install bundle**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db-rdoc
bundle install
bundle exec ruby -r ruby_rdoc_collector -e 'puts RubyRdocCollector::Collector'
```

Expected: `RubyRdocCollector::Collector` printed, no errors.

- [ ] **Step 3: Commit**

Run:
```bash
git add Gemfile Gemfile.lock
git commit -m "chore: add ruby_rdoc_collector path gem"
```

### Task 3.2: Add `ruby_rdoc` source config

**Files:**
- Modify: `config/sources.yml`

- [ ] **Step 1: Append source config**

In `config/sources.yml`, under `sources:`, add:

```yaml
  # ruby/ruby trunk RDoc (en) → JP translation.
  # Data source: pre-built darkfish HTML tarball from cache.ruby-lang.org.
  # No ruby/ruby clone needed. No cache:prepare dependency.
  ruby_rdoc:
    url: https://cache.ruby-lang.org/pub/ruby/doc/ruby-docs-en-master.tar.xz
```

- [ ] **Step 2: Verify YAML parses**

Run:
```bash
ruby -ryaml -e 'puts YAML.load_file("config/sources.yml")["sources"]["ruby_rdoc"].inspect'
```

Expected: `{"url"=>"https://cache.ruby-lang.org/pub/ruby/doc/ruby-docs-en-master.tar.xz"}` printed.

- [ ] **Step 3: Commit**

Run:
```bash
git add config/sources.yml
git commit -m "feat: add ruby_rdoc source config (tarball from cache.ruby-lang.org)"
```

### Task 3.3: Add `rake update:ruby_rdoc` task

**Files:**
- Modify: `Rakefile`

- [ ] **Step 1: Add require to `require_update_deps`**

In `Rakefile`, locate `def require_update_deps` and add:

```ruby
require 'ruby_rdoc_collector'
```

- [ ] **Step 2: Add update task**

In the `namespace :update` block, append:

```ruby
  desc "Update ruby rdoc (downloads tarball, translates, stores). No cache:prepare needed."
  task :ruby_rdoc do
    run_collector(:ruby_rdoc, 'RubyRdocCollector::Collector', 'ruby_rdoc')
  end
```

Note: **No `cache:prepare` prereq** — this collector downloads its own data from cache.ruby-lang.org.

- [ ] **Step 3: Verify task is registered**

Run:
```bash
bundle exec rake -T | grep ruby_rdoc
```

Expected: `rake update:ruby_rdoc` listed.

- [ ] **Step 4: Commit**

Run:
```bash
git add Rakefile
git commit -m "feat: add rake update:ruby_rdoc task"
```

### Task 3.4: Register in `scripts/update_all.rb`

**Files:**
- Modify: `scripts/update_all.rb`

- [ ] **Step 1: Add require**

After `require 'picoruby_docs_collector'`, add:

```ruby
require 'ruby_rdoc_collector'
```

- [ ] **Step 2: Add collector to array**

In the `collectors = [...]` array, append before `].compact`:

```ruby
  srcs['ruby_rdoc']      && RubyRdocCollector::Collector.new(srcs['ruby_rdoc']),
```

- [ ] **Step 3: Verify syntax**

Run:
```bash
APP_ENV=test bundle exec ruby -c scripts/update_all.rb
```

Expected: `Syntax OK`.

- [ ] **Step 4: Commit**

Run:
```bash
git add scripts/update_all.rb
git commit -m "feat: register ruby_rdoc collector in update_all.rb"
```

### Task 3.5: Add `source_prefix` case in ruby-knowledge-store

**Files:**
- Modify: `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-store/lib/ruby_knowledge_store/store.rb`
- Modify: `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-store/test/test_store.rb`

- [ ] **Step 1: Inspect existing cases**

Run:
```bash
grep -n "source_prefix\|rurema/doctree\|build_embedding_text" /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-store/lib/ruby_knowledge_store/store.rb
```

Record the exact format of the rurema case branch to mirror it.

- [ ] **Step 2: Write failing test**

In `test/test_store.rb`, add (matching existing style):

```ruby
def test_source_prefix_for_ruby_rdoc_trunk_class
  store = RubyKnowledgeStore::Store.new(':memory:', embedder: StubEmbedder.new)
  text = store.send(:build_embedding_text, 'dummy content', 'ruby/ruby:rdoc/trunk/Ruby::Box')
  assert_match(/Ruby::Box/, text)
  assert_match(/trunk/, text)
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rake test TESTOPTS="--name=/ruby_rdoc_trunk/"`

Expected: FAIL.

- [ ] **Step 4: Add case branch**

In `build_embedding_text` / `source_prefix` method, add:

```ruby
when %r{\Aruby/ruby:rdoc/trunk/(?<class_name>.+)\z}
  class_name = Regexp.last_match[:class_name]
  "Ruby trunk #{class_name} クラス ... ruby/ruby trunk RDoc ドキュメント: "
```

- [ ] **Step 5: Run test**

Run: `bundle exec rake test`

Expected: all PASS.

- [ ] **Step 6: Commit**

Run:
```bash
git add lib/ruby_knowledge_store/store.rb test/test_store.rb
git commit -m "feat: add source_prefix case for ruby/ruby:rdoc/trunk"
```

### Task 3.6: Integration smoke test (APP_ENV=test)

- [ ] **Step 1: Record baseline DB state**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db-rdoc
APP_ENV=test bundle exec rake db:stats 2>&1 | head -20
```

- [ ] **Step 2: Run collector end-to-end against test DB**

Run:
```bash
APP_ENV=test bundle exec rake update:ruby_rdoc 2>&1 | tee /tmp/rdoc_integration.log
```

Expected: `ruby_rdoc: stored=N` where N > 0.

- [ ] **Step 3: Verify entries in DB**

Run:
```bash
APP_ENV=test bundle exec rake db:stats
```

Expected: `ruby/ruby:rdoc/trunk` entries visible in stats.

- [ ] **Step 4: Rerun and verify idempotency**

Run:
```bash
APP_ENV=test bundle exec rake update:ruby_rdoc 2>&1 | tail -3
```

Expected: `stored=0, skipped=N` (content_hash dedup).

### Task 3.7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add to source 値の規約 table**

```
| `ruby/ruby:rdoc/trunk/{ClassName}` | ruby/ruby trunk RDoc の日本語翻訳版（ruby-rdoc-collector）|
```

- [ ] **Step 2: Add to 依存する外部リポジトリ table**

```
| ruby-rdoc-collector   | `../ruby-rdoc-collector`   | ruby/ruby の RDoc HTML（cache.ruby-lang.org tarball）を取得し Claude CLI で日本語翻訳 |
```

- [ ] **Step 3: Add cache note**

Under `### キャッシュ方針`, append:

```markdown
`ruby-rdoc-collector` は `https://cache.ruby-lang.org/pub/ruby/doc/ruby-docs-en-master.tar.xz` を `~/.cache/ruby-rdoc-collector/tarball/` にダウンロード・展開する。ruby/ruby clone は不要（`cache:prepare` 依存なし）。翻訳キャッシュは `~/.cache/ruby-rdoc-collector/translations/` に SHA256 キーで保存。
```

- [ ] **Step 4: Commit**

Run:
```bash
git add CLAUDE.md
git commit -m "docs: document ruby-rdoc-collector source, repo, and cache"
```

### Task 3.8: Update chiebukuro-mcp meta patches

**Files:**
- Modify: `/Users/bash/dev/src/github.com/bash0C7/dotfiles/chiebukuro-mcp/chiebukuro-mcp/scripts/meta_patches/ruby_knowledge.yml`

**Design note:** chiebukuro-mcp のメタパッチに `ruby/ruby:rdoc/trunk` ソースを追加する。これにより MCP サーバーがこの新しいソースタイプを認識し、適切なクエリ・解釈ガイド・レシピを提供できるようになる。パッチ適用は `apply_meta_patches.rb` で冪等。

- [ ] **Step 1: Add rdoc source to enum_values and note**

In `ruby_knowledge.yml`, under `columns: - name: memories.source`, add to `hints.enum_values`:

```yaml
        - "ruby/ruby:rdoc/trunk/*"
```

And update `hints.note` to include the interpretation guide:

```yaml
      note: |
        「Ruby」といえば CRuby。PicoRuby は必ず source='picoruby/picoruby:trunk/%' 等で明示。
        semantic_search は trunk/article（AI 生成変更記事）に最も効果的。
        rurema ドキュメントは FTS5 (WHERE source LIKE 'rurema%') が正確。
        rdoc/trunk/ は Ruby master の英語 RDoc API ドキュメントの日本語翻訳版。
        rurema（手書き詳細ドキュメント）と rdoc（最新 API 機械翻訳）は相補的に使い分ける。
        rdoc は Ruby::Box など rurema 未収録の最新クラスもカバーする。
        rdoc/trunk/ のコード例は Prism（Ruby 標準ライブラリ）で解析可能な構文。
        C 拡張メソッドの RDoc コメントは rdoc/parser（Ruby 標準ライブラリ）形式。
```

- [ ] **Step 2: Add rdoc keyword to clarification_fields**

Under `clarification_fields: - name: source_like`, add to `attrs.keywords`:

```yaml
        rdoc: "ruby/ruby:rdoc/trunk/%"
        RDoc: "ruby/ruby:rdoc/trunk/%"
```

And add to `attrs.enum_values`:

```yaml
        - "ruby/ruby:rdoc/trunk/%"
```

- [ ] **Step 3: Add rdoc recipe**

Append a new recipe:

```yaml
  - name: rdoc_class_search
    label: "RDoc クラス API 検索"
    description: "rdoc/trunk からクラス名パターンで API ドキュメント検索"
    sql: |
      SELECT content, source, created_at
        FROM memories
       WHERE source LIKE 'ruby/ruby:rdoc/trunk/%'
         AND source LIKE :class_pattern
       ORDER BY source
       LIMIT :limit
```

And add the corresponding clarification_field for class_pattern:

```yaml
  - name: class_pattern
    description: "クラス名パターン (例: %String%, %Ruby::Box%)"
    attrs:
      type: string
      required: false
      order: 5
      keywords:
        String: "ruby/ruby:rdoc/trunk/String"
        Array: "ruby/ruby:rdoc/trunk/Array"
        Hash: "ruby/ruby:rdoc/trunk/Hash"
        Integer: "ruby/ruby:rdoc/trunk/Integer"
        "Ruby::Box": "ruby/ruby:rdoc/trunk/Ruby::Box"
```

- [ ] **Step 4: Apply patches to test DB and verify**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/dotfiles/chiebukuro-mcp/chiebukuro-mcp
ruby scripts/apply_meta_patches.rb ruby_knowledge_test
```

Expected: patches applied without error.

- [ ] **Step 5: Commit in dotfiles repo**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/dotfiles
git add chiebukuro-mcp/chiebukuro-mcp/scripts/meta_patches/ruby_knowledge.yml
git commit -m "feat: add ruby/ruby:rdoc/trunk source to chiebukuro-mcp meta patches"
```

### Task 3.9: Open PR

- [ ] **Step 1: Push branch**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db-rdoc
git push -u origin feature/ruby-rdoc-collector
```

- [ ] **Step 2: Create PR**

Run:
```bash
gh pr create --title "feat: add ruby-rdoc-collector (trunk RDoc JP translation)" --body "$(cat <<'EOF'
## Summary
- Adds `ruby_rdoc_collector` gem (separate repo) that downloads pre-built RDoc darkfish HTML tarball from `cache.ruby-lang.org`, parses class/method data via Oga, translates EN descriptions to JP via Claude CLI (sonnet) with SHA256 cache, and emits class-unit Markdown.
- Data source: `ruby-docs-en-master.tar.xz` — generated daily by `ruby/actions` GitHub Actions pipeline (`make html` on ruby/ruby master).
- No ruby/ruby clone needed. No `cache:prepare` dependency. Self-contained download + parse + translate pipeline.
- Wires the collector into the existing `run_collector` helper with a new `update:ruby_rdoc` rake task and `scripts/update_all.rb` registration.
- Adds `ruby/ruby:rdoc/trunk/{ClassName}` source value and corresponding embedding prefix in `ruby-knowledge-store`.

## Test plan
- [x] gem unit tests (ruby-rdoc-collector): ~30 tests across 8 files, all pass with stub runner/fetcher
- [x] PoC smoke with real Claude CLI on Ruby::Box / String / Integer
- [x] Cache hit verified on second run
- [x] `APP_ENV=test rake update:ruby_rdoc` end-to-end integration smoke
- [x] Re-run produces `stored=0, skipped=N` (content_hash idempotency)
- [x] chiebukuro-mcp meta patches updated (source enum, keywords, recipe, interpretation guide)
- [ ] Production cost review before enabling in default schedule

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Stage 4 (out of scope — deferred)

- stdlib coverage (`ruby_rdoc_stdlib` source)
- Daily automation (rake daily integration)
- Batch parallelization of Claude CLI calls
- Translation quality regression suite
- Conditional download (ETag/If-Modified-Since) to skip unchanged tarballs

---

## Commands Reference

```bash
# Stage 2: gem tests (in ../ruby-rdoc-collector/)
bundle exec rake test

# Stage 2: PoC smoke (costs $)
bundle exec ruby bin/poc_smoke.rb Ruby::Box String Integer

# Stage 3: integration smoke
APP_ENV=test bundle exec rake update:ruby_rdoc

# Cleanup after merge
git worktree remove ../ruby-knowledge-db-rdoc
```
