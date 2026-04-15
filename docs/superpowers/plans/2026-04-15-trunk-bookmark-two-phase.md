# Trunk-Changes Two-Phase Bookmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `rake daily` record per-source two-phase bookmarks (`started` / `completed`) in `db/last_run.yml` so the trunk-changes daily subagent can compute SINCE deterministically from local state and detect WIP runs (started-but-not-completed) without querying esa.

**Architecture:** Introduce a new `RubyKnowledgeDb::TrunkBookmark` module that owns the read/write and status-derivation logic for trunk entries in `db/last_run.yml`. Entries for trunk keys (`picoruby_trunk`, `cruby_trunk`, `mruby_trunk`) become Hash values with four fields (`last_started_at`, `last_started_before`, `last_completed_at`, `last_completed_before`). Legacy flat string values for docs collectors (`RuremaCollector::Collector`, `PicorubyDocsCollector::Collector`) stay untouched — the module only reads/writes trunk-shaped keys. `rake daily` calls `mark_started` before each source begins and `mark_completed` only after that source's esa phase finishes with zero errors. The subagent's PLAN mode is rewritten to read this structure, propose `SINCE = min(last_completed_before)` across trunk sources, and surface any WIP condition.

**Tech Stack:** Ruby 4.0, test-unit, YAML, rake. No new gems.

---

## File Structure

**New files:**
- `lib/ruby_knowledge_db/trunk_bookmark.rb` — module with `load`, `save`, `mark_started`, `mark_completed`, `status`. Pure YAML-dict manipulation, no global state.
- `test/test_trunk_bookmark.rb` — unit tests for the module.

**Modified files:**
- `Rakefile` — require the new module. Modify the `daily` task body (lines ~602-689) to call `mark_started` / `mark_completed` per source. Remove `next if records.empty?` in favor of conditional phase-gating so empty days still mark completed.
- `.claude/agents/ruby-knowledge-db-trunk-changes-daily.md` — rewrite the "SINCE default" section of PLAN mode to read the new structure. Update the report format to show per-source status + WIP flags.
- `CLAUDE.md` — update the paragraph that says "`rake daily` は `last_run.yml` を読まへんし書かへん" to reflect the new two-phase write behavior; document the new schema.

**Untouched:**
- Docs pipeline (`rake update:rurema`, `rake update:picoruby_docs`) and its flat-string bookmarks.
- Rake phase tasks (`generate:*`, `import:*`, `esa:*`) — bookmarks apply only to the composite `daily` task.

---

## Task 1: Create TrunkBookmark module skeleton with load/save

**Files:**
- Create: `lib/ruby_knowledge_db/trunk_bookmark.rb`
- Create: `test/test_trunk_bookmark.rb`

- [ ] **Step 1: Write the failing test for load/save round-trip**

Create `test/test_trunk_bookmark.rb`:

```ruby
# frozen_string_literal: true

require_relative '../test/test_helper'
require_relative '../lib/ruby_knowledge_db/trunk_bookmark'
require 'tmpdir'
require 'fileutils'

class TestTrunkBookmark < Test::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir
    @path   = File.join(@tmpdir, 'last_run.yml')
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_load_returns_empty_hash_when_file_missing
    assert_equal({}, RubyKnowledgeDb::TrunkBookmark.load(@path))
  end

  def test_load_returns_empty_hash_when_file_is_empty
    File.write(@path, '')
    assert_equal({}, RubyKnowledgeDb::TrunkBookmark.load(@path))
  end

  def test_save_then_load_round_trip
    data = { 'picoruby_trunk' => { 'last_started_before' => '2026-04-15' } }
    RubyKnowledgeDb::TrunkBookmark.save(@path, data)
    assert_equal data, RubyKnowledgeDb::TrunkBookmark.load(@path)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rake test TEST=test/test_trunk_bookmark.rb`
Expected: FAIL — `cannot load such file -- .../lib/ruby_knowledge_db/trunk_bookmark`

- [ ] **Step 3: Create the module with load/save only**

Create `lib/ruby_knowledge_db/trunk_bookmark.rb`:

```ruby
# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module RubyKnowledgeDb
  module TrunkBookmark
    module_function

    def load(path)
      return {} unless File.exist?(path)
      YAML.load_file(path) || {}
    end

    def save(path, data)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, data.to_yaml)
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rake test TEST=test/test_trunk_bookmark.rb`
Expected: PASS (3 tests, 3 assertions)

