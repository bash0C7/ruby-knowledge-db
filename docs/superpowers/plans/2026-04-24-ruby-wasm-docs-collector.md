# ruby-wasm-docs-collector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ruby/ruby.wasm` RBS / README / docs / js-gem README content to `ruby-knowledge-db` via a new in-project gem `ruby-wasm-docs-collector`, modeled on `picoruby-docs-collector`.

**Architecture:** New gem at `~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector/` with three classes (Collector / FileWalker / Formatter). `ruby-knowledge-db` consumes it via a path gem, declared in `config/sources.yml` and invoked from `Rakefile`'s `namespace :update`. Local clone at `~/dev/src/github.com/ruby/ruby.wasm` is the data source (user-managed `git pull`).

**Tech Stack:** Ruby (CRuby, `bundle exec`), test-unit (xUnit style), t-wada TDD (RED/GREEN/REFACTOR independent commits).

**Spec:** `docs/superpowers/specs/2026-04-24-ruby-wasm-docs-collector-design.md`

---

## File Structure

### Files to create (gem `ruby-wasm-docs-collector`)

- `ruby_wasm_docs_collector.gemspec` — gem metadata
- `Gemfile` — rake + test-unit
- `Rakefile` — rake test task
- `.gitignore` — vendor/bundle, .bundle, *.gem
- `lib/ruby_wasm_docs_collector.rb` — root entry that requires collector
- `lib/ruby_wasm_docs_collector/collector.rb` — `Collector` class
- `lib/ruby_wasm_docs_collector/file_walker.rb` — `FileWalker` class
- `lib/ruby_wasm_docs_collector/formatter.rb` — `Formatter` class
- `test/test_helper.rb` — test-unit require + FIXTURE_REPO constant
- `test/test_file_walker.rb` — FileWalker specs
- `test/test_formatter.rb` — Formatter specs
- `test/test_collector.rb` — Collector integration specs
- `test/fixtures/fake-ruby-wasm/README.md`
- `test/fixtures/fake-ruby-wasm/sig/open_uri.rbs`
- `test/fixtures/fake-ruby-wasm/sig/ruby_wasm/build.rbs`
- `test/fixtures/fake-ruby-wasm/docs/api.md`
- `test/fixtures/fake-ruby-wasm/packages/gems/js/README.md`
- `README.md` — minimal usage description

### Files to modify (`ruby-knowledge-db`)

- `Gemfile` — add path gem line
- `config/sources.yml` — add `ruby_wasm_docs` section
- `Rakefile` — add `require 'ruby_wasm_docs_collector'` + `task :ruby_wasm_docs`
- `CLAUDE.md` — add source table rows + external repo row
- `.claude/agents/ruby-knowledge-db-run.md` — add `RubyWasmDocsCollector::Collector` to bookmark array + SINCE default table
- `.claude/agents/ruby-knowledge-db-inspect.md` — add `RubyWasmDocsCollector::Collector` to bookmark array

---

## Phase 1: ruby-wasm-docs-collector gem

### Task 1: Scaffold gem directory structure

**Files:**
- Create: `~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector/*` (entire skeleton)

- [ ] **Step 1: Create the gem directory via ghq**

```bash
mkdir -p ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
git init
```

Expected: `Initialized empty Git repository in ...`

- [ ] **Step 2: Create `.gitignore`**

Write `~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector/.gitignore`:

```
vendor/bundle/
.bundle/
*.gem
Gemfile.lock
```

- [ ] **Step 3: Create `ruby_wasm_docs_collector.gemspec`**

Write `~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector/ruby_wasm_docs_collector.gemspec`:

```ruby
Gem::Specification.new do |spec|
  spec.name          = 'ruby_wasm_docs_collector'
  spec.version       = '0.1.0'
  spec.summary       = 'ruby.wasm docs (RBS + README + docs/ + js-gem) collector for ruby knowledge DB'
  spec.authors       = ['bash0C7']
  spec.files         = Dir['lib/**/*.rb']
  spec.require_paths = ['lib']
end
```

- [ ] **Step 4: Create `Gemfile`**

Write `~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector/Gemfile`:

```ruby
# frozen_string_literal: true
source 'https://rubygems.org'
gemspec
gem 'rake'
gem 'test-unit'
```

- [ ] **Step 5: Create `Rakefile`**

Write `~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector/Rakefile`:

```ruby
require 'rake/testtask'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib' << 'test'
  t.pattern = 'test/test_*.rb'
end
task default: :test
```

- [ ] **Step 6: Create `lib/ruby_wasm_docs_collector.rb`**

Write `~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector/lib/ruby_wasm_docs_collector.rb`:

