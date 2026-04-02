require 'test/unit'
require 'tmpdir'
require 'tempfile'

$LOAD_PATH.unshift File.join(__dir__, '..', 'lib')
require 'ruby_knowledge_store/store'
require 'ruby_knowledge_store/migrator'

# StubEmbedder: 実 ONNX モデルを使わない
class StubEmbedder
  VECTOR_SIZE = 768

  def embed(_text)
    Array.new(VECTOR_SIZE, 0.0)
  end
end

MIGRATIONS_DIR = File.expand_path('../../../migrations', __dir__)

class TestRubyKnowledgeStore < Test::Unit::TestCase
  def setup
    @tmpdir  = Dir.mktmpdir('ruby_knowledge_store_test')
    @db_path = File.join(@tmpdir, 'test.db')

    migrator = RubyKnowledgeStore::Migrator.new(@db_path, migrations_dir: MIGRATIONS_DIR)
    migrator.run

    @store = RubyKnowledgeStore::Store.new(@db_path, embedder: StubEmbedder.new)
  end

  def teardown
    @store.close
    FileUtils.remove_entry(@tmpdir)
  end

  # 1. store() で1件挿入できること
  def test_store_returns_id
    id = @store.store('Hello PicoRuby', source: 'picoruby/picoruby:trunk')
    assert_not_nil id
    assert_kind_of Integer, id
    assert id > 0
  end

  # 2. 同一 content を2回 store しても重複しないこと（冪等性）
  def test_store_idempotent
    id1 = @store.store('Duplicate content', source: 'picoruby/picoruby:trunk')
    id2 = @store.store('Duplicate content', source: 'picoruby/picoruby:trunk')

    assert_not_nil id1
    assert_nil id2, 'duplicate store should return nil'

    stats = @store.stats
    assert_equal 1, stats[:total]
  end

  # 3. stats() でカウントが返ること
  def test_stats_returns_counts
    @store.store('Content A', source: 'picoruby/picoruby:trunk')
    @store.store('Content B', source: 'ruby/ruby:trunk')
    @store.store('Content C', source: 'picoruby/picoruby:trunk')

    stats = @store.stats
    assert_equal 3, stats[:total]
    assert_equal 2, stats[:by_source]['picoruby/picoruby:trunk']
    assert_equal 1, stats[:by_source]['ruby/ruby:trunk']
  end

  # 4. Migrator.run で memories テーブルが存在すること
  def test_migrator_creates_memories_table
    # setup で既に migrator.run 済み
    # 別の DB で再確認
    tmpdb = File.join(@tmpdir, 'migrator_test.db')
    migrator = RubyKnowledgeStore::Migrator.new(tmpdb, migrations_dir: MIGRATIONS_DIR)
    migrator.run

    require 'sqlite3'
    db = SQLite3::Database.new(tmpdb)
    db.results_as_hash = true
    tables = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='memories'")
    db.close

    assert_equal 1, tables.size, 'memories table should exist after migration'
  end
end