- [ ] **Step 5: Commit**

```bash
git add lib/ruby_knowledge_db/trunk_bookmark.rb test/test_trunk_bookmark.rb
git commit -m "feat: add TrunkBookmark module skeleton with load/save"
```

---

## Task 2: Implement mark_started

**Files:**
- Modify: `lib/ruby_knowledge_db/trunk_bookmark.rb`
- Modify: `test/test_trunk_bookmark.rb`

- [ ] **Step 1: Write the failing tests for mark_started**

Append to `test/test_trunk_bookmark.rb` (inside the class, before the final `end`):

```ruby
  def test_mark_started_on_empty_data
    now  = Time.new(2026, 4, 15, 10, 0, 0, '+09:00')
    data = RubyKnowledgeDb::TrunkBookmark.mark_started({}, 'picoruby_trunk', before: '2026-04-15', at: now)
    assert_equal '2026-04-15T10:00:00+09:00', data['picoruby_trunk']['last_started_at']
    assert_equal '2026-04-15',                data['picoruby_trunk']['last_started_before']
  end

  def test_mark_started_preserves_prior_completed_fields
    now  = Time.new(2026, 4, 16, 10, 0, 0, '+09:00')
    data = {
      'picoruby_trunk' => {
        'last_started_at'       => '2026-04-15T10:00:00+09:00',
        'last_started_before'   => '2026-04-15',
        'last_completed_at'     => '2026-04-15T10:05:00+09:00',
        'last_completed_before' => '2026-04-15'
      }
    }
    data = RubyKnowledgeDb::TrunkBookmark.mark_started(data, 'picoruby_trunk', before: '2026-04-16', at: now)
    assert_equal '2026-04-16T10:00:00+09:00', data['picoruby_trunk']['last_started_at']
    assert_equal '2026-04-16',                data['picoruby_trunk']['last_started_before']
    # prior completed fields must remain — they are evidence of prior success
    assert_equal '2026-04-15T10:05:00+09:00', data['picoruby_trunk']['last_completed_at']
    assert_equal '2026-04-15',                data['picoruby_trunk']['last_completed_before']
  end

  def test_mark_started_does_not_touch_other_keys
    data = { 'cruby_trunk' => { 'last_started_before' => '2026-04-14' } }
    data = RubyKnowledgeDb::TrunkBookmark.mark_started(data, 'picoruby_trunk', before: '2026-04-15', at: Time.now)
    assert_equal '2026-04-14', data['cruby_trunk']['last_started_before']
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rake test TEST=test/test_trunk_bookmark.rb`
Expected: FAIL — `undefined method 'mark_started'`

- [ ] **Step 3: Implement mark_started**

Add to `lib/ruby_knowledge_db/trunk_bookmark.rb` inside the module (before the final `end end`):

