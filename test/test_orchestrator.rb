# frozen_string_literal: true

require_relative '../test/test_helper'
require_relative '../lib/ruby_knowledge_db/orchestrator'

class StubCollector
  def initialize(chunks) = @chunks = chunks
  def collect(since: nil, before: nil) = @chunks
end

class StubStore
  attr_reader :stored
  def initialize = @stored = []
  def store(content, source:)
    @stored << { content: content, source: source }
    @stored.size  # id を返す
  end
end

class TestOrchestrator < Test::Unit::TestCase
  def test_run_stores_all_chunks
    store     = StubStore.new
    collector = StubCollector.new([
      { content: 'diff content', source: 'ruby/ruby:trunk/diff' },
      { content: 'article',      source: 'ruby/ruby:trunk/article' },
    ])
    orch = RubyKnowledgeDb::Orchestrator.new(store, [collector])
    results = orch.run(since: '2024-01-01', before: '2024-01-02')
    assert_equal 2, results[:stored]
    assert_equal 0, results[:skipped]
    assert_empty results[:errors]
  end

  def test_run_skips_duplicate
    store = StubStore.new
    def store.store(content, source:) = nil  # nil = skip
    collector = StubCollector.new([{ content: 'x', source: 's' }])
    orch = RubyKnowledgeDb::Orchestrator.new(store, [collector])
    results = orch.run(since: '2024-01-01', before: '2024-01-02')
    assert_equal 0, results[:stored]
    assert_equal 1, results[:skipped]
  end

  def test_run_captures_collector_errors
    store = StubStore.new
    bad_collector = Object.new
    def bad_collector.collect(since: nil, before: nil) = raise "boom"
    orch = RubyKnowledgeDb::Orchestrator.new(store, [bad_collector])
    results = orch.run(since: '2024-01-01', before: '2024-01-02')
    assert_equal 1, results[:errors].size
    assert_match(/boom/, results[:errors].first)
  end
end
