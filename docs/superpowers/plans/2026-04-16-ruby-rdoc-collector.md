# ruby-rdoc-collector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task (user-selected 2026-04-16). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new docs collector `ruby-rdoc-collector` that extracts class-level RDoc from `ruby/ruby` trunk via `rdoc --format=json`, translates English descriptions to Japanese via Claude CLI (sonnet) with SHA256 cache, and stores class-unit Markdown into the knowledge DB under `ruby/ruby:rdoc/trunk/{ClassName}`.

**Architecture:** PoC-first staged approach with git worktree isolation. Stage 1 probes the `rdoc --format=json` output structure via a throwaway script. Stage 2 builds the gem skeleton with DI (runner/cache/extractor injectable for test and future swap). Stage 3 wires it into `ruby-knowledge-db` using the existing `run_collector` helper — zero new abstractions on the orchestration side. Partial failure is handled at class granularity (`filter_map + rescue`). Translation cache (keyed by `SHA256(model_tag + en_text)`) guarantees deterministic re-runs and `content_hash` idempotency.

**Tech Stack:** Ruby 3.2+ (`Data.define`), `rdoc` gem (bundled), Claude CLI (`claude --model sonnet -p -`), plain-file cache with atomic rename, `test-unit` xUnit style, `Open3.capture2e`/`capture3` for subprocess.

**Coexistence:**
- **rurema と完全独立**: `rurema/doctree` と `ruby/ruby` はデータ源別、source 値別 (`rurema/doctree:ruby4.0/{lib}#{class}` vs `ruby/ruby:rdoc/trunk/{ClassName}`)、last_run.yml キー別。rurema 側コードは一切触らない。
- **cruby-trunk-changes と git キャッシュ共有**: `~/.cache/trunk-changes-repos/ruby` を read-only で再利用。clone 責務は cruby-trunk-changes 側の `cache:prepare` に委譲、rdoc-collector は `repo_path` 指定で読むだけ。`update:ruby_rdoc` task に `cache:prepare` prereq を明示して単独実行時も安全に。
- **翻訳キャッシュは専用**: `~/.cache/ruby-rdoc-collector/` に SHA256 キー、git キャッシュと階層分離。
- **Downstream source disambiguation は本プラン対象外**: chiebukuro-mcp の `hints_json` 更新は別リポ別タスク（Stage 4 deferred）。

---

## Repository layout

Two repositories are touched by this plan:

1. **New gem:** `/Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector/` (brand new `git init`, bash0C7/ruby-rdoc-collector on GitHub)
2. **Integration:** `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/` (Stage 1 probe script + Stage 3 wiring), in worktree `../ruby-knowledge-db-rdoc/`

Plus one optional/satellite repo:

3. **Store source_prefix:** `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-store/lib/ruby_knowledge_store/store.rb` (Stage 3 Task 3.5), in worktree `../ruby-knowledge-store-rdoc/`

---

## File Structure

### New gem `../ruby-rdoc-collector/`

| File | Responsibility |
|------|----------------|
| `ruby_rdoc_collector.gemspec` | gem metadata |
| `Gemfile` | local deps (test-unit, rake) |
| `Rakefile` | `rake test` default |
| `README.md` | usage, cache invariants, repo sharing with cruby-trunk-changes |
| `lib/ruby_rdoc_collector.rb` | require aggregation |
| `lib/ruby_rdoc_collector/class_entity.rb` | `ClassEntity` / `MethodEntry` (Data.define) |
| `lib/ruby_rdoc_collector/translation_cache.rb` | SHA256-keyed file cache with atomic write |
| `lib/ruby_rdoc_collector/markdown_formatter.rb` | pure formatter: `ClassEntity` + JP description → Markdown |
| `lib/ruby_rdoc_collector/translator.rb` | Claude CLI wrapper, cache read/write, runner DI, retry |
| `lib/ruby_rdoc_collector/repo_manager.rb` | read-only repo path resolver (no git writes; ensures path exists) |
| `lib/ruby_rdoc_collector/rdoc_extractor.rb` | `rdoc --format=json` subprocess + JSON parse → `Array<ClassEntity>` |
| `lib/ruby_rdoc_collector/collector.rb` | thin façade implementing the unified `collect(since:, before:)` IF |
| `test/test_helper.rb` | StubRunner, EchoRunner, FailingRunner, fixture loader |
| `test/test_class_entity.rb` | Data struct field check |
| `test/test_translation_cache.rb` | read/write/miss, atomic write |
| `test/test_markdown_formatter.rb` | pure-function snapshot test |
| `test/test_translator.rb` | cache hit/miss, runner retry |
| `test/test_repo_manager.rb` | path guard, read-only behavior |
| `test/test_rdoc_extractor.rb` | JSON fixture → ClassEntity mapping |
| `test/test_collector.rb` | full DI, partial failure (1 class error skipped) |
| `test/fixtures/sample_rdoc.json` | 2–3 class fixture derived from Stage 1 probe output |
| `bin/poc_smoke.rb` | real Claude CLI PoC smoke script (Stage 2.9) |

### ruby-knowledge-db (modifications, in worktree)

| File | Change |
|------|--------|
| `scripts/explore_rdoc_json.rb` | **Create** — Stage 1 probe script |
| `Gemfile` | **Modify** — add `gem 'ruby_rdoc_collector', path: '../ruby-rdoc-collector'` |
| `config/sources.yml` | **Modify** — add `ruby_rdoc:` key with shared-cache comment |
| `Rakefile` | **Modify** — `require_update_deps` + `namespace :update` task with `cache:prepare` prereq |
| `scripts/update_all.rb` | **Modify** — require + collectors array entry |
| `CLAUDE.md` | **Modify** — add source 値規約行、依存 repo 表行 |

### ruby-knowledge-store (Stage 3 Task 3.5, separate worktree)

| File | Change |
|------|--------|
| `lib/ruby_knowledge_store/store.rb` | **Modify** — add `when /\Aruby\/ruby:rdoc\/trunk\//` case in `source_prefix` |
| `test/test_store.rb` | **Modify** — add case coverage test |

---

## Stage 0: Worktree setup

