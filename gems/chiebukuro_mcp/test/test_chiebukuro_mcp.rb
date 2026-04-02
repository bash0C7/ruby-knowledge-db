require_relative '../../../test/test_helper'
require_relative '../lib/chiebukuro_mcp/query_tool'
require_relative '../lib/chiebukuro_mcp/schema_resource'
require_relative '../lib/chiebukuro_mcp/semantic_search_tool'
require_relative '../../ruby_knowledge_store/lib/ruby_knowledge_store/migrator'
require_relative '../../ruby_knowledge_store/lib/ruby_knowledge_store/store'
require 'tempfile'

class TestQueryTool < Test::Unit::TestCase
  def setup
    @tmpfile = Tempfile.new(['test_query_tool', '.db'])
    @db_path = @tmpfile.path
    @tmpfile.close

    migrations_dir = File.expand_path('../../../migrations', __dir__)
    RubyKnowledgeStore::Migrator.new(@db_path, migrations_dir: migrations_dir).run
  end

  def teardown
    @tmpfile.unlink
  end

  def test_select_is_allowed
    tool = ChiebukuroMcp::QueryTool.new(@db_path)
    result = tool.call(sql: 'SELECT 1 AS n')
    parsed = JSON.parse(result)
    assert_equal 1, parsed.length
    assert_equal 1, parsed.first['n']
  end

  def test_select_memories_returns_empty_array
    tool = ChiebukuroMcp::QueryTool.new(@db_path)
    result = tool.call(sql: 'SELECT * FROM memories')
    parsed = JSON.parse(result)
    assert_equal [], parsed
  end

  def test_with_clause_is_allowed
    tool = ChiebukuroMcp::QueryTool.new(@db_path)
    result = tool.call(sql: 'WITH nums AS (SELECT 42 AS n) SELECT n FROM nums')
    parsed = JSON.parse(result)
    assert_equal 42, parsed.first['n']
  end

  def test_insert_raises_argument_error
    tool = ChiebukuroMcp::QueryTool.new(@db_path)
    assert_raise(ArgumentError) do
      tool.call(sql: 'INSERT INTO memories (content, source, content_hash, created_at) VALUES ("x","s","h","2024-01-01")')
    end
  end

  def test_update_raises_argument_error
    tool = ChiebukuroMcp::QueryTool.new(@db_path)
    assert_raise(ArgumentError) do
      tool.call(sql: 'UPDATE memories SET content = "y" WHERE id = 1')
    end
  end

  def test_delete_raises_argument_error
    tool = ChiebukuroMcp::QueryTool.new(@db_path)
    assert_raise(ArgumentError) do
      tool.call(sql: 'DELETE FROM memories WHERE id = 1')
    end
  end

  def test_drop_raises_argument_error
    tool = ChiebukuroMcp::QueryTool.new(@db_path)
    assert_raise(ArgumentError) do
      tool.call(sql: 'DROP TABLE memories')
    end
  end
end

class TestSchemaResourceWithMeta < Test::Unit::TestCase
  def setup
    @tmpfile = Tempfile.new(['test_schema_resource_with_meta', '.db'])
    @db_path = @tmpfile.path
    @tmpfile.close

    migrations_dir = File.expand_path('../../../migrations', __dir__)
    RubyKnowledgeStore::Migrator.new(@db_path, migrations_dir: migrations_dir).run
  end

  def teardown
    @tmpfile.unlink
  end

  def test_schema_contains_db_description
    resource = ChiebukuroMcp::SchemaResource.new(@db_path)
    schema = resource.call
    assert_include schema, '# Database Schema'
    assert_include schema, '## Description:'
    assert_include schema, 'PicoRuby'
  end

  def test_schema_contains_memories_table
    resource = ChiebukuroMcp::SchemaResource.new(@db_path)
    schema = resource.call
    assert_include schema, '## Table: memories'
  end

  def test_schema_contains_meta_table_description
    resource = ChiebukuroMcp::SchemaResource.new(@db_path)
    schema = resource.call
    assert_include schema, '_sqlite_mcp_meta'
  end

  def test_schema_contains_sql_block
    resource = ChiebukuroMcp::SchemaResource.new(@db_path)
    schema = resource.call
    assert_include schema, '```sql'
    assert_include schema, '```'
  end