```ruby
    def mark_started(data, source_key, before:, at: Time.now)
      entry = data[source_key].is_a?(Hash) ? data[source_key].dup : {}
      entry['last_started_at']     = at.iso8601
      entry['last_started_before'] = before.to_s
      data[source_key] = entry
      data
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rake test TEST=test/test_trunk_bookmark.rb`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/ruby_knowledge_db/trunk_bookmark.rb test/test_trunk_bookmark.rb
git commit -m "feat: add TrunkBookmark.mark_started"
```

---

## Task 3: Implement mark_completed

**Files:**
- Modify: `lib/ruby_knowledge_db/trunk_bookmark.rb`
- Modify: `test/test_trunk_bookmark.rb`

- [ ] **Step 1: Write the failing tests for mark_completed**

Append to `test/test_trunk_bookmark.rb` (inside the class):

```ruby
  def test_mark_completed_on_fresh_started_entry
    now = Time.new(2026, 4, 15, 10, 5, 0, '+09:00')
    data = {
      'picoruby_trunk' => {
        'last_started_at'     => '2026-04-15T10:00:00+09:00',
        'last_started_before' => '2026-04-15'
      }
    }
    data = RubyKnowledgeDb::TrunkBookmark.mark_completed(data, 'picoruby_trunk', before: '2026-04-15', at: now)
    assert_equal '2026-04-15T10:05:00+09:00', data['picoruby_trunk']['last_completed_at']
    assert_equal '2026-04-15',                data['picoruby_trunk']['last_completed_before']
    # started fields preserved as evidence
    assert_equal '2026-04-15T10:00:00+09:00', data['picoruby_trunk']['last_started_at']
    assert_equal '2026-04-15',                data['picoruby_trunk']['last_started_before']
  end

  def test_mark_completed_when_started_missing_still_writes
    # defensive: even without a preceding started, accept the completion write
    now = Time.new(2026, 4, 15, 10, 5, 0, '+09:00')
    data = RubyKnowledgeDb::TrunkBookmark.mark_completed({}, 'picoruby_trunk', before: '2026-04-15', at: now)
    assert_equal '2026-04-15', data['picoruby_trunk']['last_completed_before']
    assert_nil              data['picoruby_trunk']['last_started_before']
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rake test TEST=test/test_trunk_bookmark.rb`
Expected: FAIL — `undefined method 'mark_completed'`

- [ ] **Step 3: Implement mark_completed**

Add to `lib/ruby_knowledge_db/trunk_bookmark.rb` inside the module:

```ruby
    def mark_completed(data, source_key, before:, at: Time.now)
      entry = data[source_key].is_a?(Hash) ? data[source_key].dup : {}
      entry['last_completed_at']     = at.iso8601
      entry['last_completed_before'] = before.to_s
      data[source_key] = entry
      data
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rake test TEST=test/test_trunk_bookmark.rb`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/ruby_knowledge_db/trunk_bookmark.rb test/test_trunk_bookmark.rb
git commit -m "feat: add TrunkBookmark.mark_completed"
```

---

## Task 4: Implement status derivation (WIP detection, recommended SINCE)

**Files:**
- Modify: `lib/ruby_knowledge_db/trunk_bookmark.rb`
- Modify: `test/test_trunk_bookmark.rb`

- [ ] **Step 1: Write the failing tests for status**

Append to `test/test_trunk_bookmark.rb`:

```ruby
  def test_status_empty_data_returns_nil_bookmarks
    status = RubyKnowledgeDb::TrunkBookmark.status({}, %w[picoruby_trunk cruby_trunk])
    assert_equal(%w[picoruby_trunk cruby_trunk], status.keys)
    status.each_value do |s|
      assert_nil s[:last_started_before]
      assert_nil s[:last_completed_before]
      assert_false s[:wip]
    end
  end

  def test_status_clean_source_reports_not_wip
    data = {
      'picoruby_trunk' => {
        'last_started_at'       => '2026-04-15T10:00:00+09:00',
        'last_started_before'   => '2026-04-15',
        'last_completed_at'     => '2026-04-15T10:05:00+09:00',
        'last_completed_before' => '2026-04-15'
      }
    }
    status = RubyKnowledgeDb::TrunkBookmark.status(data, %w[picoruby_trunk])
    assert_false status['picoruby_trunk'][:wip]
    assert_equal '2026-04-15', status['picoruby_trunk'][:recommended_since]
  end

  def test_status_detects_wip_when_started_newer_than_completed
    data = {
      'picoruby_trunk' => {
        'last_started_before'   => '2026-04-15',
        'last_completed_before' => '2026-04-14'
      }
    }
    status = RubyKnowledgeDb::TrunkBookmark.status(data, %w[picoruby_trunk])
    assert_true  status['picoruby_trunk'][:wip]
    assert_equal '2026-04-14', status['picoruby_trunk'][:recommended_since]
  end

  def test_status_detects_wip_when_completed_missing
    data = {
      'picoruby_trunk' => { 'last_started_before' => '2026-04-15' }
    }
    status = RubyKnowledgeDb::TrunkBookmark.status(data, %w[picoruby_trunk])
    assert_true status['picoruby_trunk'][:wip]
    assert_nil  status['picoruby_trunk'][:recommended_since]
  end

  def test_recommended_since_floor_returns_min_completed_before
    data = {
      'picoruby_trunk' => { 'last_completed_before' => '2026-04-14' },
      'cruby_trunk'    => { 'last_completed_before' => '2026-04-10' },
      'mruby_trunk'    => { 'last_completed_before' => '2026-04-12' }
    }
    floor = RubyKnowledgeDb::TrunkBookmark.recommended_since_floor(
      data, %w[picoruby_trunk cruby_trunk mruby_trunk]
    )
    assert_equal '2026-04-10', floor
  end

  def test_recommended_since_floor_returns_nil_when_any_source_has_no_completed
    data = {
      'picoruby_trunk' => { 'last_completed_before' => '2026-04-14' },
      'cruby_trunk'    => { 'last_started_before'   => '2026-04-10' }  # never completed
    }
    floor = RubyKnowledgeDb::TrunkBookmark.recommended_since_floor(
      data, %w[picoruby_trunk cruby_trunk]
    )
    assert_nil floor
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rake test TEST=test/test_trunk_bookmark.rb`
Expected: FAIL — `undefined method 'status'` / `undefined method 'recommended_since_floor'`