### Task 0.1: Create isolated worktree for ruby-knowledge-db changes

**Files:** none (git operation only)

- [ ] **Step 1: Create worktree from main**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
git worktree add ../ruby-knowledge-db-rdoc -b feature/ruby-rdoc-collector main
```

Expected: `Preparing worktree (new branch 'feature/ruby-rdoc-collector')`

- [ ] **Step 2: Verify worktree**

Run:
```bash
git worktree list
```

Expected: at least two entries, one for `.../ruby-knowledge-db` on `main`, one for `.../ruby-knowledge-db-rdoc` on `feature/ruby-rdoc-collector`.

- [ ] **Step 3: Install bundle in worktree**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db-rdoc
bundle config set --local path 'vendor/bundle'
bundle install
```

Expected: `Bundle complete!`

**All subsequent ruby-knowledge-db-side tasks run in `../ruby-knowledge-db-rdoc/` worktree.**

---

## Stage 1: Probe `rdoc --format=json` output

**Goal:** Determine the exact JSON structure (top-level shape, class entity fields, method entity fields, whether C-defined classes like `Ruby::Box` are represented) so Stage 2's `RdocExtractor` can be implemented confidently.

### Task 1.1: Ensure ruby/ruby is cloned locally

**Files:** none (git operation)

- [ ] **Step 1: Check / clone ruby/ruby**

Run:
```bash
REPO=~/.cache/trunk-changes-repos/ruby
if [ ! -d "$REPO/.git" ]; then
  mkdir -p ~/.cache/trunk-changes-repos
  git clone --no-single-branch https://github.com/ruby/ruby.git "$REPO"
else
  cd "$REPO" && git fetch origin && git reset --hard origin/HEAD
fi
cd "$REPO" && git rev-parse HEAD
```

Expected: SHA of origin/HEAD printed. Note it down for the Stage 1 report.

### Task 1.2: Write the probe script

**Files:**
- Create (in worktree `../ruby-knowledge-db-rdoc/`): `scripts/explore_rdoc_json.rb`

- [ ] **Step 1: Create the probe script**

File: `scripts/explore_rdoc_json.rb`

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# Probe `rdoc --format=json` output shape.
# Usage: RUBY_REPO=~/.cache/trunk-changes-repos/ruby ruby scripts/explore_rdoc_json.rb

require 'json'
require 'tmpdir'
require 'open3'

repo    = ENV.fetch('RUBY_REPO', File.expand_path('~/.cache/trunk-changes-repos/ruby'))
targets = %w[Ruby::Box String Integer Array]

abort "repo not found: #{repo}" unless Dir.exist?(repo)

Dir.mktmpdir('rdoc_probe') do |outdir|
  cmd = ['rdoc', '--format=json', "--output=#{outdir}", repo]
  puts "$ #{cmd.join(' ')}"
  out, status = Open3.capture2e(*cmd)
  unless status.success?
    warn out
    abort "rdoc failed with status #{status.exitstatus}"
  end

  json_files = Dir.glob(File.join(outdir, '**', '*.json'))
  puts "Generated #{json_files.size} JSON file(s)"
  puts "First 3 paths: #{json_files.first(3).inspect}"
  puts "Total size: #{json_files.sum { |f| File.size(f) }} bytes"

  json_files.first(5).each do |f|
    data = begin
      JSON.parse(File.read(f))
    rescue JSON::ParserError => e
      warn "parse error #{f}: #{e.message}"
      next
    end
    puts "=== #{f.sub(outdir, '')} ==="
    puts "  top-level class: #{data.class}"
    if data.is_a?(Hash)
      puts "  keys: #{data.keys.take(20).join(', ')}"
    elsif data.is_a?(Array)
      puts "  length: #{data.size}"
      puts "  first elem keys: #{data.first&.keys&.take(20)&.join(', ')}" if data.first.is_a?(Hash)
    end
  end

  targets.each do |target|
    puts "\n### target: #{target}"
    found = false
    json_files.each do |f|
      data = JSON.parse(File.read(f)) rescue next
      entries = data.is_a?(Array) ? data : [data]
      entries.each do |e|
        next unless e.is_a?(Hash)
        name = e['full_name'] || e['name']
        next unless name == target
        found = true
        puts "  file: #{f.sub(outdir, '')}"
        puts "  keys: #{e.keys.sort.join(', ')}"
        %w[description comment full_comment methods method_list superclass].each do |k|
          v = e[k]
          desc = v.is_a?(String) ? v[0, 200].inspect : v.class.to_s
          desc += " size=#{v.size}" if v.is_a?(Array)
          puts "    #{k}: #{desc}"
        end
      end
    end
    puts "  NOT FOUND" unless found
  end
end
```

- [ ] **Step 2: Run the probe**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db-rdoc
bundle exec ruby scripts/explore_rdoc_json.rb 2>&1 | tee /tmp/rdoc_probe.log
```

Expected: JSON file list + class key dumps. Script exits 0.

- [ ] **Step 3: Record findings**