```ruby
require_relative 'ruby_wasm_docs_collector/collector'

module RubyWasmDocsCollector
end
```

- [ ] **Step 7: Create placeholder class files (empty modules, so requires resolve)**

Write `~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector/lib/ruby_wasm_docs_collector/file_walker.rb`:

```ruby
module RubyWasmDocsCollector
  class FileWalker
  end
end
```

Write `~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector/lib/ruby_wasm_docs_collector/formatter.rb`:

```ruby
module RubyWasmDocsCollector
  class Formatter
  end
end
```

Write `~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector/lib/ruby_wasm_docs_collector/collector.rb`:

```ruby
require_relative 'file_walker'
require_relative 'formatter'

module RubyWasmDocsCollector
  class Collector
  end
end
```

- [ ] **Step 8: Install dependencies**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
bundle config set --local path 'vendor/bundle'
bundle install
```

Expected: `Bundle complete! N Gemfile dependencies, ...`

- [ ] **Step 9: Verify scaffolding runs (no tests yet, but rake test should succeed with no tests)**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
bundle exec rake test
```

Expected: Runs with 0 tests reported, exits 0.

- [ ] **Step 10: Commit scaffold**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
git add .
git commit -m "chore: scaffold gem structure"
```

---

### Task 2: Set up test fixture (fake-ruby-wasm)

**Files:**
- Create: `test/fixtures/fake-ruby-wasm/README.md`
- Create: `test/fixtures/fake-ruby-wasm/sig/open_uri.rbs`
- Create: `test/fixtures/fake-ruby-wasm/sig/ruby_wasm/build.rbs`
- Create: `test/fixtures/fake-ruby-wasm/docs/api.md`
- Create: `test/fixtures/fake-ruby-wasm/packages/gems/js/README.md`
- Create: `test/test_helper.rb`

- [ ] **Step 1: Create fixture directories**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
mkdir -p test/fixtures/fake-ruby-wasm/sig/ruby_wasm
mkdir -p test/fixtures/fake-ruby-wasm/docs
mkdir -p test/fixtures/fake-ruby-wasm/packages/gems/js
```

- [ ] **Step 2: Write root README fixture**

Write `test/fixtures/fake-ruby-wasm/README.md`:

```markdown
# fake ruby.wasm

This is a fixture file for testing RubyWasmDocsCollector.
```

- [ ] **Step 3: Write RBS fixtures**

Write `test/fixtures/fake-ruby-wasm/sig/open_uri.rbs`:

```rbs
module OpenURI
end
```

Write `test/fixtures/fake-ruby-wasm/sig/ruby_wasm/build.rbs`:

```rbs
module RubyWasm
  class Build
    def initialize: () -> void
  end
end
```

- [ ] **Step 4: Write docs fixture**

Write `test/fixtures/fake-ruby-wasm/docs/api.md`:

```markdown
# fake API

Fixture content for docs/api.md.
```

- [ ] **Step 5: Write js-gem README fixture**

Write `test/fixtures/fake-ruby-wasm/packages/gems/js/README.md`:

```markdown
# fake js gem

Fixture content for packages/gems/js/README.md.
```

- [ ] **Step 6: Write test_helper.rb**

Write `test/test_helper.rb`:

```ruby
# frozen_string_literal: true
require 'test/unit'

FIXTURE_REPO = File.expand_path('fixtures/fake-ruby-wasm', __dir__)
```

- [ ] **Step 7: Commit fixture**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
git add .
git commit -m "test: add fixture for fake ruby.wasm repo"
```

---

### Task 3: FileWalker RED — failing specs

**Files:**
- Create: `test/test_file_walker.rb`

- [ ] **Step 1: Write the failing FileWalker test**

Write `test/test_file_walker.rb`:

```ruby
# frozen_string_literal: true
require_relative 'test_helper'
require 'tmpdir'
require 'ruby_wasm_docs_collector'

