require 'sqlite3'
require 'sqlite_vec'

module RubyKnowledgeStore
  class Migrator
    def initialize(db_path, migrations_dir:)
      @db_path        = db_path
      @migrations_dir = migrations_dir
    end

    def run
      db = SQLite3::Database.new(@db_path)
      db.enable_load_extension(true)
      SqliteVec.load(db)
      db.enable_load_extension(false)

      sql_files = Dir[File.join(@migrations_dir, '*.sql')].sort
      sql_files.each do |f|
        sql = File.read(f)
        # execute_batch で複数文を一括実行（BEGIN...ENDのTRIGGERも正しく処理）
        db.execute_batch(sql)
      end
    ensure
      db&.close
    end
  end
end