Prepend a `# Findings:` block to the probe script documenting:
- Top-level JSON: Array or Hash?
- Class entity field names for description: `description` / `comment` / `full_comment` / other?
- Method entity field names for signature: `call_seq` / `arglists` / other?
- Method entity field for method-level description
- Field name for "source file" (used for builtin vs stdlib filter): `file` / `files` / other?
- Is `Ruby::Box` present? (class exists in Ruby 4.0 trunk — see https://docs.ruby-lang.org/en/4.0/Ruby/Box.html)
- Is description HTML-escaped, Markdown-ish, or RDoc-raw?

- [ ] **Step 4: Commit probe script and findings**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db-rdoc
git add scripts/explore_rdoc_json.rb docs/superpowers/plans/2026-04-16-ruby-rdoc-collector.md
git commit -m "chore: add rdoc --format=json probe script for ruby-rdoc-collector plan"
```

**Go/No-Go checkpoint:** After Stage 1, stop and show findings to the user. If `Ruby::Box` is absent from rdoc json OR description fields are all empty, reconsider the approach before proceeding to Stage 2.

### Task 1.3: Prepare fixture material

**Files:** none (scratch, copied into gem at Task 2.7)

- [ ] **Step 1: Save 2–3 class JSON entries for reuse as fixture**

Copy the raw JSON for `Ruby::Box`, `String`, and one more class (e.g. `Integer`) from the probe output to `/tmp/rdoc_probe_fixture.json`. These will become `test/fixtures/sample_rdoc.json` in Task 2.7 once the gem exists. Do not commit to the worktree yet.

---

## Stage 2: Gem skeleton (TDD)

**All Stage 2 tasks operate inside `/Users/bash/dev/src/github.com/bash0C7/ruby-rdoc-collector/` (brand new repo, no worktree needed).**

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
mkdir -p lib/ruby_rdoc_collector test/fixtures bin
```

- [ ] **Step 2: Write gemspec**

File: `ruby_rdoc_collector.gemspec`

```ruby
Gem::Specification.new do |spec|
  spec.name          = 'ruby_rdoc_collector'
  spec.version       = '0.1.0'
  spec.summary       = 'RDoc JSON collector with JP translation for ruby knowledge DB'
  spec.authors       = ['bash0C7']
  spec.files         = Dir['lib/**/*.rb']
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.2.0'
  spec.add_dependency 'rdoc'
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

Collector that extracts class-level RDoc from `ruby/ruby` trunk via `rdoc --format=json`, translates English descriptions into Japanese via Claude CLI (sonnet), and emits `{content:, source:}` pairs for the [ruby-knowledge-db](https://github.com/bash0C7/ruby-knowledge-db) pipeline.

## Source value

`ruby/ruby:rdoc/trunk/{ClassName}` — one record per class.

## Caches

Two caches, split by responsibility:

| Path | Owner | Mode |
|------|-------|------|
| `~/.cache/trunk-changes-repos/ruby` | cruby-trunk-changes (`rake cache:prepare`) | shared, read-only for this gem |
| `~/.cache/ruby-rdoc-collector/` | this gem | read/write |

**Invariant:** this gem does not run any `git` write command. The clone / fetch / reset of `ruby/ruby` is the responsibility of cruby-trunk-changes' `cache:prepare`. If you invoke this collector standalone, run `rake cache:prepare` (in ruby-knowledge-db) first.

## Translation cache key

```
SHA256("claude-sonnet::" + en_text)
```

Re-running the collector with unchanged upstream descriptions is a full cache hit with zero Claude CLI calls. Changing `en_text` (even by one character) invalidates that entry.

## Usage

```ruby
require 'ruby_rdoc_collector'

collector = RubyRdocCollector::Collector.new(
  'repo_path' => '~/.cache/trunk-changes-repos/ruby',
  'filter'    => 'builtin_only'
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
require_relative 'ruby_rdoc_collector/repo_manager'
require_relative 'ruby_rdoc_collector/rdoc_extractor'
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

- [ ] **Step 9: Install bundle and verify Rakefile wiring**

Run:
```bash
bundle config set --local path 'vendor/bundle'
bundle install
bundle exec rake test
```

Expected: 0 tests, 0 assertions, 0 failures (no `test_*.rb` yet). Exit 0. NOTE: this only works after Task 2.2 (otherwise requires in `ruby_rdoc_collector.rb` will fail). If you want a sanity run now, comment out all require_relative lines in `lib/ruby_rdoc_collector.rb` until Task 2.2 re-adds `class_entity`.

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

Run:
```bash
bundle exec rake test TESTOPTS="--name=/ClassEntity/"
```

Expected: FAIL with `NameError: uninitialized constant RubyRdocCollector::ClassEntity` or load error.

- [ ] **Step 3: Implement**

File: `lib/ruby_rdoc_collector/class_entity.rb`

```ruby
module RubyRdocCollector
  MethodEntry = Data.define(:name, :call_seq, :description)
  ClassEntity = Data.define(:name, :description, :methods, :constants, :superclass)
end
```

- [ ] **Step 4: Run test**

Run:
```bash
bundle exec rake test TESTOPTS="--name=/ClassEntity/"
```

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

Run:
```bash
bundle exec rake test TESTOPTS="--name=/TranslationCache/"
```

Expected: FAIL with load error.

- [ ] **Step 3: Implement**

File: `lib/ruby_rdoc_collector/translation_cache.rb`

```ruby
require 'fileutils'
require 'tempfile'

module RubyRdocCollector
  class TranslationCache
    DEFAULT_DIR = File.expand_path('~/.cache/ruby-rdoc-collector')

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

Run:
```bash
bundle exec rake test TESTOPTS="--name=/TranslationCache/"
```

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
      superclass: 'Object'
    )
    @formatter = RubyRdocCollector::MarkdownFormatter.new
  end

  def test_emits_class_header_with_superclass
    md = @formatter.format(@entity, jp_description: 'Ruby::Box は単一の値をラップする。', jp_method_descriptions: {})
    assert_match(/\A# Ruby::Box/, md)
    assert_include md, '(< Object)'
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

Run:
```bash
bundle exec rake test TESTOPTS="--name=/MarkdownFormatter/"
```

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

Run:
```bash
bundle exec rake test TESTOPTS="--name=/MarkdownFormatter/"
```

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

Translation request/response unit: each `Translator#translate` call handles ONE text block (class description OR one method description). Fine cache granularity, avoids token-limit issues on large classes, cost scales with actual text churn.

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

Run:
```bash
bundle exec rake test TESTOPTS="--name=/TestTranslator/"
```

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
      次の英語テキストを日本語に翻訳してください。ただし以下の制約を守ること:
      - コードブロック、メソッドシグネチャ、識別子（クラス名・メソッド名・定数名）は**原文のまま**保持
      - 散文（説明文）のみを自然な日本語に翻訳
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

Run:
```bash
bundle exec rake test TESTOPTS="--name=/TestTranslator/"
```

Expected: 6 tests, PASS.

- [ ] **Step 5: Commit**

Run:
```bash
git add lib/ruby_rdoc_collector/translator.rb test/test_translator.rb
git commit -m "feat: add Translator with SHA256 cache and retry"
```

### Task 2.6: `RepoManager`

**Files:**
- Create: `lib/ruby_rdoc_collector/repo_manager.rb`
- Test: `test/test_repo_manager.rb`

**Design note:** RepoManager is READ-ONLY. It does NOT run `git clone`/`fetch`/`reset`. That is the responsibility of cruby-trunk-changes' `cache:prepare`. RepoManager's job is to verify the path exists and expose `repo_path` + `head_sha`. If the path is missing, it raises with a helpful error telling the user to run `cache:prepare`.

- [ ] **Step 1: Write failing test**

File: `test/test_repo_manager.rb`

```ruby
require_relative 'test_helper'

class TestRepoManager < Test::Unit::TestCase
  def test_raises_when_path_missing
    Dir.mktmpdir do |dir|
      nonexistent = File.join(dir, 'nope')
      mgr = RubyRdocCollector::RepoManager.new(repo_path: nonexistent)
      err = assert_raise(RubyRdocCollector::RepoManager::RepoNotReadyError) { mgr.ensure_ready }
      assert_match(/cache:prepare/, err.message)
    end
  end

  def test_raises_when_path_not_git_repo
    Dir.mktmpdir do |dir|
      mgr = RubyRdocCollector::RepoManager.new(repo_path: dir)
      assert_raise(RubyRdocCollector::RepoManager::RepoNotReadyError) { mgr.ensure_ready }
    end
  end

  def test_succeeds_when_dot_git_present
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, '.git'))
      mgr = RubyRdocCollector::RepoManager.new(repo_path: dir)
      assert_nothing_raised { mgr.ensure_ready }
      assert_equal dir, mgr.repo_path
    end
  end

  def test_head_sha_uses_shell_dep_injection
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, '.git'))
      shell = ->(*_cmd, **_opts) { ['abc123\n', '', stub_success] }
      mgr = RubyRdocCollector::RepoManager.new(repo_path: dir, shell: shell)
      assert_equal 'abc123', mgr.head_sha
    end
  end

  private

  def stub_success
    s = Object.new
    def s.success?; true end
    def s.exitstatus; 0 end
    s
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
bundle exec rake test TESTOPTS="--name=/TestRepoManager/"
```

Expected: FAIL with load error.

- [ ] **Step 3: Implement**

File: `lib/ruby_rdoc_collector/repo_manager.rb`

```ruby
require 'open3'

module RubyRdocCollector
  class RepoManager
    class RepoNotReadyError < StandardError; end

    DEFAULT_REPO_PATH = File.expand_path('~/.cache/trunk-changes-repos/ruby')

    def initialize(repo_path: DEFAULT_REPO_PATH, shell: nil)
      @repo_path = repo_path
      @shell     = shell || method(:default_shell)
    end

    attr_reader :repo_path

    # Read-only guard. Does NOT clone/fetch. Clone is owned by cruby-trunk-changes cache:prepare.
    def ensure_ready
      unless Dir.exist?(@repo_path) && Dir.exist?(File.join(@repo_path, '.git'))
        raise RepoNotReadyError, <<~MSG
          repo not found at #{@repo_path}. Run `rake cache:prepare` in ruby-knowledge-db first,
          or let the update:ruby_rdoc rake task do it for you (cache:prepare is declared as prereq).
        MSG
      end
    end

    def head_sha
      stdout, _stderr, status = @shell.call('git', 'rev-parse', 'HEAD', chdir: @repo_path)
      raise RepoNotReadyError, 'git rev-parse failed' unless status.success?
      stdout.strip
    end

    private

    def default_shell(*cmd, **opts)
      Open3.capture3(*cmd, **opts)
    end
  end
end
```

- [ ] **Step 4: Run test**

Run:
```bash
bundle exec rake test TESTOPTS="--name=/TestRepoManager/"
```

Expected: 4 tests, PASS.

- [ ] **Step 5: Commit**

Run:
```bash
git add lib/ruby_rdoc_collector/repo_manager.rb test/test_repo_manager.rb
git commit -m "feat: add read-only RepoManager (clone delegated to cache:prepare)"
```

### Task 2.7: `RdocExtractor`

**Files:**
- Create: `lib/ruby_rdoc_collector/rdoc_extractor.rb`
- Create: `test/fixtures/sample_rdoc.json` (derived from Stage 1 probe)
- Test: `test/test_rdoc_extractor.rb`

**Note:** JSON field names below (`description`, `methods`, `name`, `superclass`, `call_seq`, `file`) are *placeholders based on current rdoc conventions*. Before implementing, open the Stage 1 findings block in `scripts/explore_rdoc_json.rb` (in ruby-knowledge-db-rdoc worktree) and substitute the actual field names.

- [ ] **Step 1: Copy fixture from probe output**

Copy content prepared in Task 1.3 (`/tmp/rdoc_probe_fixture.json`) into `test/fixtures/sample_rdoc.json`. Keep only the fields used.

Example (adjust field names per Stage 1 findings):

```json
{
  "name": "Ruby::Box",
  "full_name": "Ruby::Box",
  "description": "A Ruby::Box wraps a single value.",
  "superclass": "Object",
  "file": "object.c",
  "methods": [
    {"name": "value", "call_seq": "box.value -> object", "description": "Returns the wrapped value."},
    {"name": "replace", "call_seq": "box.replace(obj) -> obj", "description": "Replaces the wrapped value."}
  ],
  "constants": []
}
```

- [ ] **Step 2: Write failing test**

File: `test/test_rdoc_extractor.rb`

```ruby
require_relative 'test_helper'

class TestRdocExtractor < Test::Unit::TestCase
  class FixtureRdocRunner
    def call(_repo_path, outdir)
      FileUtils.cp(File.join(FIXTURE_DIR, 'sample_rdoc.json'), outdir)
      true
    end
  end

  def test_parses_fixture_into_class_entities
    extractor = RubyRdocCollector::RdocExtractor.new(rdoc_runner: FixtureRdocRunner.new)
    entities = extractor.extract(repo_path: '/fake/repo', filter: :all)
    assert_equal 1, entities.size
    e = entities.first
    assert_equal 'Ruby::Box', e.name
    assert_equal 'Object', e.superclass
    assert_equal 2, e.methods.size
    assert_equal 'value', e.methods.first.name
    assert_equal 'box.value -> object', e.methods.first.call_seq
  end

  def test_builtin_only_filter_excludes_stdlib_entries
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'mixed.json')
      File.write(path, JSON.generate([
        { 'name' => 'String', 'full_name' => 'String', 'description' => 'x',
          'superclass' => 'Object', 'methods' => [], 'constants' => [],
          'file' => 'string.c' },
        { 'name' => 'Net::HTTP', 'full_name' => 'Net::HTTP', 'description' => 'y',
          'superclass' => 'Object', 'methods' => [], 'constants' => [],
          'file' => 'lib/net/http.rb' }
      ]))
      runner = ->(_repo, outdir) { FileUtils.cp(path, outdir); true }
      extractor = RubyRdocCollector::RdocExtractor.new(rdoc_runner: runner)
      entities = extractor.extract(repo_path: '/fake/repo', filter: :builtin_only)
      names = entities.map(&:name)
      assert_include names, 'String'
      refute_include names, 'Net::HTTP'
    end
  end

  def test_raises_when_runner_fails
    failing = ->(_repo, _out) { raise 'rdoc boom' }
    extractor = RubyRdocCollector::RdocExtractor.new(rdoc_runner: failing)
    assert_raise(RubyRdocCollector::RdocExtractor::ExtractError) do
      extractor.extract(repo_path: '/fake/repo')
    end
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run:
```bash
bundle exec rake test TESTOPTS="--name=/TestRdocExtractor/"
```

Expected: FAIL with load error.

- [ ] **Step 4: Implement**

File: `lib/ruby_rdoc_collector/rdoc_extractor.rb`

```ruby
require 'json'
require 'tmpdir'
require 'open3'

module RubyRdocCollector
  class RdocExtractor
    class ExtractError < StandardError; end

    # builtin = no file OR file ending in .c OR top-level lib/*.rb (NOT lib/*/*.rb which is stdlib)
    BUILTIN_FILE_PATTERN = %r{(\.c\z|\Alib/[^/]+\.rb\z|\A\z)}

    def initialize(rdoc_runner: nil)
      @rdoc_runner = rdoc_runner || method(:default_rdoc_runner)
    end

    # @param repo_path [String]
    # @param filter [Symbol] :builtin_only or :all
    # @return [Array<ClassEntity>]
    def extract(repo_path:, filter: :builtin_only)
      entities = []
      Dir.mktmpdir('rdoc_extract') do |outdir|
        begin
          @rdoc_runner.call(repo_path, outdir)
        rescue => e
          raise ExtractError, "rdoc runner failed: #{e.class}: #{e.message}"
        end

        Dir.glob(File.join(outdir, '**', '*.json')).each do |f|
          data = JSON.parse(File.read(f))
          records = data.is_a?(Array) ? data : [data]
          records.each do |r|
            next unless r.is_a?(Hash)
            next unless class_record?(r)
            next if filter == :builtin_only && !builtin?(r)
            entities << to_entity(r)
          end
        end
      end
      entities
    end

    private

    def class_record?(r)
      r['name'] && (r['methods'] || r['description'] || r['comment'])
    end

    def builtin?(r)
      file = r['file'] || Array(r['files']).first || ''
      BUILTIN_FILE_PATTERN.match?(file)
    end

    def to_entity(r)
      methods = Array(r['methods'] || r['method_list']).map do |m|
        MethodEntry.new(
          name:        m['name'] || '',
          call_seq:    m['call_seq'] || m['arglists'],
          description: m['description'] || m['comment'] || ''
        )
      end
      ClassEntity.new(
        name:        r['full_name'] || r['name'],
        description: r['description'] || r['comment'] || '',
        methods:     methods,
        constants:   Array(r['constants']),
        superclass:  r['superclass'] || 'Object'
      )
    end

    def default_rdoc_runner(repo_path, outdir)
      _out, status = Open3.capture2e('rdoc', '--format=json', "--output=#{outdir}", repo_path)
      raise ExtractError, "rdoc exit #{status.exitstatus}" unless status.success?
      true
    end
  end
end
```

**If Stage 1 revealed different field names, adjust `class_record?`, `builtin?`, and `to_entity` to match BEFORE running the tests below.**

- [ ] **Step 5: Run test**

Run:
```bash
bundle exec rake test TESTOPTS="--name=/TestRdocExtractor/"
```

Expected: 3 tests, PASS.

- [ ] **Step 6: Commit**

Run:
```bash
git add lib/ruby_rdoc_collector/rdoc_extractor.rb test/test_rdoc_extractor.rb test/fixtures/sample_rdoc.json
git commit -m "feat: add RdocExtractor with builtin filter"
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
  class StubRepoManager
    def initialize(path: '/fake/repo'); @path = path; end
    def ensure_ready; end
    def repo_path; @path; end
  end

  class StubExtractor
    def initialize(entities); @entities = entities; end
    def extract(repo_path:, filter: :builtin_only); @entities; end
  end

  class BoomExtractor
    def extract(repo_path:, filter: :builtin_only); raise 'boom'; end
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
      repo_manager: StubRepoManager.new,
      extractor:    StubExtractor.new(entities),
      translator:   @translator,
      formatter:    RubyRdocCollector::MarkdownFormatter.new)
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
      repo_manager: StubRepoManager.new,
      extractor:    StubExtractor.new(entities),
      translator:   boom_translator,
      formatter:    RubyRdocCollector::MarkdownFormatter.new)
    results = c.collect
    sources = results.map { |r| r[:source] }
    assert_equal 1, results.size
    assert_include sources, 'ruby/ruby:rdoc/trunk/String'
    refute_include sources, 'ruby/ruby:rdoc/trunk/Integer'
  end

  def test_extractor_failure_raises_whole_batch
    c = RubyRdocCollector::Collector.new({},
      repo_manager: StubRepoManager.new,
      extractor:    BoomExtractor.new,
      translator:   @translator,
      formatter:    RubyRdocCollector::MarkdownFormatter.new)
    assert_raise(RuntimeError) { c.collect }
  end

  def test_since_and_before_are_ignored
    entities = [build_entity('A')]
    c = RubyRdocCollector::Collector.new({},
      repo_manager: StubRepoManager.new,
      extractor:    StubExtractor.new(entities),
      translator:   @translator,
      formatter:    RubyRdocCollector::MarkdownFormatter.new)
    r1 = c.collect(since: '2020-01-01', before: '2020-01-02')
    r2 = c.collect
    assert_equal r1, r2
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
bundle exec rake test TESTOPTS="--name=/TestCollector/"
```

Expected: FAIL with load error.

- [ ] **Step 3: Implement**

File: `lib/ruby_rdoc_collector/collector.rb`

```ruby
module RubyRdocCollector
  class Collector
    SOURCE_PREFIX = 'ruby/ruby:rdoc/trunk'

    def initialize(config,
                   repo_manager: nil,
                   extractor:    nil,
                   translator:   nil,
                   formatter:    nil)
      @config       = config || {}
      @repo_manager = repo_manager || RepoManager.new(
        repo_path: @config['repo_path'] ? File.expand_path(@config['repo_path']) : RepoManager::DEFAULT_REPO_PATH
      )
      @extractor  = extractor  || RdocExtractor.new
      @translator = translator || Translator.new
      @formatter  = formatter  || MarkdownFormatter.new
      @filter     = (@config['filter'] || 'builtin_only').to_sym
    end

    # since/before are ignored. content_hash idempotency upstream.
    def collect(since: nil, before: nil)
      @repo_manager.ensure_ready
      entities = @extractor.extract(repo_path: @repo_manager.repo_path, filter: @filter)
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