class TestFileWalker < Test::Unit::TestCase
  def setup
    @walker = RubyWasmDocsCollector::FileWalker.new(FIXTURE_REPO)
  end

  def test_each_entry_yields_rbs_files_with_sig_prefixed_suffix
    rbs = @walker.each_entry.to_a.select { |e| e[:kind] == :rbs }
    suffixes = rbs.map { |e| e[:source_suffix] }.sort
    assert_equal ['sig/open_uri', 'sig/ruby_wasm/build'], suffixes
  end

  def test_each_rbs_entry_has_absolute_path_and_relative_rel_path
    rbs = @walker.each_entry.find { |e| e[:source_suffix] == 'sig/open_uri' }
    assert_equal File.join(FIXTURE_REPO, 'sig/open_uri.rbs'), rbs[:path]
    assert_equal 'sig/open_uri.rbs', rbs[:rel_path]
  end

  def test_each_entry_yields_root_readme_with_readme_suffix
    entry = @walker.each_entry.find { |e| e[:source_suffix] == 'readme' }
    assert_equal :readme, entry[:kind]
    assert_equal File.join(FIXTURE_REPO, 'README.md'), entry[:path]
    assert_equal 'README.md', entry[:rel_path]
  end

  def test_each_entry_yields_docs_md_without_docs_prefix
    entry = @walker.each_entry.find { |e| e[:source_suffix] == 'api' }
    assert_equal :doc, entry[:kind]
    assert_equal File.join(FIXTURE_REPO, 'docs/api.md'), entry[:path]
  end

  def test_each_entry_yields_js_gem_readme
    entry = @walker.each_entry.find { |e| e[:source_suffix] == 'js-gem' }
    assert_equal :readme, entry[:kind]
    assert_equal File.join(FIXTURE_REPO, 'packages/gems/js/README.md'), entry[:path]
  end

  def test_returns_enumerator_without_block
    result = @walker.each_entry
    assert_kind_of Enumerator, result
  end

  def test_missing_sig_directory_logs_warning_and_continues
    Dir.mktmpdir do |tmp|
      File.write(File.join(tmp, 'README.md'), 'no sig dir')
      walker = RubyWasmDocsCollector::FileWalker.new(tmp)
      entries = nil
      _out, err = capture_subprocess_or_warnings { entries = walker.each_entry.to_a }
      assert_empty entries.select { |e| e[:kind] == :rbs }
      assert_not_nil entries.find { |e| e[:source_suffix] == 'readme' }
      assert_match(/sig.*not found/, err)
    end
  end

  private

  def capture_subprocess_or_warnings
    require 'stringio'
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
    [nil, $stderr.string]
  ensure
    $stderr = original_stderr
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
bundle exec rake test TESTOPTS="-v"
```

Expected: Errors like `NoMethodError: undefined method 'new' for RubyWasmDocsCollector::FileWalker:Class` or similar. At minimum, failing/error count >= 1.

- [ ] **Step 3: Commit RED**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
git add test/test_file_walker.rb
git commit -m "test: add failing specs for FileWalker"
```

---

### Task 4: FileWalker GREEN — minimal implementation

**Files:**
- Modify: `lib/ruby_wasm_docs_collector/file_walker.rb`

- [ ] **Step 1: Implement FileWalker**

Overwrite `lib/ruby_wasm_docs_collector/file_walker.rb`:

```ruby
module RubyWasmDocsCollector
  class FileWalker
    def initialize(repo_path)
      @repo_path = repo_path
    end

    # @yieldparam entry [Hash{kind: Symbol, path: String, rel_path: String, source_suffix: String}]
    # @return [Enumerator] if no block given
    def each_entry(&block)
      return enum_for(:each_entry) unless block_given?
      walk_rbs(&block)
      walk_root_readme(&block)
      walk_docs(&block)
      walk_js_gem(&block)
    end

    private

    def walk_rbs
      sig_dir = File.join(@repo_path, 'sig')
      unless Dir.exist?(sig_dir)
        warn "RubyWasmDocsCollector: sig/ not found in #{@repo_path}"
        return
      end
      Dir.glob(File.join(sig_dir, '**', '*.rbs')).sort.each do |path|
        rel    = path.sub(/\A#{Regexp.escape(@repo_path)}\//, '')
        suffix = rel.sub(/\.rbs\z/, '')
        yield(kind: :rbs, path: path, rel_path: rel, source_suffix: suffix)
      end
    end

    def walk_root_readme
      path = File.join(@repo_path, 'README.md')
      unless File.exist?(path)
        warn "RubyWasmDocsCollector: root README.md not found in #{@repo_path}"
        return
      end
      yield(kind: :readme, path: path, rel_path: 'README.md', source_suffix: 'readme')
    end

    def walk_docs
      docs_dir = File.join(@repo_path, 'docs')
      unless Dir.exist?(docs_dir)
        warn "RubyWasmDocsCollector: docs/ not found in #{@repo_path}"
        return
      end
      Dir.glob(File.join(docs_dir, '*.md')).sort.each do |path|
        name = File.basename(path, '.md')
        yield(kind: :doc, path: path, rel_path: "docs/#{File.basename(path)}", source_suffix: name)
      end
    end

    def walk_js_gem
      path = File.join(@repo_path, 'packages', 'gems', 'js', 'README.md')
      unless File.exist?(path)
        warn "RubyWasmDocsCollector: js gem README not found at #{path}"
        return
      end
      yield(kind: :readme, path: path, rel_path: 'packages/gems/js/README.md', source_suffix: 'js-gem')
    end
  end
end
```

