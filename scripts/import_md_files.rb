#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Usage: bundle exec ruby scripts/import_md_files.rb <dir> [source]
#
# Imports canonical *.md files (YYYY-MM-DD.md pattern, no duplicates)
# from <dir> into the knowledge DB.
#
# Default source: picoruby/picoruby:trunk/article

require 'bundler/setup'
require 'ruby_knowledge_store'
require 'yaml'

dir    = ARGV[0] or abort "Usage: #{$0} <dir> [source]"
source = ARGV[1] || 'picoruby/picoruby:trunk/article'

db_path = File.expand_path('../db/ruby_knowledge.db', __dir__)

RubyKnowledgeStore::Migrator.new(db_path, migrations_dir: RubyKnowledgeStore::MIGRATIONS_DIR).run
embedder = RubyKnowledgeStore::Embedder.new
store    = RubyKnowledgeStore::Store.new(db_path, embedder: embedder)

# 正規ファイルのみ: YYYY-MM-DD.md (スペースや__duplicated__なし)
files = Dir.glob(File.join(dir, '**', '*.md'))
             .select { |f| File.basename(f) =~ /\A\d{4}-\d{2}-\d{2}\.md\z/ }
             .sort

stored  = 0
skipped = 0

files.each do |path|
  raw = File.read(path, encoding: 'utf-8')

  # YAML フロントマター除去 (--- ... --- の間を取り除く)
  content = if raw.start_with?('---')
    parts = raw.split(/^---\s*$/, 3)
    parts.length >= 3 ? parts[2].strip : raw
  else
    raw.strip
  end

  next if content.empty?

  id = store.store(content, source: source)
  if id
    stored += 1
    print '.'
  else
    skipped += 1
    print 's'
  end
end

puts
puts "Done: stored=#{stored}, skipped=#{skipped}, total_files=#{files.length}"
store.close