Run:
```bash
bundle exec rake test TESTOPTS="--name=/TestCollector/"
```

Expected: 4 tests, PASS.

- [ ] **Step 5: Run full suite**

Run:
```bash
bundle exec rake test
```

Expected: ~27 tests across 8 files, all PASS.

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
# Usage: bundle exec ruby bin/poc_smoke.rb Ruby::Box String Integer
# Prereq: `rake cache:prepare` in ruby-knowledge-db has cloned ~/.cache/trunk-changes-repos/ruby.
require 'bundler/setup'
require 'ruby_rdoc_collector'

targets = ARGV.empty? ? ['Ruby::Box', 'String', 'Integer'] : ARGV

collector = RubyRdocCollector::Collector.new('filter' => 'all')
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

Expected: 3 Markdown blocks printed. Each has `# ClassName` header, `## 概要` with JP text, and `## Methods` with EN signatures + JP descriptions.

- [ ] **Step 3: Re-run to verify cache**

Run:
```bash
time bundle exec ruby bin/poc_smoke.rb Ruby::Box String Integer > /dev/null
```

Expected: elapsed seconds ≪ first run (cache hit on all translations).

- [ ] **Step 4: Record PoC findings**

Edit `bin/poc_smoke.rb` top comment block with:
- Wall-clock time first run vs cached run
- Approx Claude CLI call count (classes × (1 + avg_methods_per_class))
- Quality verdict on Ruby::Box output (pass/fail)
- Estimated $/class based on elapsed time × Claude CLI rate

