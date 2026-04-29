# frozen_string_literal: true

require_relative '../test/test_helper'
require_relative '../lib/ruby_knowledge_db/pipeline_plan'
require 'date'
require 'json'

class TestPipelinePlan < Test::Unit::TestCase
  TRUNK_KEYS = %w[picoruby_trunk cruby_trunk mruby_trunk].freeze

  def cfg
    {
      'sources' => {
        'picoruby_trunk' => {},
        'cruby_trunk'    => {},
        'mruby_trunk'    => {}
      },
      'esa' => {
        'team' => 'my-team',
        'sources' => {
          'picoruby_trunk' => { 'category' => 'production/picoruby/trunk-changes' },
          'cruby_trunk'    => { 'category' => 'production/cruby/trunk-changes' },
          'mruby_trunk'    => { 'category' => 'production/mruby/trunk-changes' }
        }
      }
    }
  end

  def clean_bookmark
    {
      'picoruby_trunk' => { 'last_started_before' => '2026-04-28', 'last_completed_before' => '2026-04-28' },
      'cruby_trunk'    => { 'last_started_before' => '2026-04-28', 'last_completed_before' => '2026-04-28' },
      'mruby_trunk'    => { 'last_started_before' => '2026-04-28', 'last_completed_before' => '2026-04-28' }
    }
  end

  def today
    Date.new(2026, 4, 29)
  end

  def empty_searcher
    StubEsaSearcher.new
  end

  def build_plan(**overrides)
    RubyKnowledgeDb::PipelinePlan.new(
      cfg:           overrides.fetch(:cfg, cfg),
      since:         overrides[:since],
      before:        overrides[:before],
      bookmark_data: overrides.fetch(:bookmark_data, clean_bookmark),
      today:         overrides.fetch(:today, today),
      esa_searcher:  overrides.fetch(:esa_searcher, empty_searcher)
    )
  end

  # 1. SINCE が bookmark floor から計算される
  def test_since_from_bookmark_floor
    h = build_plan.to_h
    assert_equal '2026-04-28', h['since']
    assert_equal 'bookmark_floor', h['since_source']
    assert_equal '2026-04-29', h['before']
  end

  # 2. floor が nil（一部欠落）→ fallback_yesterday + 矛盾
  def test_since_fallback_to_yesterday_when_floor_nil
    bm = { 'picoruby_trunk' => { 'last_completed_before' => '2026-04-28' } }
    h = build_plan(bookmark_data: bm).to_h
    assert_equal '2026-04-28', h['since']
    assert_equal 'fallback_yesterday', h['since_source']
    assert_false h['consistent']
  end

  # 3. SINCE 明示 override
  def test_since_explicit_override
    h = build_plan(since: '2026-04-25').to_h
    assert_equal '2026-04-25', h['since']
    assert_equal 'explicit', h['since_source']
  end

  # 4. クリーンな状態 → consistent == true
  def test_consistent_when_clean
    plan = build_plan
    assert_true plan.consistent?
    assert_equal [], plan.contradiction_reasons
  end

  # 5. WIP 残骸あり → 矛盾
  def test_inconsistent_when_wip
    bm = clean_bookmark.merge(
      'picoruby_trunk' => { 'last_started_before' => '2026-04-29', 'last_completed_before' => '2026-04-28' }
    )
    plan = build_plan(bookmark_data: bm)
    assert_false plan.consistent?
    assert_equal ['picoruby_trunk'], plan.to_h['wip_sources']
    assert_match(/WIP/, plan.contradiction_reasons.join("\n"))
  end

  # 6. esa 衝突あり → 矛盾
  def test_inconsistent_when_esa_conflict
    posts = {
      ['my-team', 'production/picoruby/trunk-changes/2026/04/28', '2026-04-28-picoruby-trunk-changes'] => [
        { 'number' => 999, 'name' => '2026-04-28-picoruby-trunk-changes', 'full_name' => 'x' }
      ]
    }
    plan = build_plan(esa_searcher: StubEsaSearcher.new(posts))
    assert_false plan.consistent?
    assert_equal 1, plan.to_h['esa_conflicts'].size
    assert_match(/esa 衝突/, plan.contradiction_reasons.join("\n"))
  end

  # 7. bookmark 全欠落（初回実行扱い）→ 矛盾
  def test_inconsistent_when_no_bookmarks
    plan = build_plan(bookmark_data: {})
    h = plan.to_h
    assert_equal 'fallback_yesterday', h['since_source']
    assert_false plan.consistent?
  end

  # 8. BEFORE が未来日付 → 矛盾
  def test_before_future_flag
    plan = build_plan(before: '2026-05-01')
    h = plan.to_h
    assert_true h['before_is_future']
    assert_false plan.consistent?
  end

  # 9. WIP が複数ソース → multiple_wip + 矛盾、ただし WIP reason は単一（重複しない）
  def test_multiple_wip_flag
    bm = {
      'picoruby_trunk' => { 'last_started_before' => '2026-04-29', 'last_completed_before' => '2026-04-28' },
      'cruby_trunk'    => { 'last_started_before' => '2026-04-29', 'last_completed_before' => '2026-04-28' },
      'mruby_trunk'    => { 'last_started_before' => '2026-04-28', 'last_completed_before' => '2026-04-28' }
    }
    plan = build_plan(bookmark_data: bm)
    h = plan.to_h
    assert_true h['multiple_wip']
    assert_equal 2, h['wip_sources'].size
    wip_reasons = plan.contradiction_reasons.grep(/WIP/)
    assert_equal 1, wip_reasons.size, "WIP reason should appear exactly once even when multiple sources are WIP"
  end

  # 13. no_bookmark_sources は contradiction_reasons に明示される（JSON dump を読まなくて済む）
  def test_no_bookmark_sources_surfaced_as_reason
    bm = clean_bookmark.reject { |k, _| k == 'cruby_trunk' }
    plan = build_plan(bookmark_data: bm)
    assert_includes plan.to_h['no_bookmark_sources'], 'cruby_trunk'
    assert_match(/bookmark 欠落.*cruby_trunk/, plan.contradiction_reasons.join("\n"))
  end

  # 10. to_h は JSON serializable
  def test_to_h_json_serializable
    plan = build_plan
    assert_nothing_raised { JSON.generate(plan.to_h) }
  end

  # 11. SINCE >= BEFORE → 矛盾
  def test_inconsistent_when_since_geq_before
    plan = build_plan(since: '2026-04-29')
    assert_false plan.consistent?
    assert_match(/SINCE.*BEFORE/, plan.contradiction_reasons.join("\n"))
  end

  # 12. trunk_sources Hash に各 source の status が入る
  def test_trunk_sources_in_hash
    h = build_plan.to_h
    assert_equal TRUNK_KEYS.sort, h['trunk_sources'].keys.sort
    h['trunk_sources'].each_value do |s|
      assert_equal '2026-04-28', s['last_completed_before']
      assert_false s['wip']
    end
  end
end
