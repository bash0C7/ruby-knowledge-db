require 'sqlite3'
require 'sqlite_vec'
require 'json'

module ChiebukuroMcp
  class SchemaResource
    def initialize(db_path)
      @db_path = db_path
    end

    def call
      db = open_db
      meta = read_meta(db)
      tables = read_tables(db)
      build_schema(meta, tables)
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

    def read_meta(db)
      has_meta = db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='_sqlite_mcp_meta'"
      ).any?
      return {} unless has_meta

      db.execute('SELECT object_type, object_name, description FROM _sqlite_mcp_meta')
        .each_with_object({}) do |row, h|
          h["#{row['object_type']}:#{row['object_name']}"] = row['description']
        end
    end

    def read_tables(db)
      db.execute(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
      )
    end

    def build_schema(meta, tables)
      lines = []
      db_desc = meta['db:ruby_knowledge'] || meta.values.first
      lines << "# Database Schema"
      lines << "## Description: #{db_desc}" if db_desc
      lines << ""

      tables.each do |t|
        name = t['name']
        lines << "## Table: #{name}"
        desc = meta["table:#{name}"]
        lines << "Description: #{desc}" if desc
        lines << "```sql"
        lines << t['sql']
        lines << "```"
        lines << ""
      end

      lines.join("\n")
    end
  end
end