**CHECKPOINT: Report findings to user. If quality fails or cost projects unacceptable for full rollout, stop and re-evaluate before Stage 3.**

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

**All Stage 3 tasks (except 3.5) operate in `../ruby-knowledge-db-rdoc/` worktree from Stage 0.**

### Task 3.1: Add gem to Gemfile

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add gem entry**

Open `Gemfile` and in the block of `path: '../...'` gems (near the existing `rurema_collector` / `picoruby_docs_collector` entries around line 17), add:

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

Open `config/sources.yml` and add under the top-level `sources:` map (after `picoruby_docs:`). The comment documents the shared cache invariant:

```yaml
  # ruby/ruby trunk RDoc → JP translation.
  # repo_path is SHARED with cruby-trunk-changes (read-only).
  # Clone/fetch is owned by `rake cache:prepare`; this collector never writes to the repo.
  ruby_rdoc:
    repo_path: ~/.cache/trunk-changes-repos/ruby
    filter: builtin_only
```

- [ ] **Step 2: Verify YAML parses**

Run:
```bash
ruby -ryaml -e 'puts YAML.load_file("config/sources.yml")["sources"]["ruby_rdoc"].inspect'
```

Expected: `{"repo_path"=>"~/.cache/trunk-changes-repos/ruby", "filter"=>"builtin_only"}` printed.