end

class TestSemanticSearchTool < Test::Unit::TestCase
  def setup
    @tmpfile = Tempfile.new(['test_semantic_search', '.db'])
    @db_path = @tmpfile.path
    @tmpfile.close

    migrations_dir = File.expand_path('../../../migrations', __dir__)
    RubyKnowledgeStore::Migrator.new(@db_path, migrations_dir: migrations_dir).run

    @stub_embedder = StubEmbedder.new
    store = RubyKnowledgeStore::Store.new(@db_path, embedder: @stub_embedder)
    store.store('PicoRuby の GPIO クラス', source: 'picoruby/picoruby:docs/gpio')
    store.store('CRuby の Array クラス', source: 'rurema/doctree:ruby3.3/array')
    store.store('mruby の Hash クラス', source: 'rurema/doctree:ruby3.3/hash')
    store.close
  end

  def teardown
    @tmpfile.unlink
  end

  def test_semantic_search_returns_results_with_expected_keys
    tool = ChiebukuroMcp::SemanticSearchTool.new(@db_path, embedder: @stub_embedder)
    result = tool.call(query: 'GPIO')
    parsed = JSON.parse(result)
    assert parsed.length > 0
    first = parsed.first
    assert first.key?('content')
    assert first.key?('source')
    assert first.key?('distance')
  end

  def test_semantic_search_limit_respected
    tool = ChiebukuroMcp::SemanticSearchTool.new(@db_path, embedder: @stub_embedder)
    result = tool.call(query: 'Ruby', limit: 2)
    parsed = JSON.parse(result)
    assert_equal 2, parsed.length
  end

  def test_semantic_search_default_limit_is_five
    store = RubyKnowledgeStore::Store.new(@db_path, embedder: @stub_embedder)
    store.store('record 4', source: 'test/4')
    store.store('record 5', source: 'test/5')
    store.store('record 6', source: 'test/6')
    store.store('record 7', source: 'test/7')
    store.close

    tool = ChiebukuroMcp::SemanticSearchTool.new(@db_path, embedder: @stub_embedder)
    result = tool.call(query: 'Ruby')
    parsed = JSON.parse(result)
    assert_equal 5, parsed.length
  end
end

class TestSchemaResourceWithoutMeta < Test::Unit::TestCase
  def setup
    @tmpfile = Tempfile.new(['test_schema_resource_no_meta', '.db'])
    @db_path = @tmpfile.path
    @tmpfile.close

    # _sqlite_mcp_meta なしの最小限 DB（memories テーブルのみ）
    require 'sqlite3'
    require 'sqlite_vec'
    db = SQLite3::Database.new(@db_path)
    db.enable_load_extension(true)
    SqliteVec.load(db)
    db.enable_load_extension(false)
    db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS memories (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        content      TEXT    NOT NULL,
        source       TEXT    NOT NULL,
        content_hash TEXT    NOT NULL UNIQUE,
        embedding    BLOB,
        created_at   TEXT    NOT NULL
      )
    SQL
    db.close
  end

  def teardown
    @tmpfile.unlink
  end

  def test_schema_without_meta_still_returns_tables
    resource = ChiebukuroMcp::SchemaResource.new(@db_path)
    schema = resource.call
    assert_include schema, '# Database Schema'
    assert_include schema, '## Table: memories'
  end

  def test_schema_without_meta_has_no_description_line
    resource = ChiebukuroMcp::SchemaResource.new(@db_path)
    schema = resource.call
    # _sqlite_mcp_meta がないので Description: 行は出ない
    assert_not_include schema, '## Description:'
  end
end