- [ ] **Step 2: Run tests to verify green**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
bundle exec rake test TESTOPTS="-v"
```

Expected: All `TestFileWalker` tests pass (7 passes, 0 failures, 0 errors).

- [ ] **Step 3: Commit GREEN**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
git add lib/ruby_wasm_docs_collector/file_walker.rb
git commit -m "feat: implement FileWalker to discover rbs/readme/docs/js-gem entries"
```

---

### Task 5: Formatter RED — failing specs

**Files:**
- Create: `test/test_formatter.rb`

- [ ] **Step 1: Write the failing Formatter test**

Write `test/test_formatter.rb`:

```ruby
# frozen_string_literal: true
require_relative 'test_helper'
require 'ruby_wasm_docs_collector'

class TestFormatter < Test::Unit::TestCase
  def setup
    @formatter = RubyWasmDocsCollector::Formatter.new
  end

  def test_rbs_gets_header_with_relative_path
    entry = {
      kind:     :rbs,
      path:     File.join(FIXTURE_REPO, 'sig/ruby_wasm/build.rbs'),
      rel_path: 'sig/ruby_wasm/build.rbs',
    }
    output = @formatter.format(entry)
    assert_match(/\A# RBS: sig\/ruby_wasm\/build\.rbs\n\n/, output)
    assert_match(/class Build/, output)
  end

  def test_md_passes_through_unchanged
    entry = {
      kind:     :doc,
      path:     File.join(FIXTURE_REPO, 'docs/api.md'),
      rel_path: 'docs/api.md',
    }
    output = @formatter.format(entry)
    assert_equal File.read(entry[:path], encoding: 'utf-8'), output
  end

  def test_readme_passes_through_unchanged
    entry = {
      kind:     :readme,
      path:     File.join(FIXTURE_REPO, 'README.md'),
      rel_path: 'README.md',
    }
    output = @formatter.format(entry)
    assert_equal File.read(entry[:path], encoding: 'utf-8'), output
  end

  def test_read_failure_returns_nil_and_warns
    entry = {
      kind:     :rbs,
      path:     '/nonexistent/file.rbs',
      rel_path: 'nonexistent/file.rbs',
    }
    original_stderr = $stderr
    require 'stringio'
    $stderr = StringIO.new
    result = @formatter.format(entry)
    assert_nil result
    assert_match(/read failed/, $stderr.string)
  ensure
    $stderr = original_stderr
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
bundle exec rake test TESTOPTS="-v --name=/TestFormatter/"
```

Expected: 4 errors/failures for `TestFormatter` (e.g., `NoMethodError: undefined method 'format'`).

- [ ] **Step 3: Commit RED**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
git add test/test_formatter.rb
git commit -m "test: add failing specs for Formatter"
```

---

### Task 6: Formatter GREEN — minimal implementation

**Files:**
- Modify: `lib/ruby_wasm_docs_collector/formatter.rb`

- [ ] **Step 1: Implement Formatter**

Overwrite `lib/ruby_wasm_docs_collector/formatter.rb`:

```ruby
module RubyWasmDocsCollector
  class Formatter
    # @param entry [Hash{kind: Symbol, path: String, rel_path: String}]
    # @return [String, nil] content or nil on read failure
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
end
```

- [ ] **Step 2: Run tests to verify green**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
bundle exec rake test TESTOPTS="-v"
```

Expected: `TestFormatter` all pass; `TestFileWalker` still pass. Total 11 passes, 0 failures, 0 errors.

- [ ] **Step 3: Commit GREEN**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
git add lib/ruby_wasm_docs_collector/formatter.rb
git commit -m "feat: implement Formatter with RBS header prefix"
```

---

### Task 7: Collector RED — failing specs

**Files:**
- Create: `test/test_collector.rb`

- [ ] **Step 1: Write the failing Collector test**

Write `test/test_collector.rb`:

```ruby
# frozen_string_literal: true
require_relative 'test_helper'
require 'ruby_wasm_docs_collector'

