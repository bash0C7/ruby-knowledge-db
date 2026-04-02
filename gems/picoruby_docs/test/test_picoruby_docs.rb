require_relative '../../../test/test_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/picoruby_docs/rbs_parser'
require_relative '../lib/picoruby_docs/readme_parser'
require_relative '../lib/picoruby_docs/collector'

# ---- RbsParser tests ----

class TestRbsParser < Test::Unit::TestCase
  RBS_FIXTURE = <<~RBS
    # @sidebar io_peripheral
    class GPIO
      IN:  Integer
      OUT: Integer

      attr_reader pin: Integer

      def initialize: (Integer pin, Integer flags) -> void
      def read: () -> Integer
      def write: (Integer value) -> 0
      def self.read_at: (Integer pin) -> Integer
    end
  RBS

  def setup
    @parser = PicorubyDocs::RbsParser.new
  end

  def test_parse_class_name
    result = @parser.parse(RBS_FIXTURE)
    assert_equal 'GPIO', result.class_name
  end

  def test_parse_sidebar_tag
    result = @parser.parse(RBS_FIXTURE)
    assert_equal 'io_peripheral', result.sidebar_tag
  end

  def test_parse_constants
    result = @parser.parse(RBS_FIXTURE)
    assert_include result.constants, 'IN'
    assert_include result.constants, 'OUT'
  end

  def test_parse_instance_methods
    result = @parser.parse(RBS_FIXTURE)
    assert result.instance_methods.any? { |m| m.start_with?('read') }
    assert result.instance_methods.any? { |m| m.start_with?('write') }
  end

  def test_parse_class_methods
    result = @parser.parse(RBS_FIXTURE)
    assert result.class_methods.any? { |m| m.start_with?('read_at') }
  end

  def test_to_doc_contains_class_name
    result = @parser.parse(RBS_FIXTURE)
    doc = result.to_doc
    assert_include doc, 'GPIO'
    assert_include doc, 'Instance Methods'
  end

  def test_parse_empty_rbs_does_not_raise
    result = @parser.parse('')
    assert_equal '(unknown)', result.class_name
  end
end

# ---- ReadmeParser tests ----

class TestReadmeParser < Test::Unit::TestCase
  def setup
    @parser = PicorubyDocs::ReadmeParser.new
  end

  def test_parse_returns_stripped_content
    result = @parser.parse("  # picoruby-gpio\n\nGPIO library  ")
    assert_equal "# picoruby-gpio\n\nGPIO library", result
  end

  def test_parse_empty_returns_nil
    assert_nil @parser.parse('   ')
  end
end

# ---- Collector tests ----

class FakeGemDocCollector
  def initialize(gem_dir)
    @gem_name = File.basename(gem_dir)
  end

  def collect
    ["# #{@gem_name} doc content"]
  end
end

class TestPicorubyDocsCollector < Test::Unit::TestCase
  def test_collect_returns_source_with_gem_name
    Dir.mktmpdir do |tmpdir|
      gem_dir = File.join(tmpdir, 'mrbgems', 'picoruby-gpio')
      FileUtils.mkdir_p(gem_dir)

      collector = PicorubyDocs::Collector.new(
        { 'repo_path' => tmpdir },
        gem_doc_collector_class: FakeGemDocCollector
      )
      results = collector.collect

      assert_equal 1, results.size
      assert_equal 'picoruby/picoruby:docs/picoruby-gpio', results[0][:source]
      assert_equal '# picoruby-gpio doc content',          results[0][:content]
    end
  end

  def test_collect_ignores_since_parameter
    Dir.mktmpdir do |tmpdir|
      gem_dir = File.join(tmpdir, 'mrbgems', 'picoruby-adc')
      FileUtils.mkdir_p(gem_dir)

      collector = PicorubyDocs::Collector.new(
        { 'repo_path' => tmpdir },
        gem_doc_collector_class: FakeGemDocCollector
      )
      results_with_since    = collector.collect(since: '2020-01-01T00:00:00Z')
      results_without_since = collector.collect

      assert_equal results_with_since.size, results_without_since.size
    end
  end

  def test_collect_empty_when_no_mrbgems
    Dir.mktmpdir do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, 'mrbgems'))

      collector = PicorubyDocs::Collector.new(
        { 'repo_path' => tmpdir },
        gem_doc_collector_class: FakeGemDocCollector
      )
      assert_empty collector.collect
    end
  end

  def test_skips_non_picoruby_dirs
    Dir.mktmpdir do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, 'mrbgems', 'picoruby-gpio'))
      FileUtils.mkdir_p(File.join(tmpdir, 'mrbgems', 'mruby-file-stat'))

      collector = PicorubyDocs::Collector.new(
        { 'repo_path' => tmpdir },
        gem_doc_collector_class: FakeGemDocCollector
      )
      results = collector.collect

      assert_equal 1, results.size
      assert_equal 'picoruby/picoruby:docs/picoruby-gpio', results[0][:source]
    end
  end
end
