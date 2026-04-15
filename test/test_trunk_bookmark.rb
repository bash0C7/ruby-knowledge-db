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
end