- [ ] **Step 3: Commit**

Run:
```bash
git add config/sources.yml
git commit -m "feat: add ruby_rdoc source config (shared cache with cruby-trunk-changes)"
```

### Task 3.3: Add `rake update:ruby_rdoc` task with `cache:prepare` prereq

**Files:**
- Modify: `Rakefile`

- [ ] **Step 1: Confirm `cache:prepare` task exists and name**

Run:
```bash
bundle exec rake -T | grep cache:prepare
```

Expected: at least one `cache:prepare` task listed (from cruby-trunk-changes integration). Record the exact task name (it may be `cache:prepare` or `cache:prepare_cruby`).

- [ ] **Step 2: Add require to `require_update_deps`**

Open `Rakefile`, locate `def require_update_deps` around line 42:

```ruby
def require_update_deps
  require_store_deps
  require 'rurema_collector'
  require 'picoruby_docs_collector'
  require 'ruby_rdoc_collector'
end
```

- [ ] **Step 3: Add update task with prereq**

Locate the `namespace :update do` block around line 282. Append after `task :picoruby_docs`:

```ruby
  desc "Update ruby rdoc (SINCE/BEFORE accepted but ignored — full collect always). Requires cache:prepare."
  task :ruby_rdoc => ['cache:prepare'] do
    run_collector(:ruby_rdoc, 'RubyRdocCollector::Collector', 'ruby_rdoc')
  end
```

**If Step 1 revealed a different task name (e.g. `cache:prepare_cruby`), substitute it in the `=> [...]` array.**

- [ ] **Step 4: Verify task is registered with dependency**

Run:
```bash
bundle exec rake -T | grep ruby_rdoc
bundle exec rake -P | grep -A1 update:ruby_rdoc
```

Expected: `rake update:ruby_rdoc  # Update ruby rdoc ...` and the prereq chain shows `cache:prepare` under `update:ruby_rdoc`.

