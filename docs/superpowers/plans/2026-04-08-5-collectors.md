# 5 Collectors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 5つの Collector gem の lib/ を実装し、既存テストを全て通す。

**Architecture:** trunk-changes 系 3 gem は trunk-changes-diary に追加する `TrunkChangesCollector` ライブラリクラスに処理を委譲。picoruby-docs-collector と rurema-collector は独立実装。テストは既存のスタブを利用。

**Tech Stack:** Ruby 4.0.1, test-unit, trunk_changes_diary gem (GitOps / ContentGenerator), bitclust-core

---

## ファイルマップ

| 操作 | パス |
|------|------|
| Modify | `../trunk-changes-diary/trunk_changes.rb` — 末尾に `TrunkChangesCollector` 追加 |
| Create | `../trunk-changes-diary/test/test_trunk_changes_collector.rb` |
| Create | `../picoruby-trunk-changes-generator/lib/picoruby_trunk_changes_generator.rb` |
| Create | `../picoruby-trunk-changes-generator/lib/picoruby_trunk_changes_generator/collector.rb` |
| Create | `../picoruby-docs-collector/lib/picoruby_docs_collector.rb` |
| Create | `../picoruby-docs-collector/lib/picoruby_docs_collector/rbs_parser.rb` |
| Create | `../picoruby-docs-collector/lib/picoruby_docs_collector/readme_parser.rb` |
| Create | `../picoruby-docs-collector/lib/picoruby_docs_collector/gem_doc_collector.rb` |
| Create | `../picoruby-docs-collector/lib/picoruby_docs_collector/collector.rb` |
| Create | `../rurema-collector/lib/rurema_collector.rb` |
| Create | `../rurema-collector/lib/rurema_collector/doctree_manager.rb` |
| Create | `../rurema-collector/lib/rurema_collector/collector.rb` |
| Create | `../mruby-trunk-changes-generator/lib/mruby_trunk_changes_generator.rb` |
| Create | `../mruby-trunk-changes-generator/lib/mruby_trunk_changes_generator/collector.rb` |
| Create | `../cruby-trunk-changes-generator/lib/cruby_trunk_changes_generator.rb` |
| Create | `../cruby-trunk-changes-generator/lib/cruby_trunk_changes_generator/collector.rb` |

> パスはすべて `/Users/bash/dev/src/github.com/bash0C7/` からの相対

---

## Task 1: TrunkChangesCollector を trunk-changes-diary に追加

**Files:**
- Modify: `/Users/bash/dev/src/github.com/bash0C7/trunk-changes-diary/trunk_changes.rb`
- Create: `/Users/bash/dev/src/github.com/bash0C7/trunk-changes-diary/test/test_trunk_changes_collector.rb`

- [ ] **Step 1: テストファイルを作成（Red）**

```ruby
# /Users/bash/dev/src/github.com/bash0C7/trunk-changes-diary/test/test_trunk_changes_collector.rb
require_relative '../trunk_changes'
require 'test/unit'
require 'date'

class TestTrunkChangesCollector < Test::Unit::TestCase
  def setup
    @git = Object.new
    def @git.commits_for_date(date, branch)
      date == Date.today ? ['abc123'] : []
    end
    def @git.show(hash) = "diff --git a/foo.rb ...\n+added line"
    def @git.commit_metadata(hash)
      { author: 'test', datetime: '2026-04-08 12:00:00 +0900', message: 'fix: test' }
    end

    @gen = Object.new
    def @gen.call(context:) = "### Fix: test (2026-04-08)"

    @collector = TrunkChangesCollector.new(
      repo:              'picoruby/picoruby',
      branch:            'master',
      source_diff:       'picoruby/picoruby:trunk/diff',
      source_article:    'picoruby/picoruby:trunk/article',
      git_ops:           @git,
      content_generator: @gen
    )
  end

  def test_collect_returns_diff_and_article_per_commit
    results = @collector.collect(since: Date.today.iso8601)
    assert_equal 2, results.size
    assert_equal 'picoruby/picoruby:trunk/diff',    results[0][:source]
    assert_equal 'picoruby/picoruby:trunk/article', results[1][:source]
  end

  def test_diff_content_is_show_output
    results = @collector.collect(since: Date.today.iso8601)
    assert_equal @git.show('abc123'), results[0][:content]
  end

  def test_article_content_is_generator_output
    results = @collector.collect(since: Date.today.iso8601)
    assert_equal '### Fix: test (2026-04-08)', results[1][:content]
  end

  def test_empty_when_no_commits
    def @git.commits_for_date(date, branch) = []
    assert_empty @collector.collect(since: Date.today.iso8601)
  end

  def test_nil_since_uses_default_days_range
    # DEFAULT_DAYS=30 → 31日分 × 今日だけ1コミット = 2レコード
    results = @collector.collect(since: nil)
    assert_equal 2, results.size
  end
end
```

