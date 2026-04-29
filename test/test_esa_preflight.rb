# frozen_string_literal: true

require_relative '../test/test_helper'
require_relative '../lib/ruby_knowledge_db/esa_preflight'
require 'stringio'

class TestEsaPreflight < Test::Unit::TestCase
  def cfg
    {
      'sources' => {
        'picoruby_trunk' => {},
        'cruby_trunk'    => {}
      },
      'esa' => {
        'team' => 'my-team',
        'sources' => {
          'picoruby_trunk' => { 'category' => 'production/picoruby/trunk-changes' },
          'cruby_trunk'    => { 'category' => 'production/cruby/trunk-changes' }
        }
      }
    }
  end

  def test_conflicts_empty_when_no_existing_posts
    searcher = StubEsaSearcher.new
    result = RubyKnowledgeDb::EsaPreflight.conflicts(
      cfg: cfg, since: '2026-04-16', before: '2026-04-17', searcher: searcher
    )
    assert_equal [], result
  end

  def test_conflicts_detects_exact_name_match
    posts = {
      ['my-team', 'production/picoruby/trunk-changes/2026/04/16', '2026-04-16-picoruby-trunk-changes'] => [
        { 'number' => 131,
          'name'   => '2026-04-16-picoruby-trunk-changes',
          'full_name' => 'production/picoruby/trunk-changes/2026/04/16/2026-04-16-picoruby-trunk-changes' }
      ]
    }
    searcher = StubEsaSearcher.new(posts)
    result = RubyKnowledgeDb::EsaPreflight.conflicts(
      cfg: cfg, since: '2026-04-16', before: '2026-04-17', searcher: searcher
    )
    assert_equal 1, result.size
    assert_equal 'picoruby_trunk', result.first[:key]
    assert_equal '2026-04-16',     result.first[:date]
    assert_equal 131,              result.first[:posts].first['number']
  end

  def test_conflicts_detects_paren_suffix_dup
    posts = {
      ['my-team', 'production/picoruby/trunk-changes/2026/04/16', '2026-04-16-picoruby-trunk-changes'] => [
        { 'number' => 135,
          'name'   => '2026-04-16-picoruby-trunk-changes (1)',
          'full_name' => 'production/picoruby/trunk-changes/2026/04/16/2026-04-16-picoruby-trunk-changes (1)' }
      ]
    }
    searcher = StubEsaSearcher.new(posts)
    result = RubyKnowledgeDb::EsaPreflight.conflicts(
      cfg: cfg, since: '2026-04-16', before: '2026-04-17', searcher: searcher
    )
    assert_equal 1, result.size
    assert_equal 135, result.first[:posts].first['number']
  end

  def test_conflicts_ignores_non_matching_names
    posts = {
      ['my-team', 'production/picoruby/trunk-changes/2026/04/16', '2026-04-16-picoruby-trunk-changes'] => [
        { 'number' => 999, 'name' => 'some-other-post', 'full_name' => 'x' }
      ]
    }
    searcher = StubEsaSearcher.new(posts)
    result = RubyKnowledgeDb::EsaPreflight.conflicts(
      cfg: cfg, since: '2026-04-16', before: '2026-04-17', searcher: searcher
    )
    assert_equal [], result
  end

  def test_conflicts_iterates_multi_day_range
    posts = {
      ['my-team', 'production/picoruby/trunk-changes/2026/04/15', '2026-04-15-picoruby-trunk-changes'] => [
        { 'number' => 101, 'name' => '2026-04-15-picoruby-trunk-changes', 'full_name' => 'x' }
      ],
      ['my-team', 'production/picoruby/trunk-changes/2026/04/16', '2026-04-16-picoruby-trunk-changes'] => [
        { 'number' => 102, 'name' => '2026-04-16-picoruby-trunk-changes', 'full_name' => 'x' }
      ]
    }
    searcher = StubEsaSearcher.new(posts)
    result = RubyKnowledgeDb::EsaPreflight.conflicts(
      cfg: cfg, since: '2026-04-15', before: '2026-04-17', searcher: searcher
    )
    dates = result.map { |r| r[:date] }.sort
    assert_equal ['2026-04-15', '2026-04-16'], dates
  end

  def test_conflicts_skips_keys_without_esa_category
    cfg_partial = {
      'sources' => { 'picoruby_trunk' => {} },
      'esa'     => { 'team' => 'my-team', 'sources' => {} }
    }
    searcher = StubEsaSearcher.new
    result = RubyKnowledgeDb::EsaPreflight.conflicts(
      cfg: cfg_partial, since: '2026-04-16', before: '2026-04-17', searcher: searcher
    )
    assert_equal [], result
    assert_equal 0, searcher.calls.size
  end

  def test_conflicts_skips_non_trunk_keys
    cfg_mixed = {
      'sources' => {
        'picoruby_trunk' => {},
        'rurema'         => {},
        'picoruby_docs'  => {}
      },
      'esa' => {
        'team' => 'my-team',
        'sources' => {
          'picoruby_trunk' => { 'category' => 'x/picoruby' }
        }
      }
    }
    searcher = StubEsaSearcher.new
    RubyKnowledgeDb::EsaPreflight.conflicts(
      cfg: cfg_mixed, since: '2026-04-16', before: '2026-04-17', searcher: searcher
    )
    assert_equal 1, searcher.calls.size
    assert_equal 'x/picoruby/2026/04/16', searcher.calls.first[:category]
  end

  def test_conflicts_no_esa_config_returns_empty
    cfg_no_esa = { 'sources' => { 'picoruby_trunk' => {} } }
    searcher = StubEsaSearcher.new
    result = RubyKnowledgeDb::EsaPreflight.conflicts(
      cfg: cfg_no_esa, since: '2026-04-16', before: '2026-04-17', searcher: searcher
    )
    assert_equal [], result
  end

  def test_check_conflicts_bang_raises_system_exit_on_conflict
    posts = {
      ['my-team', 'production/picoruby/trunk-changes/2026/04/16', '2026-04-16-picoruby-trunk-changes'] => [
        { 'number' => 131, 'name' => '2026-04-16-picoruby-trunk-changes', 'full_name' => 'x' }
      ]
    }
    searcher = StubEsaSearcher.new(posts)
    orig_stderr = $stderr
    $stderr = StringIO.new
    begin
      assert_raise(SystemExit) do
        RubyKnowledgeDb::EsaPreflight.check_conflicts!(
          cfg: cfg, since: '2026-04-16', before: '2026-04-17', searcher: searcher
        )
      end
      assert_match(/esa preflight/, $stderr.string)
      assert_match(/#131/, $stderr.string)
    ensure
      $stderr = orig_stderr
    end
  end

  def test_check_conflicts_bang_noop_when_clean
    searcher = StubEsaSearcher.new
    assert_nothing_raised do
      RubyKnowledgeDb::EsaPreflight.check_conflicts!(
        cfg: cfg, since: '2026-04-16', before: '2026-04-17', searcher: searcher
      )
    end
  end
end
