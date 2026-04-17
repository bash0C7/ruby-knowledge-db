# frozen_string_literal: true

require_relative 'test_helper'
require 'rake'
require 'tmpdir'
require 'fileutils'
require 'sqlite3'
require 'sqlite_vec'
require_relative '../lib/ruby_knowledge_db/config'

# Integration test for the `rake db:delete_rdoc` contract:
# Deletes all rows in memories / memories_vec / memories_fts where
# source LIKE 'ruby/ruby:rdoc/trunk/%'. Non-rdoc rows are preserved.

class TestRakeDbDeleteRdoc < Test::Unit::TestCase
  def setup
    @dir     = Dir.mktmpdir('delete_rdoc')
    @db_path = File.join(@dir, 'test.db')
    # Build a minimal schema compatible with ruby-knowledge-store 001_schema.sql
    db = SQLite3::Database.new(@db_path)
    db.enable_load_extension(true); SqliteVec.load(db); db.enable_load_extension(false)
    db.execute_batch(<<~SQL)
      CREATE TABLE memories (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        content      TEXT    NOT NULL,
        source       TEXT    NOT NULL,
        content_hash TEXT    NOT NULL UNIQUE,
        embedding    BLOB,
        created_at   TEXT    NOT NULL
      );
      CREATE VIRTUAL TABLE memories_fts USING fts5(content, content='memories', content_rowid='id', tokenize='trigram');
      CREATE VIRTUAL TABLE memories_vec USING vec0(memory_id INTEGER PRIMARY KEY, embedding FLOAT[768]);
      CREATE TRIGGER memories_ai AFTER INSERT ON memories BEGIN
        INSERT INTO memories_fts(rowid, content) VALUES (new.id, new.content);
      END;
      CREATE TRIGGER memories_ad AFTER DELETE ON memories BEGIN
        INSERT INTO memories_fts(memories_fts, rowid, content) VALUES('delete', old.id, old.content);
      END;
    SQL
    # Seed 3 rows: 2 rdoc + 1 rurema
    emb = Array.new(768, 0.1).pack('f*')
    db.execute("INSERT INTO memories(content, source, content_hash, created_at) VALUES(?, ?, ?, datetime('now'))",
      ['# ARGF', 'ruby/ruby:rdoc/trunk/ARGF', 'hash_argf'])
    db.execute("INSERT INTO memories_vec(memory_id, embedding) VALUES(?, ?)", [db.last_insert_row_id, emb])
    db.execute("INSERT INTO memories(content, source, content_hash, created_at) VALUES(?, ?, ?, datetime('now'))",
      ['# Addrinfo', 'ruby/ruby:rdoc/trunk/Addrinfo', 'hash_addrinfo'])
    db.execute("INSERT INTO memories_vec(memory_id, embedding) VALUES(?, ?)", [db.last_insert_row_id, emb])
    db.execute("INSERT INTO memories(content, source, content_hash, created_at) VALUES(?, ?, ?, datetime('now'))",
      ['rurema content', 'rurema/doctree:ruby4.0/core', 'hash_rurema'])
    db.execute("INSERT INTO memories_vec(memory_id, embedding) VALUES(?, ?)", [db.last_insert_row_id, emb])
    db.close
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def count_rows
    db = SQLite3::Database.new(@db_path)
    db.enable_load_extension(true); SqliteVec.load(db); db.enable_load_extension(false)
    m   = db.get_first_value('SELECT count(*) FROM memories')
    v   = db.get_first_value('SELECT count(*) FROM memories_vec')
    fts = db.get_first_value('SELECT count(*) FROM memories_fts')
    db.close
    [m, v, fts]
  end

  def test_delete_rdoc_removes_rdoc_rows_only
    # Load the Rake file so that the task is registered
    unless Rake::Task.task_defined?('db:delete_rdoc') || Rake::Task.task_defined?('db:stats')
      Rake.application.init
      Rake.application.load_rakefile
    end
    # Stub ensure_write_host! for test env
    RubyKnowledgeDb::Config.define_singleton_method(:ensure_write_host!) { nil }
    # Stub db_path to our test DB via Config load
    original = RubyKnowledgeDb::Config.method(:load)
    db_path = @db_path
    RubyKnowledgeDb::Config.define_singleton_method(:load) { { 'db_path' => db_path } }

    before = count_rows
    assert_equal [3, 3, 3], before

    Rake::Task['db:delete_rdoc'].reenable
    Rake::Task['db:delete_rdoc'].invoke

    after = count_rows
    assert_equal [1, 1, 1], after, "only rurema row should remain"

    # Confirm remaining row is rurema
    db = SQLite3::Database.new(@db_path)
    source = db.get_first_value("SELECT source FROM memories")
    db.close
    assert_equal 'rurema/doctree:ruby4.0/core', source
  ensure
    RubyKnowledgeDb::Config.define_singleton_method(:load, &original) if original
  end
end