- [ ] **Step 5: Commit**

Run:
```bash
git add Rakefile
git commit -m "feat: add rake update:ruby_rdoc task with cache:prepare prereq"
```

### Task 3.4: Register in `scripts/update_all.rb`

**Files:**
- Modify: `scripts/update_all.rb`

- [ ] **Step 1: Add require**

Around line 15 (after `require 'picoruby_docs_collector'`), add:

```ruby
require 'ruby_rdoc_collector'
```

- [ ] **Step 2: Add collector to array**

Around line 31 (the `collectors = [...]` array), append before `].compact`:

```ruby
  srcs['ruby_rdoc']      && RubyRdocCollector::Collector.new(srcs['ruby_rdoc']),
```

- [ ] **Step 3: Verify the script still loads**

Run:
```bash
APP_ENV=test bundle exec ruby -c scripts/update_all.rb
APP_ENV=test bundle exec ruby -e 'require "./lib/ruby_knowledge_db/config"; puts "syntax ok"'
```

Expected: `Syntax OK` for `-c`, `syntax ok` for the second command.

- [ ] **Step 4: Commit**

Run:
```bash
git add scripts/update_all.rb
git commit -m "feat: register ruby_rdoc collector in update_all.rb"
```

### Task 3.5: Add `source_prefix` case in ruby-knowledge-store

**Files:**
- Modify (separate worktree): `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-store/lib/ruby_knowledge_store/store.rb`

- [ ] **Step 1: Create worktree for store change**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-store
git worktree add ../ruby-knowledge-store-rdoc -b feature/rdoc-source-prefix main
cd ../ruby-knowledge-store-rdoc
bundle install
```

- [ ] **Step 2: Inspect existing cases**

Run:
```bash
grep -n "source_prefix\|rurema/doctree\|build_embedding_text" lib/ruby_knowledge_store/store.rb
```

Record the exact format of the rurema case branch to mirror it.

- [ ] **Step 3: Write failing test**

Open `test/test_store.rb`, find the existing `source_prefix` / embedding text tests, and add (matching the file's existing style):

```ruby
def test_source_prefix_for_ruby_rdoc_trunk_class
  store = RubyKnowledgeStore::Store.new(':memory:', embedder: StubEmbedder.new)
  text = store.send(:build_embedding_text, 'dummy content', 'ruby/ruby:rdoc/trunk/Ruby::Box')
  assert_match(/Ruby::Box/, text)
  assert_match(/trunk/, text)
end
```

(Adapt `StubEmbedder` reference if the test file uses a different name.)

- [ ] **Step 4: Run test to verify it fails**

Run:
```bash
bundle exec rake test TESTOPTS="--name=/ruby_rdoc_trunk/"
```

Expected: FAIL (new case not added yet).

- [ ] **Step 5: Add case branch**

In `lib/ruby_knowledge_store/store.rb`'s `build_embedding_text` / `source_prefix` method (around lines 68–98), add a new `when` clause following the rurema pattern:

```ruby
when %r{\Aruby/ruby:rdoc/trunk/(?<class_name>.+)\z}
  class_name = Regexp.last_match[:class_name]
  "Ruby trunk #{class_name} クラス ... ruby/ruby trunk RDoc ドキュメント: "
```

(Mirror the exact Japanese cadence of the existing rurema `when` clause.)

- [ ] **Step 6: Run test**

Run:
```bash
bundle exec rake test TESTOPTS="--name=/ruby_rdoc_trunk/"
bundle exec rake test
```

Expected: new test PASS, full suite PASS.

- [ ] **Step 7: Commit**

Run:
```bash
git add lib/ruby_knowledge_store/store.rb test/test_store.rb
git commit -m "feat: add source_prefix case for ruby/ruby:rdoc/trunk"
```

### Task 3.6: Integration smoke test (APP_ENV=test)

**Files:** none

- [ ] **Step 1: Prime the shared cache via cache:prepare**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db-rdoc
APP_ENV=test bundle exec rake cache:prepare 2>&1 | tail -5
```

Expected: cache:prepare completes, `~/.cache/trunk-changes-repos/ruby` at HEAD of origin.

- [ ] **Step 2: Record baseline DB state**

Run:
```bash
APP_ENV=test bundle exec rake db:stats 2>&1 | head -20
```

Note existing `source` counts.

- [ ] **Step 3: Run collector end-to-end against test DB**

Run:
```bash
APP_ENV=test SINCE=2026-01-01 BEFORE=2026-04-17 bundle exec rake update:ruby_rdoc 2>&1 | tee /tmp/rdoc_integration.log
```

Expected: `ruby_rdoc: stored=N, skipped=0` where N > 0. No `ERROR:` lines. NOTE: this invocation will also run `cache:prepare` first (prereq).

- [ ] **Step 4: Verify entries in DB**

Run:
```bash
APP_ENV=test bundle exec rake db:stats
APP_ENV=test bundle exec ruby -r sqlite3 -r sqlite_vec -e '
  require "./lib/ruby_knowledge_db/config"
  cfg = RubyKnowledgeDb::Config.load
  db_path = File.expand_path(cfg["db_path"], __dir__)
  db = SQLite3::Database.new(db_path)
  db.results_as_hash = true
  puts db.execute("SELECT source, substr(content, 1, 80) AS preview FROM memories WHERE source LIKE ? LIMIT 5", ["ruby/ruby:rdoc/trunk/%"]).inspect
'
```

Expected: 5 rows with `ruby/ruby:rdoc/trunk/ClassName` sources, JP-containing previews.

- [ ] **Step 5: Verify `last_run.yml` was updated**

Run:
```bash
grep -A1 'RubyRdocCollector' db/last_run.yml
```

Expected: `RubyRdocCollector::Collector: '2026-04-17'` (or whatever BEFORE was).

- [ ] **Step 6: Rerun and verify idempotency**

Run:
```bash
APP_ENV=test SINCE=2026-01-01 BEFORE=2026-04-17 bundle exec rake update:ruby_rdoc 2>&1 | tail -3
```

Expected: `ruby_rdoc: stored=0, skipped=N` (all entries deduped by content_hash).

