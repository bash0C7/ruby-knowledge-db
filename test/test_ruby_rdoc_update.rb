# frozen_string_literal: true

require_relative 'test_helper'
require 'ruby_rdoc_collector'

# Integration test for the ruby_rdoc Rake task contract:
# Collector yields records → Rake task's block calls store.store(content, source:) per record.
# This verifies the streaming + per-record store wiring without touching Rake or real DB.

class TestRubyRdocUpdate < Test::Unit::TestCase
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

  class SpyStore
    attr_reader :calls, :closed
    def initialize(skip: false)
      @calls = []
      @skip  = skip
      @closed = false
    end

    def store(content, source:)
      @calls << { content: content, source: source }
      @skip ? nil : @calls.size
    end

    def close
      @closed = true
    end
  end

  def setup
    @dir         = Dir.mktmpdir('rdoc_update')
    @baseline    = RubyRdocCollector::SourceHashBaseline.new(path: File.join(@dir, 'baseline.yml'))
    @output_dir  = File.join(@dir, 'out')
    cache        = RubyRdocCollector::TranslationCache.new(cache_dir: File.join(@dir, 'cache'))
    @translator  = RubyRdocCollector::Translator.new(
      runner: ->(_p) { 'JP' }, cache: cache, sleeper: ->(_s) {}
    )
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def build_entity(name)
    RubyRdocCollector::ClassEntity.new(
      name: name, description: "desc #{name}", methods: [], constants: [], superclass: 'Object'
    )
  end

  def build_collector(entities)
    RubyRdocCollector::Collector.new({},
      fetcher:    StubFetcher.new('/fake'),
      parser:     StubParser.new(entities),
      translator: @translator,
      formatter:  RubyRdocCollector::MarkdownFormatter.new,
      baseline:   @baseline,
      output_dir: @output_dir)
  end

  def test_streaming_hooks_each_record_into_store
    store     = SpyStore.new
    collector = build_collector([build_entity('A'), build_entity('B')])

    stored = 0
    skipped = 0
    collector.collect do |record|
      id = store.store(record[:content], source: record[:source])
      id ? (stored += 1) : (skipped += 1)
    end

    assert_equal 2, store.calls.size
    assert_equal 2, stored
    assert_equal 0, skipped
    sources = store.calls.map { |c| c[:source] }
    assert_include sources, 'ruby/ruby:rdoc/trunk/A'
    assert_include sources, 'ruby/ruby:rdoc/trunk/B'
  end

  def test_store_skip_signal_is_respected
    store     = SpyStore.new(skip: true) # always nil (dup)
    collector = build_collector([build_entity('A')])

    stored = 0
    skipped = 0
    collector.collect do |record|
      id = store.store(record[:content], source: record[:source])
      id ? (stored += 1) : (skipped += 1)
    end

    assert_equal 1, store.calls.size
    assert_equal 0, stored
    assert_equal 1, skipped
  end

  def test_store_exception_propagation_prevents_baseline_update
    store     = SpyStore.new
    entity    = build_entity('A')
    collector = build_collector([entity])

    # simulate Rake task's inline rescue+raise: propagate to Collector's yield rescue
    errors = 0
    collector.collect do |record|
      begin
        store.store(record[:content], source: record[:source])
        raise 'boom'
      rescue
        errors += 1
        raise
      end
    end

    assert_equal 1, errors
    b2 = RubyRdocCollector::SourceHashBaseline.new(path: File.join(@dir, 'baseline.yml'))
    assert b2.changed?('A', @baseline.hash_for(entity)),
      'baseline must NOT be updated when yield raises'
  end
end