- [ ] **Step 2: テストが失敗することを確認（Red）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/trunk-changes-diary
bundle exec rake test 2>&1 | tail -20
```

Expected: `NameError: uninitialized constant TrunkChangesCollector` または同等のエラー

- [ ] **Step 3: TrunkChangesCollector を trunk_changes.rb 末尾に追加（Green）**

`trunk_changes.rb` の末尾（`TrunkChanges` クラスの後）に追記:

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
        ctx     = build_context(hash)
        article = @generator.call(context: ctx)
        [
          { content: ctx[:show_output], source: @source_diff },
          { content: article,           source: @source_article }
        ]
      end
    end
  end

  private

  # Date.today はマシンのタイムゾーン（JST）で評価される
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
      submodule_updates:  []
    }
  end
end
```

- [ ] **Step 4: テストが通ることを確認（Green）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/trunk-changes-diary
bundle exec rake test 2>&1 | tail -20
```

Expected: 全テスト PASS（既存テスト + 新規5件）

- [ ] **Step 5: コミット**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/trunk-changes-diary
git add trunk_changes.rb test/test_trunk_changes_collector.rb
git commit -m "feat: add TrunkChangesCollector library class"
```

---

## Task 2: picoruby-trunk-changes-generator の lib/ を実装

**Files:**
- Create: `/Users/bash/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator/lib/picoruby_trunk_changes_generator.rb`
- Create: `/Users/bash/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator/lib/picoruby_trunk_changes_generator/collector.rb`
- Test: `/Users/bash/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator/test/test_picoruby_trunk_changes_generator.rb` (既存)

- [ ] **Step 1: Gemfile を path: 参照に変更（Task 1 でローカル変更した trunk-changes-diary を使うため）**

`/Users/bash/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator/Gemfile` の該当行を変更:

```ruby
# 変更前
gem 'trunk_changes_diary', github: 'bash0C7/trunk-changes-diary'

# 変更後
gem 'trunk_changes_diary', path: '../trunk-changes-diary'
```

```bash
cd /Users/bash/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator
bundle install 2>&1 | tail -5
```

Expected: `Bundle complete!`

- [ ] **Step 2: 既存テストが失敗することを確認（Red）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator
bundle exec rake test 2>&1 | tail -10
```

Expected: `LoadError: cannot load such file` または `NameError`

- [ ] **Step 3: lib ディレクトリを作成**

```bash
mkdir -p /Users/bash/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator/lib/picoruby_trunk_changes_generator
```

- [ ] **Step 4: collector.rb を作成（Green）**

```ruby
# /Users/bash/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator/lib/picoruby_trunk_changes_generator/collector.rb
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

- [ ] **Step 5: エントリポイントを作成**

```ruby
# /Users/bash/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator/lib/picoruby_trunk_changes_generator.rb
require_relative 'picoruby_trunk_changes_generator/collector'
```

- [ ] **Step 6: テストが通ることを確認（Green）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator
bundle exec rake test 2>&1 | tail -10
```

Expected: 3件 PASS

- [ ] **Step 7: コミット**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator
git add lib/ Gemfile Gemfile.lock
git commit -m "feat: implement PicorubyTrunkChangesGenerator::Collector"
```

---

## Task 3: picoruby-docs-collector の lib/ を実装

**Files:**
- Create: `lib/picoruby_docs_collector.rb`
- Create: `lib/picoruby_docs_collector/rbs_parser.rb`
- Create: `lib/picoruby_docs_collector/readme_parser.rb`
- Create: `lib/picoruby_docs_collector/gem_doc_collector.rb`
- Create: `lib/picoruby_docs_collector/collector.rb`
- Test: `test/test_picoruby_docs_collector.rb` (既存 — RbsParser/ReadmeParser/Collector テスト含む)