- [ ] **Step 7: Commit if incidental changes**

Run:
```bash
git status
# clean → proceed; changes → inspect and commit with "test: ..." message
```

### Task 3.7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add to source 値の規約 table**

In the `### source 値の規約` table, add a row:

```
| `ruby/ruby:rdoc/trunk/{ClassName}` | ruby/ruby trunk RDoc の日本語翻訳版（ruby-rdoc-collector）|
```

- [ ] **Step 2: Add to 依存する外部リポジトリ table**

In the `依存する外部リポジトリ（in-project gem）` table, add a row:

```
| ruby-rdoc-collector   | `../ruby-rdoc-collector`   | ruby/ruby の RDoc JSON を収集し Claude CLI で日本語翻訳 |
```

- [ ] **Step 3: Add a brief "キャッシュ共有" note**

Under the cache-related section (near `### キャッシュ方針`), append a paragraph:

```markdown
`ruby-rdoc-collector` は `~/.cache/trunk-changes-repos/ruby` を **read-only** で共有する（clone / fetch / reset は cruby-trunk-changes の `cache:prepare` が所有、rdoc-collector は git write 操作を一切しない）。`rake update:ruby_rdoc` は `cache:prepare` を prereq に宣言済みなので、単独実行でも最新 HEAD に対して動く。翻訳キャッシュは別階層 `~/.cache/ruby-rdoc-collector/` に SHA256 キーで保存。
```

- [ ] **Step 4: Commit**

Run:
```bash
git add CLAUDE.md
git commit -m "docs: document ruby-rdoc-collector source, repo, and cache sharing"
```

### Task 3.8: Open PR

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
- Adds `ruby_rdoc_collector` gem (separate repo) that extracts class-level RDoc from `ruby/ruby` trunk via `rdoc --format=json`, translates EN descriptions to JP via Claude CLI (sonnet) with SHA256 cache, and emits class-unit Markdown.
- Wires the collector into the existing `run_collector` helper with a new `update:ruby_rdoc` rake task (prereq: `cache:prepare`) and `scripts/update_all.rb` registration.
- Adds `ruby/ruby:rdoc/trunk/{ClassName}` source value and corresponding embedding prefix in `ruby-knowledge-store`.
- Shares `~/.cache/trunk-changes-repos/ruby` read-only with cruby-trunk-changes; clone is owned by `cache:prepare`, not by this collector.
- Coexistence with `rurema/doctree` is intentional: rurema = stable hand-translated, rdoc/trunk = latest API coverage (e.g. `Ruby::Box`). Downstream source disambiguation is out of scope (chiebukuro-mcp hints task).

## Test plan
- [x] gem unit tests (ruby-rdoc-collector): ~27 tests across 8 files, all pass with stub runner
- [x] PoC smoke with real Claude CLI on Ruby::Box / String / Integer
- [x] Cache hit verified on second run
- [x] `APP_ENV=test rake update:ruby_rdoc` end-to-end integration smoke
- [x] Re-run produces `stored=0, skipped=N` (content_hash idempotency)
- [x] `last_run.yml` updated with `RubyRdocCollector::Collector` key
- [ ] Production cost review before enabling in `scripts/update_all.rb` default schedule

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Report PR URL to user**

---

## Stage 4 (out of scope — deferred)

These are explicitly **not** in this plan:

- stdlib coverage (`ruby_rdoc_stdlib` source)
- Daily automation (rake daily integration)
- chiebukuro-mcp `hints_json` update for source_filter hinting
- Batch parallelization of Claude CLI calls
- Translation quality regression suite

Each becomes its own plan once Stage 3 is merged and observed in production.

---

## Commands Reference

```bash
# Stage 0: worktree
git worktree add ../ruby-knowledge-db-rdoc -b feature/ruby-rdoc-collector main

# Stage 1: probe
bundle exec ruby scripts/explore_rdoc_json.rb

# Stage 2: gem tests (in ../ruby-rdoc-collector/)
bundle exec rake test

# Stage 2: PoC smoke (costs $)
bundle exec ruby bin/poc_smoke.rb Ruby::Box String Integer

# Stage 3: integration smoke (prereq cache:prepare runs automatically)
APP_ENV=test SINCE=2026-01-01 BEFORE=2026-04-17 bundle exec rake update:ruby_rdoc

# Cleanup after merge
git worktree remove ../ruby-knowledge-db-rdoc
git worktree remove ../ruby-knowledge-store-rdoc
```

---

## Self-Review Notes

- **Spec coverage:** Q1 (cache in gem) → 2.3. Q2 (class granularity) → 2.8 `SOURCE_PREFIX`. Q3 (JP desc + EN signatures) → 2.4. Q4 (probe rdoc json first) → Stage 1 entirely + Task 2.7 explicit adjustment note. Q5 (PoC → cost → decide) → 2.9 CHECKPOINT. Q6 (coexist, hints separate) → Stage 4 deferred + README. Q7 (all classes) → 2.7 `filter: :builtin_only`. Q8 (trunk, not tagged) → 3.2 `repo_path`. Q9 (since/before ignored) → 2.8 test `test_since_and_before_are_ignored`.
- **rurema/cruby-trunk-changes relationship:** documented in Architecture section, README (Task 2.1 Step 6), sources.yml comment (3.2), Rakefile prereq (3.3), CLAUDE.md (3.7), RepoManager design note (2.6).
- **Placeholders:** RdocExtractor field names (Task 2.7) are explicitly marked as *needing Stage 1 findings*, not a hidden TBD.
- **Type consistency:** `ClassEntity(name, description, methods, constants, superclass)` and `MethodEntry(name, call_seq, description)` used consistently across 2.2, 2.4, 2.7, 2.8. `runner.call(prompt)` signature identical in Translator default runner and test stubs. `SOURCE_PREFIX = 'ruby/ruby:rdoc/trunk'` identical in Collector and Store case. RepoManager uses `ensure_ready` (read-only) — NOT `ensure_repo` (implied git write).
- **Worktree safety:** ruby-knowledge-db and ruby-knowledge-store both use isolated worktrees. New gem is a fresh repo (no worktree needed).
