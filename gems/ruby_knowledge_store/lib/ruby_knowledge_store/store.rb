require 'sqlite3'
require 'sqlite_vec'
require 'digest'
require 'time'

module RubyKnowledgeStore
  class Store
    def initialize(db_path, embedder:)
      @db = SQLite3::Database.new(db_path)
      @db.results_as_hash = true
      @db.busy_timeout = 5000
      @embedder = embedder
      setup_extensions
      setup_pragmas
    end

    def close
      @db.close
    end

    # content_hash が既存なら skip（冪等）
    # @return [Integer, nil] 挿入した id、スキップなら nil
    def store(content, source:)
      content_hash = Digest::SHA256.hexdigest(content)
      existing = @db.execute(
        'SELECT id FROM memories WHERE content_hash = ?', [content_hash]
      ).first
      return nil if existing

      created_at = Time.now.iso8601
      @db.execute(
        'INSERT INTO memories (content, source, content_hash, created_at) VALUES (?, ?, ?, ?)',
        [content, source, content_hash, created_at]
      )
      id = @db.last_insert_row_id

      embedding      = @embedder.embed(content)
      embedding_blob = embedding.pack('f*')
      @db.execute(
        'INSERT INTO memories_vec(memory_id, embedding) VALUES (?, ?)',
        [id, embedding_blob]
      )

      id
    end

    def stats
      total     = @db.execute('SELECT COUNT(*) as c FROM memories').first['c']
      by_source = @db.execute('SELECT source, COUNT(*) as c FROM memories GROUP BY source')
                     .each_with_object({}) { |r, h| h[r['source']] = r['c'] }
      { total: total, by_source: by_source }
    end

    private

    def setup_extensions
      @db.enable_load_extension(true)
      SqliteVec.load(@db)
      @db.enable_load_extension(false)
    end

    def setup_pragmas
      @db.execute('PRAGMA journal_mode=WAL')
      @db.execute('PRAGMA synchronous=NORMAL')
    end
  end
end
