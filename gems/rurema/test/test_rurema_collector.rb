require_relative '../../../test/test_helper'
require_relative '../lib/rurema/collector'

FakeClassEntry = Struct.new(:name, :source)

class FakeLibraryEntry
  attr_reader :name, :source, :classes

  def initialize(name, source, classes = [])
    @name    = name
    @source  = source
    @classes = classes
  end
end

class StubDoctreeManager
  def sync; end
  def rd_files(_version) = ['/fake/src/yaml.rd', '/fake/src/json.rd']
end

class StubRDParser
  FIXTURES = {
    '/fake/src/yaml.rd' => FakeLibraryEntry.new(
      'yaml',
      "= library yaml\nyaml ライブラリ\n",
      [FakeClassEntry.new('YAML', "= class YAML\nYAML クラス\n")]
    ),
    '/fake/src/json.rd' => FakeLibraryEntry.new(
      'json',
      "= library json\njson ライブラリ\n",
      []
    )
  }

  def parse(path, _version) = FIXTURES[path]
end

class StubRDParserReturnsNil
  def parse(_path, _version) = nil
end

class StubRDParserRaises
  def parse(_path, _version)
    raise 'parse error'
  end
end

class StubRDParserEmptySource
  def parse(_path, _version)
    FakeLibraryEntry.new('empty_lib', '   ', [])
  end
end

class TestRuremaCollector < Test::Unit::TestCase
  def setup
    @collector = Rurema::Collector.new(
      { 'doctree_path' => '/fake/doctree', 'version' => '3.3.0' },
      doctree_manager: StubDoctreeManager.new,
      rd_parser:       StubRDParser.new
    )
  end

  def test_collect_returns_library_and_class_entries
    results = @collector.collect
    # yaml_lib + yaml_class + json_lib = 3 件
    assert_equal 3, results.size
  end

  def test_library_source_format
    results = @collector.collect
    yaml_lib = results.find { |r| r[:source] == 'rurema/doctree:ruby3.3/yaml' }
    assert_not_nil yaml_lib
    assert_include yaml_lib[:content], 'yaml ライブラリ'
  end

  def test_class_source_format
    results = @collector.collect
    yaml_cls = results.find { |r| r[:source] == 'rurema/doctree:ruby3.3/yaml#YAML' }
    assert_not_nil yaml_cls
    assert_include yaml_cls[:content], 'YAML クラス'
  end

  def test_since_is_ignored
    results_without = @collector.collect
    results_with    = @collector.collect(since: '2024-01-01T00:00:00Z')
    assert_equal results_without.size, results_with.size
  end

  def test_nil_from_parser_is_skipped
    collector = Rurema::Collector.new(
      { 'doctree_path' => '/fake', 'version' => '3.3.0' },
      doctree_manager: StubDoctreeManager.new,
      rd_parser:       StubRDParserReturnsNil.new
    )
    assert_empty collector.collect
  end

  def test_parse_error_is_skipped
    collector = Rurema::Collector.new(
      { 'doctree_path' => '/fake', 'version' => '3.3.0' },
      doctree_manager: StubDoctreeManager.new,
      rd_parser:       StubRDParserRaises.new
    )
    assert_nothing_raised { collector.collect }
    assert_empty collector.collect
  end

  def test_empty_source_string_is_not_collected
    collector = Rurema::Collector.new(
      { 'doctree_path' => '/fake', 'version' => '3.3.0' },
      doctree_manager: StubDoctreeManager.new,
      rd_parser:       StubRDParserEmptySource.new
    )
    assert_empty collector.collect
  end
end