class TestCollector < Test::Unit::TestCase
  def setup
    @config    = { 'repo_path' => FIXTURE_REPO }
    @collector = RubyWasmDocsCollector::Collector.new(@config)
  end

  def test_collect_returns_records_with_expected_source_values
    records = @collector.collect
    sources = records.map { |r| r[:source] }.sort
    expected = [
      'ruby/ruby.wasm:docs/api',
      'ruby/ruby.wasm:docs/js-gem',
      'ruby/ruby.wasm:docs/readme',
      'ruby/ruby.wasm:docs/sig/open_uri',
      'ruby/ruby.wasm:docs/sig/ruby_wasm/build',
    ]
    assert_equal expected, sources
  end

  def test_collect_returns_content_strings
    records = @collector.collect
    records.each do |r|
      assert_kind_of String, r[:content]
      assert_not_empty r[:content]
    end
  end

  def test_rbs_record_starts_with_rbs_header
    records = @collector.collect
    rbs = records.find { |r| r[:source] == 'ruby/ruby.wasm:docs/sig/ruby_wasm/build' }
    assert_match(/\A# RBS: sig\/ruby_wasm\/build\.rbs\n\n/, rbs[:content])
  end

  def test_collect_ignores_since_and_before_arguments
    records_a = @collector.collect(since: '2026-01-01', before: '2026-04-01')
    records_b = @collector.collect
    assert_equal records_a.map { |r| r[:source] }.sort,
                 records_b.map { |r| r[:source] }.sort
  end

  def test_raises_system_exit_when_repo_path_missing
    assert_raise(SystemExit) do
      RubyWasmDocsCollector::Collector.new({ 'repo_path' => '/nonexistent/path/here' })
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
bundle exec rake test TESTOPTS="-v --name=/TestCollector/"
```

Expected: 5 errors/failures for `TestCollector`.

- [ ] **Step 3: Commit RED**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
git add test/test_collector.rb
git commit -m "test: add failing specs for Collector"
```

---

### Task 8: Collector GREEN — minimal implementation

**Files:**
- Modify: `lib/ruby_wasm_docs_collector/collector.rb`

- [ ] **Step 1: Implement Collector**

Overwrite `lib/ruby_wasm_docs_collector/collector.rb`:

```ruby
require_relative 'file_walker'
require_relative 'formatter'

module RubyWasmDocsCollector
  class Collector
    SOURCE_PREFIX = 'ruby/ruby.wasm:docs'

    def initialize(config, file_walker: nil, formatter: nil)
      @repo_path = File.expand_path(config['repo_path'])
      abort "ruby.wasm repo not found: #{@repo_path}" unless Dir.exist?(@repo_path)
      @file_walker = file_walker || FileWalker.new(@repo_path)
      @formatter   = formatter   || Formatter.new
    end

    # since / before are ignored (content_hash handles idempotency at Store layer).
    # @return [Array<{content: String, source: String}>]
    def collect(since: nil, before: nil)
      @file_walker.each_entry.filter_map do |entry|
        content = @formatter.format(entry)
        next nil if content.nil?
        { content: content, source: "#{SOURCE_PREFIX}/#{entry[:source_suffix]}" }
      end
    end
  end
end
```

- [ ] **Step 2: Run all tests**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
bundle exec rake test TESTOPTS="-v"
```

Expected: 16 passes total (7 FileWalker + 4 Formatter + 5 Collector), 0 failures, 0 errors.

- [ ] **Step 3: Commit GREEN**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
git add lib/ruby_wasm_docs_collector/collector.rb
git commit -m "feat: implement Collector entry point"
```

---

### Task 9: Gem README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

Write `~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector/README.md`:

```markdown
# ruby_wasm_docs_collector

`ruby/ruby.wasm` の RBS / README / docs / js-gem README を収集して、`ruby-knowledge-db` の `memories` テーブルに投入するための in-project collector gem。

## 収集対象

- `sig/**/*.rbs` — RBS 型定義
- `README.md` — ルート README
- `docs/*.md` — docs ディレクトリ配下の guide 群
- `packages/gems/js/README.md` — ruby.wasm の js gem README

npm パッケージ README 群 (`packages/npm-packages/*/README.md`) や `ext/`, `CONTRIBUTING.md` 等は対象外。

## 前提

- `~/dev/src/github.com/ruby/ruby.wasm` をローカルに clone 済みであること (`ghq get ruby/ruby.wasm`)
- リポジトリの最新化はユーザーが手動で `git pull` する運用 (rurema / picoruby-docs と同じ方針)

## 使い方

`ruby-knowledge-db` の `Rakefile` から呼ばれる。直接 CLI からは実行しない。

```ruby
collector = RubyWasmDocsCollector::Collector.new('repo_path' => '~/dev/src/github.com/ruby/ruby.wasm')
records = collector.collect   # [{content, source}, ...]
```

## source 値の命名

| ファイル種別 | source 値 |
|---|---|
| `sig/**/*.rbs` | `ruby/ruby.wasm:docs/sig/<rel without .rbs>` |
| ルート `README.md` | `ruby/ruby.wasm:docs/readme` |
| `docs/<name>.md` | `ruby/ruby.wasm:docs/<name>` |
| `packages/gems/js/README.md` | `ruby/ruby.wasm:docs/js-gem` |

## テスト

```bash
bundle install
bundle exec rake test
```
```

- [ ] **Step 2: Commit README**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-wasm-docs-collector
git add README.md
git commit -m "docs: add README"
```

---

## Phase 2: ruby-knowledge-db integration

### Task 10: Add path gem to `ruby-knowledge-db` Gemfile

**Files:**
- Modify: `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/Gemfile`

- [ ] **Step 1: Read the current Gemfile to find the right insertion point**

```bash
cat /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/Gemfile
```

Locate the line `gem 'picoruby_docs_collector', path: '../picoruby-docs-collector'`.

- [ ] **Step 2: Add the new path gem line directly below the picoruby line**

Edit `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/Gemfile`:

Insert after the existing `gem 'picoruby_docs_collector', path: '../picoruby-docs-collector'` line:

```ruby
gem 'ruby_wasm_docs_collector', path: '../ruby-wasm-docs-collector'
```

- [ ] **Step 3: Run bundle install**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
bundle install
```

Expected: `Bundle complete! ...` and `Gemfile.lock` updated to include `ruby_wasm_docs_collector (0.1.0)` from source path `../ruby-wasm-docs-collector`.

- [ ] **Step 4: Verify require works from ruby-knowledge-db**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
bundle exec ruby -e "require 'ruby_wasm_docs_collector'; puts RubyWasmDocsCollector::Collector::SOURCE_PREFIX"
```

Expected: `ruby/ruby.wasm:docs`

(Do not commit yet — batch all Phase 2 changes in Task 15.)

---

### Task 11: Add `ruby_wasm_docs` to `config/sources.yml`

**Files:**
- Modify: `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/config/sources.yml`

- [ ] **Step 1: Append `ruby_wasm_docs` section**

Edit `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/config/sources.yml`:

Append at the end of the file (below the `ruby_rdoc:` block):

```yaml

  ruby_wasm_docs:
    repo_path: ~/dev/src/github.com/ruby/ruby.wasm
```

- [ ] **Step 2: Verify YAML parses**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
bundle exec ruby -ryaml -e 'puts YAML.load_file("config/sources.yml").dig("sources", "ruby_wasm_docs", "repo_path")'
```

Expected: `~/dev/src/github.com/ruby/ruby.wasm`

(Do not commit yet.)

---

### Task 12: Add `update:ruby_wasm_docs` task to Rakefile

**Files:**
- Modify: `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/Rakefile`

- [ ] **Step 1: Add require to `require_update_deps`**

Edit `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/Rakefile`:

Find the block:

```ruby
def require_update_deps
  require_store_deps
  require 'rurema_collector'
  require 'picoruby_docs_collector'
  require 'ruby_rdoc_collector'
end
```

Replace with:

```ruby
def require_update_deps
  require_store_deps
  require 'rurema_collector'
  require 'picoruby_docs_collector'
  require 'ruby_rdoc_collector'
  require 'ruby_wasm_docs_collector'
end
```

- [ ] **Step 2: Add task to `namespace :update`**

In the same file, find the `namespace :update do` block. After the existing `task :picoruby_docs do ... end` block, add:

```ruby
  desc "Update ruby.wasm docs (SINCE/BEFORE は無視、content_hash で冪等)"
  task :ruby_wasm_docs do
    run_collector(:ruby_wasm_docs, 'RubyWasmDocsCollector::Collector', 'ruby_wasm_docs')
  end
```

- [ ] **Step 3: Verify rake -T shows the new task**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
bundle exec rake -T | grep ruby_wasm_docs
```

Expected: `rake update:ruby_wasm_docs   # Update ruby.wasm docs (SINCE/BEFORE は無視、content_hash で冪等)`

(Do not commit yet.)

---

### Task 13: Smoke run + verify

- [ ] **Step 1: Ensure ruby.wasm repo is cloned locally**

```bash
ls ~/dev/src/github.com/ruby/ruby.wasm/sig 2>/dev/null || ghq get ruby/ruby.wasm
```

Expected: `sig/` directory listing, or a fresh clone completes.

- [ ] **Step 2: Run update:ruby_wasm_docs in development**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
APP_ENV=development bundle exec rake update:ruby_wasm_docs
```

Expected output (approximate): `ruby_wasm_docs: stored=12, skipped=0` (count may vary slightly if ruby.wasm upstream changed `sig/` or `docs/` file count — that is acceptable, the important thing is it's non-zero and no errors).

- [ ] **Step 3: Run again to verify idempotency**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
APP_ENV=development bundle exec rake update:ruby_wasm_docs
```

Expected: `ruby_wasm_docs: stored=0, skipped=12` (all records already present, content_hash match).

- [ ] **Step 4: Verify source distribution in DB**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
APP_ENV=development bundle exec rake db:stats | grep 'ruby.wasm'
```

Expected: Multiple lines showing `ruby/ruby.wasm:docs/*` sources in the top distribution, or at least verify the total matches with a direct count:

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
APP_ENV=development bundle exec ruby -e '
  require "sqlite3"; require "sqlite_vec"
  require_relative "lib/ruby_knowledge_db/config"
  cfg = RubyKnowledgeDb::Config.load
  db = SQLite3::Database.new(File.expand_path(cfg["db_path"]), readonly: true)
  db.enable_load_extension(true); SqliteVec.load(db); db.enable_load_extension(false)
  count = db.get_first_value("SELECT count(*) FROM memories WHERE source LIKE ?", "ruby/ruby.wasm:docs/%")
  puts "ruby.wasm docs rows: #{count}"
'
```

Expected: a positive integer matching the stored count from Step 2.

---

### Task 14: Update CLAUDE.md

**Files:**
- Modify: `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/CLAUDE.md`

- [ ] **Step 1: Add source rows to the source 値の規約 table**

Edit `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/CLAUDE.md`:

Find the table under `### source 値の規約`. After the row:

```
| `ruby/ruby:rdoc/trunk/{ClassName}` | ruby/ruby trunk RDoc の英語原文（ruby-rdoc-collector）。JP query の英訳と和訳表示は chiebukuro-mcp 経由のホスト LLM agent が担当 |
```

Append these four rows:

```
| `ruby/ruby.wasm:docs/sig/{path}` | ruby/ruby.wasm の RBS 型定義 (sig/ 配下) |
| `ruby/ruby.wasm:docs/readme` | ruby/ruby.wasm ルート README |
| `ruby/ruby.wasm:docs/{name}` | ruby/ruby.wasm の docs/ 配下ガイド (api / faq / cheat_sheet) |
| `ruby/ruby.wasm:docs/js-gem` | ruby/ruby.wasm の js gem (`packages/gems/js`) README |
```

- [ ] **Step 2: Add row to the 依存する外部リポジトリ table**

Find the table under `## 依存する外部リポジトリ（in-project gem）`. After the row:

```
| ruby-rdoc-collector   | `../ruby-rdoc-collector`   | ruby/ruby の RDoc HTML（cache.ruby-lang.org tarball）を取得し英語原文のまま格納。JP query 英訳と和訳表示は chiebukuro-mcp 経由のホスト LLM agent 担当 |
```

Append:

```
| ruby-wasm-docs-collector | `../ruby-wasm-docs-collector` | ruby/ruby.wasm の sig (RBS) + ルート README + docs/ + js-gem README を収集 |
```

(Do not commit yet.)

---

### Task 15: Update .claude/agents/ruby-knowledge-db-run.md

**Files:**
- Modify: `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/.claude/agents/ruby-knowledge-db-run.md`

- [ ] **Step 1: Add SINCE default entry for update:ruby_wasm_docs**

Edit `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/.claude/agents/ruby-knowledge-db-run.md`:

Find the block listing SINCE defaults:

```
  - `update:picoruby_docs`: key `PicorubyDocsCollector::Collector`, or yesterday if absent.
  - `update:ruby_rdoc`: key `RubyRdocCollector::Collector`, or `2026-04-16` (initial release) if absent. Note: RDoc translation is date-independent (always latest tarball); `SINCE`/`BEFORE` only drive the bookmark.
```

Insert a new bullet before the `update:ruby_rdoc` line:

```
  - `update:picoruby_docs`: key `PicorubyDocsCollector::Collector`, or yesterday if absent.
  - `update:ruby_wasm_docs`: key `RubyWasmDocsCollector::Collector`, or yesterday if absent.
  - `update:ruby_rdoc`: key `RubyRdocCollector::Collector`, or `2026-04-16` (initial release) if absent. Note: RDoc translation is date-independent (always latest tarball); `SINCE`/`BEFORE` only drive the bookmark.
```

- [ ] **Step 2: Add `RubyWasmDocsCollector::Collector` to the bookmark readback array**

Find the line (inside the collector bookmark readback Ruby one-liner):

```ruby
    %w[RuremaCollector::Collector PicorubyDocsCollector::Collector RubyRdocCollector::Collector].each do |k|
```

Replace with:

```ruby
    %w[RuremaCollector::Collector PicorubyDocsCollector::Collector RubyRdocCollector::Collector RubyWasmDocsCollector::Collector].each do |k|
```

(Do not commit yet.)

---

### Task 16: Update .claude/agents/ruby-knowledge-db-inspect.md

**Files:**
- Modify: `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/.claude/agents/ruby-knowledge-db-inspect.md`

- [ ] **Step 1: Add `RubyWasmDocsCollector::Collector` to the bookmark readback array**

Edit `/Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db/.claude/agents/ruby-knowledge-db-inspect.md`:

Find:

```ruby
    %w[RuremaCollector::Collector PicorubyDocsCollector::Collector RubyRdocCollector::Collector].each do |k|
```

Replace with:

```ruby
    %w[RuremaCollector::Collector PicorubyDocsCollector::Collector RubyRdocCollector::Collector RubyWasmDocsCollector::Collector].each do |k|
```

(Do not commit yet.)

---

### Task 17: Verify tests still pass, then commit Phase 2

- [ ] **Step 1: Run ruby-knowledge-db test suite**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
bundle exec rake test
```

Expected: All tests pass. If there is any test that asserts the set of valid sources or update tasks, it should still pass (new task is additive).

- [ ] **Step 2: Stage all Phase 2 changes**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
git add Gemfile Gemfile.lock config/sources.yml Rakefile CLAUDE.md .claude/agents/ruby-knowledge-db-run.md .claude/agents/ruby-knowledge-db-inspect.md
```

- [ ] **Step 3: Verify staged diff**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
git diff --cached --stat
```

Expected: 7 files changed; no unrelated files in the list.

- [ ] **Step 4: Commit**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
git commit -m "$(cat <<'EOF'
feat: add ruby-wasm-docs-collector integration

- Gemfile: add path gem ruby_wasm_docs_collector
- config/sources.yml: ruby_wasm_docs entry with repo_path
- Rakefile: require + namespace :update task :ruby_wasm_docs
- CLAUDE.md: source value rows + external repo row
- .claude/agents: RubyWasmDocsCollector::Collector added to
  bookmark readback arrays (inspect + run) and SINCE default
  table (run)

Default rake pipeline auto-discovers update:ruby_wasm_docs via
dynamic update:* enumeration; no default-task edits required.

EOF
)"
```

Expected: commit created, `git log -1` shows it.

---

### Task 18: Optional production full run (user-initiated)

- [ ] **Step 1: Prompt user before running**

Before running production, summarize to the user:

```
Phase 2 integration committed. Next step (optional) is a production full
run that will: (a) run the trunk-changes pipeline with SINCE=yesterday
BEFORE=today, (b) run every update:* including update:ruby_wasm_docs,
(c) copy the DB to the iCloud chiebukuro-mcp reference location.

Run it? (y/n)
```

- [ ] **Step 2: If approved, run production**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
APP_ENV=production bundle exec rake
```

Expected: full pipeline completes. Per the project's non-determinism guard, a pollution scan runs afterwards; review its output before assuming success.

- [ ] **Step 3: Verify the new rows landed in production DB**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
APP_ENV=production bundle exec ruby -e '
  require "sqlite3"; require "sqlite_vec"
  require_relative "lib/ruby_knowledge_db/config"
  cfg = RubyKnowledgeDb::Config.load
  db = SQLite3::Database.new(File.expand_path(cfg["db_path"]), readonly: true)
  db.enable_load_extension(true); SqliteVec.load(db); db.enable_load_extension(false)
  rows = db.execute("SELECT source, count(*) FROM memories WHERE source LIKE ? GROUP BY source ORDER BY source", "ruby/ruby.wasm:docs/%")
  rows.each { |r| puts "  #{r[1].to_s.rjust(4)}  #{r[0]}" }
'
```

Expected: every `ruby/ruby.wasm:docs/*` source value with count=1 per row.

---

## Summary of commits produced

Gem repo `ruby-wasm-docs-collector` (10 commits):

1. `chore: scaffold gem structure`
2. `test: add fixture for fake ruby.wasm repo`
3. `test: add failing specs for FileWalker`
4. `feat: implement FileWalker to discover rbs/readme/docs/js-gem entries`
5. `test: add failing specs for Formatter`
6. `feat: implement Formatter with RBS header prefix`
7. `test: add failing specs for Collector`
8. `feat: implement Collector entry point`
9. `docs: add README`

Repo `ruby-knowledge-db` (1 commit):

10. `feat: add ruby-wasm-docs-collector integration`

Total commits across both repos: 10.