すべて `/Users/bash/dev/src/github.com/bash0C7/picoruby-docs-collector/` 配下。

- [ ] **Step 1: 既存テストが失敗することを確認（Red）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/picoruby-docs-collector
bundle exec rake test 2>&1 | tail -10
```

Expected: `LoadError`

- [ ] **Step 2: lib ディレクトリを作成**

```bash
mkdir -p /Users/bash/dev/src/github.com/bash0C7/picoruby-docs-collector/lib/picoruby_docs_collector
```

- [ ] **Step 3: rbs_parser.rb を作成**

```ruby
# lib/picoruby_docs_collector/rbs_parser.rb
module PicorubyDocsCollector
  class RbsParser
    ParsedRbs = Struct.new(:class_name, :sidebar_tag, :constants,
                           :instance_methods, :class_methods, :attributes,
                           keyword_init: true) do
      def to_doc
        lines = ["## #{class_name}"]
        lines << "Category: #{sidebar_tag}" if sidebar_tag
        lines << ""

        unless constants.empty?
          lines << "### Constants"
          constants.each { |c| lines << "- `#{c}`" }
          lines << ""
        end

        unless attributes.empty?
          lines << "### Attributes"
          attributes.each { |a| lines << "- `#{a}`" }
          lines << ""
        end

        unless class_methods.empty?
          lines << "### Class Methods"
          class_methods.each { |m| lines << "- `#{m}`" }
          lines << ""
        end

        unless instance_methods.empty?
          lines << "### Instance Methods"
          instance_methods.each { |m| lines << "- `#{m}`" }
          lines << ""
        end

        lines.join("\n")
      end
    end

    def parse(rbs_source)
      ParsedRbs.new(
        class_name:       extract_class_name(rbs_source),
        sidebar_tag:      extract_sidebar_tag(rbs_source),
        constants:        extract_constants(rbs_source),
        instance_methods: extract_instance_methods(rbs_source),
        class_methods:    extract_class_methods(rbs_source),
        attributes:       extract_attributes(rbs_source)
      )
    end

    private

    def extract_class_name(src)
      src.match(/^class\s+(\S+)/)&.captures&.first || '(unknown)'
    end

    def extract_sidebar_tag(src)
      src.match(/#\s*@sidebar\s+(\S+)/)&.captures&.first
    end

    def extract_constants(src)
      src.scan(/^\s{0,2}([A-Z][A-Z0-9_]+)\s*:/).flatten.uniq
    end

    def extract_class_methods(src)
      src.scan(/def self\.(\w+[?!]?)\s*:\s*([^\n]+)/).map do |name, sig|
        "#{name}: #{sig.strip}"
      end
    end

    def extract_instance_methods(src)
      src.scan(/^\s+def (\w+[?!]?)\s*:\s*([^\n]+)/).map do |name, sig|
        "#{name}: #{sig.strip}"
      end
    end

    def extract_attributes(src)
      src.scan(/attr_(?:reader|writer|accessor)\s+(\w+)\s*:\s*([^\n]+)/).map do |name, type|
        "#{name}: #{type.strip}"
      end
    end
  end
end
```

- [ ] **Step 4: readme_parser.rb を作成**

```ruby
# lib/picoruby_docs_collector/readme_parser.rb
module PicorubyDocsCollector
  class ReadmeParser
    def parse(readme_source)
      stripped = readme_source.strip
      return nil if stripped.empty?
      stripped
    end
  end
end
```

- [ ] **Step 5: gem_doc_collector.rb を作成**

```ruby
# lib/picoruby_docs_collector/gem_doc_collector.rb
require_relative 'rbs_parser'
require_relative 'readme_parser'

module PicorubyDocsCollector
  class GemDocCollector
    def initialize(gem_dir, rbs_parser: nil, readme_parser: nil)
      @gem_dir       = gem_dir
      @rbs_parser    = rbs_parser    || RbsParser.new
      @readme_parser = readme_parser || ReadmeParser.new
    end

    def collect
      results = []

      rbs_content = collect_rbs
      results << rbs_content if rbs_content && !rbs_content.strip.empty?

      readme_content = collect_readme
      results << readme_content if readme_content && !readme_content.strip.empty?

      results
    end

    private

    def collect_rbs
      rbs_files = Dir.glob(File.join(@gem_dir, 'sig', '*.rbs')).sort
      return nil if rbs_files.empty?

      sections = rbs_files.filter_map do |rbs_file|
        @rbs_parser.parse(File.read(rbs_file)).to_doc
      rescue => e
        warn "PicorubyDocsCollector: RBS parse failed: #{rbs_file} (#{e.message})"
        nil
      end

      sections.empty? ? nil : sections.join("\n\n")
    end

    def collect_readme
      readme_path = File.join(@gem_dir, 'README.md')
      return nil unless File.exist?(readme_path)

      @readme_parser.parse(File.read(readme_path))
    rescue => e
      warn "PicorubyDocsCollector: README parse failed: #{readme_path} (#{e.message})"
      nil
    end
  end
end
```

- [ ] **Step 6: collector.rb を作成**

```ruby
# lib/picoruby_docs_collector/collector.rb
require_relative 'gem_doc_collector'

module PicorubyDocsCollector
  class Collector
    SOURCE_PREFIX = 'picoruby/picoruby:docs'

    def initialize(config, gem_doc_collector_class: nil)
      @repo_path               = File.expand_path(config['repo_path'])
      @gem_doc_collector_class = gem_doc_collector_class || GemDocCollector
    end

    def collect(since: nil)
      results = []
      mrbgem_dirs.each do |gem_dir|
        gem_name  = File.basename(gem_dir)
        source    = "#{SOURCE_PREFIX}/#{gem_name}"
        collector = @gem_doc_collector_class.new(gem_dir)
        collector.collect.each do |content|
          results << { content: content, source: source }
        end
      end
      results
    end

    private

    def mrbgem_dirs
      Dir.glob(File.join(@repo_path, 'mrbgems', 'picoruby-*'))
         .select { |d| File.directory?(d) }
         .sort
    end
  end
end
```

- [ ] **Step 7: エントリポイントを作成**

```ruby
# lib/picoruby_docs_collector.rb
require_relative 'picoruby_docs_collector/collector'
```

- [ ] **Step 8: テストが通ることを確認（Green）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/picoruby-docs-collector
bundle exec rake test 2>&1 | tail -15
```

Expected: 全テスト PASS（RbsParser 7件 + ReadmeParser 2件 + Collector 4件 = 13件）

- [ ] **Step 9: コミット**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/picoruby-docs-collector
git add lib/
git commit -m "feat: implement PicorubyDocsCollector"
```

---

## Task 4: rurema-collector の lib/ を実装

**Files:**
- Create: `lib/rurema_collector.rb`
- Create: `lib/rurema_collector/doctree_manager.rb`
- Create: `lib/rurema_collector/collector.rb`
- Test: `test/test_rurema_collector.rb` (既存)

すべて `/Users/bash/dev/src/github.com/bash0C7/rurema-collector/` 配下。

- [ ] **Step 1: 既存テストが失敗することを確認（Red）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/rurema-collector
bundle exec rake test 2>&1 | tail -10
```

Expected: `LoadError`

- [ ] **Step 2: lib ディレクトリを作成**

```bash
mkdir -p /Users/bash/dev/src/github.com/bash0C7/rurema-collector/lib/rurema_collector
```

- [ ] **Step 3: doctree_manager.rb を作成**

```ruby
# lib/rurema_collector/doctree_manager.rb
require 'open3'

module RuremaCollector
  class DoctreeManager
    RUREMA_REPO = 'https://github.com/rurema/doctree.git'

    def initialize(doctree_path)
      @doctree_path = File.expand_path(doctree_path)
    end

    def sync
      if Dir.exist?(File.join(@doctree_path, '.git'))
        git_pull
      else
        git_clone
      end
    end

    def rd_files(_version)
      src_dir = File.join(@doctree_path, 'refm', 'api', 'src')
      Dir.glob(File.join(src_dir, '**', '*.rd')).sort
    end

    private

    def git_clone
      out, status = Open3.capture2e('git', 'clone', '--depth=1', RUREMA_REPO, @doctree_path)
      raise "git clone failed: #{out}" unless status.success?
    end

    def git_pull
      out, status = Open3.capture2e('git', '-C', @doctree_path, 'pull', '--ff-only')
      raise "git pull failed: #{out}" unless status.success?
    end
  end
end
```

- [ ] **Step 4: collector.rb を作成**

```ruby
# lib/rurema_collector/collector.rb
require 'bitclust/rrdparser'
require_relative 'doctree_manager'

module RuremaCollector
  class Collector
    SOURCE_PREFIX = 'rurema/doctree'

    def initialize(config, doctree_manager: nil, rd_parser: nil)
      @version         = config.fetch('version', '3.3.0')
      @doctree_manager = doctree_manager || DoctreeManager.new(config.fetch('doctree_path'))
      @rd_parser       = rd_parser       || DefaultRDParser.new
    end

    def collect(since: nil)
      @doctree_manager.sync
      results = []
      @doctree_manager.rd_files(@version).each do |path|
        parse_rd_file(path, results)
      end
      results
    end

    private

    def version_label
      @version.split('.').first(2).join('.')
    end

    def lib_source(lib_name)
      "#{SOURCE_PREFIX}:ruby#{version_label}/#{lib_name}"
    end

    def class_source(lib_name, class_name)
      "#{SOURCE_PREFIX}:ruby#{version_label}/#{lib_name}##{class_name}"
    end

    def parse_rd_file(path, results)
      library_entry = @rd_parser.parse(path, @version)
      return if library_entry.nil?

      lib_src = library_entry.source.to_s.strip
      results << { content: lib_src, source: lib_source(library_entry.name) } unless lib_src.empty?

      library_entry.classes.each do |class_entry|
        cls_src = class_entry.source.to_s.strip
        next if cls_src.empty?
        results << { content: cls_src, source: class_source(library_entry.name, class_entry.name) }
      end
    rescue => e
      warn "[RuremaCollector] skip #{path}: #{e.class}: #{e.message}"
    end

    class DefaultRDParser
      def parse(path, version)
        BitClust::RRDParser.parse_stdlib_file(path, { 'version' => version })
      rescue => e
        warn "[RuremaCollector::DefaultRDParser] parse error #{path}: #{e.class}: #{e.message}"
        nil
      end
    end
  end
end
```

- [ ] **Step 5: エントリポイントを作成**

```ruby
# lib/rurema_collector.rb
require_relative 'rurema_collector/doctree_manager'
require_relative 'rurema_collector/collector'
```

- [ ] **Step 6: テストが通ることを確認（Green）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/rurema-collector
bundle exec rake test 2>&1 | tail -15
```

Expected: 全テスト PASS（7件）

- [ ] **Step 7: コミット**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/rurema-collector
git add lib/
git commit -m "feat: implement RuremaCollector"
```

---

## Task 5: mruby-trunk-changes-generator の lib/ を実装

**Files:**
- Create: `lib/mruby_trunk_changes_generator.rb`
- Create: `lib/mruby_trunk_changes_generator/collector.rb`
- Test: `test/test_mruby_trunk_changes_generator.rb` (既存)

すべて `/Users/bash/dev/src/github.com/bash0C7/mruby-trunk-changes-generator/` 配下。

- [ ] **Step 1: Gemfile を path: 参照に変更**

`/Users/bash/dev/src/github.com/bash0C7/mruby-trunk-changes-generator/Gemfile` の該当行を変更:

```ruby
# 変更前
gem 'trunk_changes_diary', github: 'bash0C7/trunk-changes-diary'

# 変更後
gem 'trunk_changes_diary', path: '../trunk-changes-diary'
```

```bash
cd /Users/bash/dev/src/github.com/bash0C7/mruby-trunk-changes-generator
bundle install 2>&1 | tail -5
```

Expected: `Bundle complete!`

- [ ] **Step 2: 既存テストが失敗することを確認（Red）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/mruby-trunk-changes-generator
bundle exec rake test 2>&1 | tail -10
```

Expected: `LoadError`

- [ ] **Step 3: lib ディレクトリを作成**

```bash
mkdir -p /Users/bash/dev/src/github.com/bash0C7/mruby-trunk-changes-generator/lib/mruby_trunk_changes_generator
```

- [ ] **Step 4: collector.rb を作成**

```ruby
# lib/mruby_trunk_changes_generator/collector.rb
require 'trunk_changes'

module MrubyTrunkChangesGenerator
  class Collector
    REPO           = 'mruby/mruby'
    SOURCE_DIFF    = 'mruby/mruby:trunk/diff'
    SOURCE_ARTICLE = 'mruby/mruby:trunk/article'

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

- [ ] **Step 5: エントリポイントを作成**

```ruby
# lib/mruby_trunk_changes_generator.rb
require_relative 'mruby_trunk_changes_generator/collector'
```

- [ ] **Step 6: テストが通ることを確認（Green）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/mruby-trunk-changes-generator
bundle exec rake test 2>&1 | tail -10
```

Expected: 3件 PASS

- [ ] **Step 7: コミット**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/mruby-trunk-changes-generator
git add lib/ Gemfile Gemfile.lock
git commit -m "feat: implement MrubyTrunkChangesGenerator::Collector"
```

---

## Task 6: cruby-trunk-changes-generator の lib/ を実装

**Files:**
- Create: `lib/cruby_trunk_changes_generator.rb`
- Create: `lib/cruby_trunk_changes_generator/collector.rb`
- Test: `test/test_cruby_trunk_changes_generator.rb` (既存)

すべて `/Users/bash/dev/src/github.com/bash0C7/cruby-trunk-changes-generator/` 配下。

- [ ] **Step 1: Gemfile を path: 参照に変更**

`/Users/bash/dev/src/github.com/bash0C7/cruby-trunk-changes-generator/Gemfile` の該当行を変更:

```ruby
# 変更前
gem 'trunk_changes_diary', github: 'bash0C7/trunk-changes-diary'

# 変更後
gem 'trunk_changes_diary', path: '../trunk-changes-diary'
```

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cruby-trunk-changes-generator
bundle install 2>&1 | tail -5
```

Expected: `Bundle complete!`

- [ ] **Step 2: 既存テストが失敗することを確認（Red）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cruby-trunk-changes-generator
bundle exec rake test 2>&1 | tail -10
```

Expected: `LoadError`

- [ ] **Step 3: lib ディレクトリを作成**

```bash
mkdir -p /Users/bash/dev/src/github.com/bash0C7/cruby-trunk-changes-generator/lib/cruby_trunk_changes_generator
```

- [ ] **Step 4: collector.rb を作成**

```ruby
# lib/cruby_trunk_changes_generator/collector.rb
require 'trunk_changes'

module CrubyTrunkChangesGenerator
  class Collector
    REPO           = 'ruby/ruby'
    SOURCE_DIFF    = 'ruby/ruby:trunk/diff'
    SOURCE_ARTICLE = 'ruby/ruby:trunk/article'

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

- [ ] **Step 5: エントリポイントを作成**

```ruby
# lib/cruby_trunk_changes_generator.rb
require_relative 'cruby_trunk_changes_generator/collector'
```

- [ ] **Step 6: テストが通ることを確認（Green）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cruby-trunk-changes-generator
bundle exec rake test 2>&1 | tail -10
```

Expected: 3件 PASS

- [ ] **Step 7: コミット**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/cruby-trunk-changes-generator
git add lib/ Gemfile Gemfile.lock
git commit -m "feat: implement CrubyTrunkChangesGenerator::Collector"
```

---

## Task 7: ruby-knowledge-db の全テストが通ることを確認

- [ ] **Step 1: ruby-knowledge-db のテストを実行**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
bundle exec rake test 2>&1
```

Expected: 3件 PASS（Orchestrator テスト）

- [ ] **Step 2: update_all.rb の dry run 確認（ロード確認のみ）**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
bundle exec ruby -e "require 'bundler/setup'; require 'picoruby_trunk_changes_generator'; require 'cruby_trunk_changes_generator'; require 'mruby_trunk_changes_generator'; require 'rurema_collector'; require 'picoruby_docs_collector'; puts 'All requires OK'"
```

Expected: `All requires OK`

- [ ] **Step 3: コミット**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db
git add docs/superpowers/plans/
git commit -m "docs: add implementation plan for 5 collectors"
```
