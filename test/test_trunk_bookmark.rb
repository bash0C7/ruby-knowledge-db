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
