require 'sqlite3'
require 'sqlite_vec'
require 'json'

module ChiebukuroMcp
  class SemanticSearchTool
    def initialize(db_path, embedder:)
      @db_path  = db_path
      @embedder = embedder
    end

    def call(query:, limit: 5)
      embedding = @embedder.embed(query)
      blob = embedding.pack('f*')
      db = open_db
      rows = db.execute(
        "SELECT m.content, m.source, v.distance
         FROM memories_vec v
         JOIN memories m ON m.id = v.memory_id
         WHERE v.embedding MATCH ? AND k = ?
         ORDER BY v.distance",
        [blob, limit]
      )
      JSON.generate(rows.map { |r|
        { 'content' => r['content'], 'source' => r['source'], 'distance' => r['distance'] }
      })
    rescue SQLite3::Exception => e
      raise "SQLite error: #{e.message}"
    ensure
      db&.close
    end

    private

    def open_db
      db = SQLite3::Database.new(@db_path, readonly: true)
      db.results_as_hash = true
      db.enable_load_extension(true)
      SqliteVec.load(db)
      db.enable_load_extension(false)
      db
    end
  end
end