- [ ] **Step 3: Implement status and recommended_since_floor**

Add to `lib/ruby_knowledge_db/trunk_bookmark.rb` inside the module:

```ruby
    # @return [Hash{String => Hash}] keyed by source_key, each with
    #   :last_started_at, :last_started_before, :last_completed_at,
    #   :last_completed_before, :wip, :recommended_since
    def status(data, source_keys)
      source_keys.each_with_object({}) do |key, acc|
        entry     = data[key].is_a?(Hash) ? data[key] : {}
        started   = entry['last_started_before']
        completed = entry['last_completed_before']
        wip = !started.nil? && (completed.nil? || started > completed)
        acc[key] = {
          last_started_at:       entry['last_started_at'],
          last_started_before:   started,
          last_completed_at:     entry['last_completed_at'],
          last_completed_before: completed,
          wip:                   wip,
          recommended_since:     completed
        }
      end
    end

    # Returns the safest SINCE floor across all sources: min of last_completed_before.
    # Returns nil if any source has no last_completed_before (caller must decide fallback).
    def recommended_since_floor(data, source_keys)
      completed = source_keys.map do |key|
        entry = data[key].is_a?(Hash) ? data[key] : {}
        entry['last_completed_before']
      end
      return nil if completed.any?(&:nil?)
      completed.min
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rake test TEST=test/test_trunk_bookmark.rb`
Expected: PASS (14 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/ruby_knowledge_db/trunk_bookmark.rb test/test_trunk_bookmark.rb
git commit -m "feat: add TrunkBookmark.status and recommended_since_floor"
```

---

## Task 5: Wire TrunkBookmark into `rake daily`

**Files:**
- Modify: `Rakefile` (the `task daily:` block, currently at lines 602-689)

- [ ] **Step 1: Confirm current daily flow by re-reading Rakefile:602-689**

Run: `bundle exec rake -T daily`
Expected: shows `rake daily` entry.

Read `Rakefile:602-689` to confirm the source loop structure: `cfg['sources'].each do |key, source_cfg|` with `next if records.empty?` and sequential Phase 1 / 2a / 2b.

- [ ] **Step 2: Add require to Rakefile and modify the `daily` task**

At the top of `Rakefile`, add alongside the existing `require_relative 'lib/ruby_knowledge_db/config'` (around line 2):

```ruby
require_relative 'lib/ruby_knowledge_db/trunk_bookmark'
```

Rewrite the inside of the `cfg['sources'].each` loop in the `daily` task. Replace this block (Rakefile lines ~618-674):

```ruby
  cfg['sources'].each do |key, source_cfg|
    next unless key.end_with?('_trunk')
    short_name = key.sub(/_trunk$/, '')
    puts "\n--- #{key} ---"

    # Phase 1: generate
    ENV['SINCE']  = since
    ENV['BEFORE'] = before
    collector = build_trunk_collector(source_cfg)
    records   = collector.collect(since: since, before: before)

    tmpdir = Dir.mktmpdir(["#{key}_", "_#{since}_#{before}"])
    records.each { |r| write_md(tmpdir, r) }
    puts "generate: #{records.size} records → #{tmpdir}"

    next if records.empty?

    # Phase 2a: import to SQLite
    files = Dir.glob(File.join(tmpdir, '*.md')).sort
    stored = skipped = 0
    files.each do |path|
      rec = parse_md(path)
      next unless rec
      id = store.store(rec[:content], source: rec[:source])
      id ? (stored += 1) : (skipped += 1)
    end
    puts "import: stored=#{stored}, skipped=#{skipped}"

    # Phase 2b: post to esa
    next unless esa_cfg
    category = esa_cfg.dig('sources', key, 'category')
    next unless category

    article_files = Dir.glob(File.join(tmpdir, '*-article.md')).sort
    posted = 0
    article_files.each do |path|
      rec = parse_md(path)
      next unless rec
      date = File.basename(path)[/\A(\d{4}-\d{2}-\d{2})/, 1]
      next unless date
      y, m, d = date.split('-')
      date_category = "#{category}/#{y}/#{m}/#{d}"
      title = "#{date}-#{short_name}-trunk-changes"

      writer = RubyKnowledgeDb::EsaWriter.new(
        team: esa_cfg['team'], category: date_category, wip: esa_cfg['wip']
      )
      res = writer.post(name: title, body_md: rec[:content])
      if res['number']
        puts "esa: ##{res['number']} #{res['full_name']}"
        posted += 1
      else
        warn "ERROR posting #{path}: #{res.inspect}"
      end
    end
    puts "esa: posted=#{posted}"
  end
```

with this (the `next if records.empty?` is removed; phases are gated with `if` so empty days still run to completion and mark bookmark):

```ruby
  cfg['sources'].each do |key, source_cfg|
    next unless key.end_with?('_trunk')
    short_name = key.sub(/_trunk$/, '')
    puts "\n--- #{key} ---"

    # Mark started (two-phase bookmark, Phase 1 of 2)
    bm = RubyKnowledgeDb::TrunkBookmark.load(LAST_RUN_PATH)
    RubyKnowledgeDb::TrunkBookmark.mark_started(bm, key, before: before)
    RubyKnowledgeDb::TrunkBookmark.save(LAST_RUN_PATH, bm)

    source_ok = false
    begin
      # Phase 1: generate
      ENV['SINCE']  = since
      ENV['BEFORE'] = before
      collector = build_trunk_collector(source_cfg)
      records   = collector.collect(since: since, before: before)

      tmpdir = Dir.mktmpdir(["#{key}_", "_#{since}_#{before}"])
      records.each { |r| write_md(tmpdir, r) }
      puts "generate: #{records.size} records → #{tmpdir}"

      any_esa_error = false

      if records.any?
        # Phase 2a: import to SQLite
        files = Dir.glob(File.join(tmpdir, '*.md')).sort
        stored = skipped = 0
        files.each do |path|
          rec = parse_md(path)
          next unless rec
          id = store.store(rec[:content], source: rec[:source])
          id ? (stored += 1) : (skipped += 1)
        end
        puts "import: stored=#{stored}, skipped=#{skipped}"

        # Phase 2b: post to esa
        if esa_cfg && (category = esa_cfg.dig('sources', key, 'category'))
          article_files = Dir.glob(File.join(tmpdir, '*-article.md')).sort
          posted = 0
          article_files.each do |path|
            rec = parse_md(path)
            next unless rec
            date = File.basename(path)[/\A(\d{4}-\d{2}-\d{2})/, 1]
            next unless date
            y, m, d = date.split('-')
            date_category = "#{category}/#{y}/#{m}/#{d}"
            title = "#{date}-#{short_name}-trunk-changes"

            writer = RubyKnowledgeDb::EsaWriter.new(
              team: esa_cfg['team'], category: date_category, wip: esa_cfg['wip']
            )
            res = writer.post(name: title, body_md: rec[:content])
            if res['number']
              puts "esa: ##{res['number']} #{res['full_name']}"
              posted += 1
            else
              warn "ERROR posting #{path}: #{res.inspect}"
              any_esa_error = true
            end
          end
          puts "esa: posted=#{posted}"
        end
      end

      source_ok = !any_esa_error
    rescue => e
      warn "ERROR in #{key}: #{e.class}: #{e.message}"
      source_ok = false
    end

    # Mark completed only on full success (Phase 2 of 2)
    if source_ok
      bm = RubyKnowledgeDb::TrunkBookmark.load(LAST_RUN_PATH)
      RubyKnowledgeDb::TrunkBookmark.mark_completed(bm, key, before: before)
      RubyKnowledgeDb::TrunkBookmark.save(LAST_RUN_PATH, bm)
      puts "bookmark: #{key} completed before=#{before}"
    else
      warn "bookmark: #{key} NOT marked completed (errors or exception) — next run will re-process"
    end
  end
```

- [ ] **Step 3: Run full test suite to make sure nothing regressed**

Run: `bundle exec rake test`
Expected: PASS (9 original tests + 14 new TrunkBookmark tests = 23 tests)

- [ ] **Step 4: Dry-run the Rakefile loads**

Run: `bundle exec rake -T | grep daily`
Expected: `rake daily` line prints without Ruby syntax errors.

- [ ] **Step 5: Commit**

```bash
git add Rakefile
git commit -m "feat: wire TrunkBookmark two-phase marks into rake daily"
```

---

## Task 6: Update subagent PLAN logic

**Files:**
- Modify: `.claude/agents/ruby-knowledge-db-trunk-changes-daily.md`

- [ ] **Step 1: Replace the "SINCE default" section**

In `.claude/agents/ruby-knowledge-db-trunk-changes-daily.md`, locate the section starting with `### SINCE default — read from \`db/last_run.yml\`` (around lines 40-74).

Replace the entire section (from that header through the end of the `Override rules:` list) with:

````markdown
### SINCE default — read from `db/last_run.yml` (two-phase bookmark)

The default `SINCE` comes from `db/last_run.yml`. `rake daily` writes per-source bookmarks there in a two-phase shape:

```yaml
picoruby_trunk:
  last_started_at:       2026-04-15T10:00:00+09:00
  last_started_before:   2026-04-15
  last_completed_at:     2026-04-15T10:05:00+09:00
  last_completed_before: 2026-04-15
cruby_trunk:
  ...
mruby_trunk:
  ...
```

`last_started_*` is written before Phase 1 of each source; `last_completed_*` is only written after Phase 2b (esa post) succeeds with zero errors. A source whose `last_started_before > last_completed_before` (or whose `last_completed_*` is missing entirely) is **WIP** — its last run did not complete.

Recommended `SINCE` = min of `last_completed_before` across the trunk sources read from `config/sources.yml`. Using the minimum is the safest floor: it guarantees no source is skipped, and `content_hash` dedup in the Store makes re-processing harmless at the DB layer.

Read the file with a small Ruby one-liner (stay consistent with the project's "Ruby only, always via bundle exec" rule):

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db && \
  bundle exec ruby -ryaml -e '
    require_relative "lib/ruby_knowledge_db/trunk_bookmark"
    require "yaml"
    cfg  = YAML.load_file("config/sources.yml") || {}
    keys = (cfg["sources"] || {}).keys.select { |k| k.to_s.end_with?("_trunk") }
    data = RubyKnowledgeDb::TrunkBookmark.load("db/last_run.yml")
    status = RubyKnowledgeDb::TrunkBookmark.status(data, keys)
    floor  = RubyKnowledgeDb::TrunkBookmark.recommended_since_floor(data, keys)
    puts "TRUNK_KEYS=#{keys.join(",")}"
    status.each do |k, s|
      puts "STATUS\t#{k}\tstarted=#{s[:last_started_before].inspect}\tcompleted=#{s[:last_completed_before].inspect}\twip=#{s[:wip]}"
    end
    puts "FLOOR=#{floor.inspect}"
  '
```

Interpret the result:

- **Happy path** — all sources have non-nil `last_completed_before`, `FLOOR` is a `YYYY-MM-DD`. Use it as `SINCE`.
- **WIP detected** — one or more sources have `wip=true`. Still use `FLOOR` as SINCE (will replay from the last fully-completed floor), but **surface the WIP sources explicitly** in the report so the user knows a prior run did not finish cleanly.
- **No completion history at all** — `FLOOR=nil`. Fall back to yesterday (JST) and flag this as a first-run / bootstrap condition in the report.

Override rules:
- If the prompt gave explicit `SINCE`, use that verbatim and note "explicit override — last_run.yml ignored".
- Otherwise always prefer the `FLOOR` value.
````

- [ ] **Step 2: Replace the "Report format" section**

In the same file, locate the `### Report format` section (around lines 97-117) and replace its body with this new shape:

````markdown
### Report format

Report back in this exact structure (Japanese is fine, but keep the labeled fields so the main session can parse):

```
## daily-runner PLAN
- APP_ENV: production
- SINCE:   2026-04-14         ← FLOOR = min of last_completed_before
- BEFORE:  2026-04-15          ← today (JST)
- 半開区間: [SINCE, BEFORE)
- DB:      db/ruby_knowledge.db (XX bytes, mtime ...)
- 対象ソース: picoruby_trunk / cruby_trunk / mruby_trunk

### Per-source bookmark status
- picoruby_trunk: started=2026-04-14  completed=2026-04-14  (OK)
- cruby_trunk:    started=2026-04-14  completed=2026-04-14  (OK)
- mruby_trunk:    started=2026-04-14  completed=2026-04-14  (OK)

### WIP detected
(none)   ← or per-source list if any wip=true

- 実行予定コマンド:
  APP_ENV=production SINCE=2026-04-14 BEFORE=2026-04-15 bundle exec rake daily
- 次のアクション: ユーザーに上記範囲で良いか確認し、OK なら
  `CONFIRMED SINCE=2026-04-14 BEFORE=2026-04-15` を含むプロンプトで再度このエージェントを呼び出してください。
```

If WIP is detected, list the offenders explicitly:
```
### WIP detected
- picoruby_trunk: started=2026-04-15 completed=2026-04-14  ⚠ 前回 started やのに completed 未記録
  → SINCE=2026-04-14 で再実行すれば content_hash 冪等で安全に拾い直せます
```

If `FLOOR=nil` (no completion history), surface the bootstrap fallback:
```
- SINCE:   2026-04-14         ← FALLBACK: last_run.yml に completed 履歴なし、昨日を使用
```
````

- [ ] **Step 3: Manually verify the Ruby one-liner against the real repo**

Run:
```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db && \
  bundle exec ruby -ryaml -e '
    require_relative "lib/ruby_knowledge_db/trunk_bookmark"
    require "yaml"
    cfg  = YAML.load_file("config/sources.yml") || {}
    keys = (cfg["sources"] || {}).keys.select { |k| k.to_s.end_with?("_trunk") }
    data = RubyKnowledgeDb::TrunkBookmark.load("db/last_run.yml")
    status = RubyKnowledgeDb::TrunkBookmark.status(data, keys)
    floor  = RubyKnowledgeDb::TrunkBookmark.recommended_since_floor(data, keys)
    puts "TRUNK_KEYS=#{keys.join(",")}"
    status.each do |k, s|
      puts "STATUS\t#{k}\tstarted=#{s[:last_started_before].inspect}\tcompleted=#{s[:last_completed_before].inspect}\twip=#{s[:wip]}"
    end
    puts "FLOOR=#{floor.inspect}"
  '
```
Expected: prints `TRUNK_KEYS=picoruby_trunk,cruby_trunk,mruby_trunk`, then three `STATUS` lines. Immediately after Task 5 is deployed, all three sources should show `started=nil completed=nil wip=false` (no history under the new key scheme yet) and `FLOOR=nil`. The first successful `rake daily` run will populate them.

- [ ] **Step 4: Commit**

```bash
git add .claude/agents/ruby-knowledge-db-trunk-changes-daily.md
git commit -m "docs(agent): rewrite trunk-changes-daily PLAN to use two-phase bookmark"
```

---

## Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Locate and replace the obsolete paragraph**

In `CLAUDE.md`, find the paragraph under `### since 永続化` that reads:

```
**注意:** `rake daily`（trunk-changes 3フェーズパイプライン）は `last_run.yml` を**読まへんし書かへん**。trunk-changes 系の次回 SINCE は esa 側の最新投稿日（`bash-trunk-changes` team の `production/{picoruby,cruby,mruby}/trunk-changes/YYYY/MM/DD/...` パス）を事実上の bookmark として判断する。`last_run.yml` は `scripts/update_all.rb` と rurema / picoruby_docs 系 collector 専用。
```

Replace it with:

```
**更新:** `rake daily`（trunk-changes 3フェーズパイプライン）は **二段コミット式 bookmark** を `last_run.yml` に書き込む。各 `*_trunk` ソースごとに Phase 1 開始直前に `last_started_{at,before}` を記録し、Phase 2b（esa 投稿）がエラーなく完走した時だけ `last_completed_{at,before}` を追記する。`last_started_before > last_completed_before`（あるいは `last_completed_*` 欠落）のソースは WIP = 前回実行が完走してへん、というシグナル。次回の SINCE は `min(last_completed_before)` を床にして safe floor から再開（`content_hash` 冪等で重複は自動スキップ）。`rurema` / `picoruby_docs` 系は従来通り flat string（`scripts/update_all.rb` と `namespace :update` が管理）。

二段コミット bookmark のスキーマ例:
\`\`\`yaml
picoruby_trunk:
  last_started_at:       2026-04-15T10:00:00+09:00
  last_started_before:   2026-04-15
  last_completed_at:     2026-04-15T10:05:00+09:00
  last_completed_before: 2026-04-15
\`\`\`
```

Use the Edit tool with the full "Replace with" block. Keep surrounding sections untouched.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document two-phase trunk bookmark in CLAUDE.md"
```

---

## Task 8: Integration smoke-test (dry-run of rake daily on empty range)

**Files:** none modified; this is a behavioral verification task.

- [ ] **Step 1: Pick a zero-change date to keep the test cheap**

The goal is to exercise the mark_started / mark_completed wiring without actually posting new articles to esa. Use a past date that is **already fully ingested** and where `content_hash` will dedup everything at the import phase.

Proposed range: `SINCE=2026-04-14 BEFORE=2026-04-15` (today is 2026-04-15; 2026-04-14 was already ingested in the prior conversation, so `store.store` will skip duplicates and there will be nothing new to post).

Caveat: esa posts ARE attempted per article — the rake task does not short-circuit on duplicates at the esa layer. If that would create a "(1)" suffix duplicate on esa, skip this task and instead verify by reading the resulting `db/last_run.yml` after the user's next real daily run.

Decision: **skip this task if the user prefers to wait for the next real daily**. Otherwise, run with the `APP_ENV=test` DB to isolate from production DB writes, but note that esa posts still go to the `bist` team (test config) — check that this is acceptable before running.

- [ ] **Step 2: Run against test environment**

Only if the user approves:

```bash
cd /Users/bash/dev/src/github.com/bash0C7/ruby-knowledge-db && \
  APP_ENV=test SINCE=2026-04-14 BEFORE=2026-04-15 bundle exec rake daily
```
Expected output tail should include `bookmark: picoruby_trunk completed before=2026-04-15` (and same for cruby/mruby) for each source that succeeds.

- [ ] **Step 3: Inspect db/last_run.yml**

Run: `cat db/last_run.yml`
Expected: under `picoruby_trunk:` / `cruby_trunk:` / `mruby_trunk:` keys, both `last_started_*` and `last_completed_*` populated with `2026-04-15` (for `_before`) and an ISO8601 timestamp (for `_at`).

If this confirms the wiring, no commit needed — this is a verification task.

---

## Self-Review (completed before handoff)

1. **Spec coverage:**
   - Two-phase bookmark schema in `last_run.yml` → Tasks 1-4 (module), Task 5 (Rakefile wiring)
   - `rake daily` writes `started` before phase 1 → Task 5, Step 2
   - `rake daily` writes `completed` only after esa phase with zero errors → Task 5, Step 2 (`source_ok = !any_esa_error`)
   - Subagent PLAN reads `last_completed_before`, detects WIP → Task 6
   - SINCE = min(last_completed_before) → Task 4 (`recommended_since_floor`) + Task 6
   - CLAUDE.md reflects new design → Task 7

2. **Placeholder scan:** no TBD / TODO / "handle edge cases" / "similar to Task N". All code blocks are complete.

3. **Type consistency:**
   - Module name `RubyKnowledgeDb::TrunkBookmark` used consistently across Tasks 1, 2, 3, 4, 5, 6.
   - Method names `load`, `save`, `mark_started`, `mark_completed`, `status`, `recommended_since_floor` unchanged throughout.
   - Hash keys `last_started_at`, `last_started_before`, `last_completed_at`, `last_completed_before` consistent everywhere (strings in the YAML, symbols in the `status` return Hash — this is intentional and tested).
   - Source keys `picoruby_trunk` / `cruby_trunk` / `mruby_trunk` match `config/sources.yml`. Verified by the Task 6 Step 3 command.
