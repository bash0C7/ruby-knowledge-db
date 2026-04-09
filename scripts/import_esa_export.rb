# frozen_string_literal: true

# Usage:
#   APP_ENV=production EXPORT_DIR=/path/to/export SHORT_NAME=picoruby bundle exec ruby scripts/import_esa_export.rb
#
# Imports esa-exported MD files into:
#   1. SQLite DB (with embedding, source: picoruby/picoruby:trunk/article)
#   2. esa team (production/picoruby/trunk-changes/{yyyy}/{mm}/{dd}/{yyyy-mm-dd}-picoruby-trunk-changes)

require 'bundler/setup'
require 'yaml'
require 'digest'
require_relative '../lib/ruby_knowledge_db/config'
require_relative '../lib/ruby_knowledge_db/esa_writer'

export_dir = ENV['EXPORT_DIR'] or abort "EXPORT_DIR required"
short_name = ENV['SHORT_NAME'] or abort "SHORT_NAME required (e.g., picoruby)"
skip_esa   = ENV['SKIP_ESA'] == '1'
skip_db    = ENV['SKIP_DB'] == '1'

cfg     = RubyKnowledgeDb::Config.load
esa_cfg = cfg['esa']

# DB setup
unless skip_db
  require 'ruby_knowledge_store'
  require_relative '../lib/ruby_knowledge_db/orchestrator'
  db_path  = File.expand_path(cfg['db_path'], File.dirname(__dir__))
  RubyKnowledgeStore::Migrator.new(db_path, migrations_dir: RubyKnowledgeStore::MIGRATIONS_DIR).run
  store = RubyKnowledgeStore::Store.new(db_path, embedder: RubyKnowledgeStore::Embedder.new)
end

source_key = "#{short_name}_trunk"
base_category = esa_cfg.dig('sources', source_key, 'category') or abort "esa.sources.#{source_key}.category missing"
source_value  = cfg.dig('sources', source_key, 'source_article') or abort "sources.#{source_key}.source_article missing"

files = Dir.glob(File.join(export_dir, '**', '*.md')).sort
puts "Found #{files.size} files"

db_stored = db_skipped = esa_posted = 0

files.each do |path|
  raw = File.read(path, encoding: 'utf-8')

  # Parse esa export frontmatter
  unless raw.start_with?('---')
    warn "SKIP (no frontmatter): #{path}"
    next
  end
  parts = raw.split(/^---\s*$/, 3)
  next if parts.length < 3
  content = parts[2].strip
  next if content.empty?

  # Extract date from filename (YYYY-MM-DD.md)
  date = File.basename(path, '.md')
  unless date =~ /\A\d{4}-\d{2}-\d{2}\z/
    warn "SKIP (bad date): #{path}"
    next
  end
  y, m, d = date.split('-')

  # DB import
  unless skip_db
    id = store.store(content, source: source_value)
    id ? (db_stored += 1) : (db_skipped += 1)
  end

  # esa post
  unless skip_esa
    category = "#{base_category}/#{y}/#{m}/#{d}"
    title    = "#{date}-#{short_name}-trunk-changes"
    writer   = RubyKnowledgeDb::EsaWriter.new(
      team: esa_cfg['team'], category: category, wip: esa_cfg['wip']
    )
    res = writer.post(name: title, body_md: content)
    if res['number']
      puts "Posted: ##{res['number']} #{res['full_name']}"
      esa_posted += 1
    else
      warn "ERROR posting #{path}: #{res.inspect}"
    end
  end
end

store&.close unless skip_db
puts "Done: db_stored=#{db_stored}, db_skipped=#{db_skipped}, esa_posted=#{esa_posted}"
