#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'yaml'
require 'time'

require 'ruby_knowledge_store'
require 'picoruby_trunk'
require 'cruby_trunk'
require 'mruby_trunk'
require_relative '../lib/ruby_knowledge_db/orchestrator'

config   = YAML.load_file(File.join(__dir__, '../config/sources.yml'))
db_path  = File.expand_path(config['db_path'], File.join(__dir__, '..'))

# DB マイグレーション
migrations_dir = File.expand_path('../migrations', __dir__)
RubyKnowledgeStore::Migrator.new(db_path, migrations_dir: migrations_dir).run

embedder = RubyKnowledgeStore::Embedder.new
store    = RubyKnowledgeStore::Store.new(db_path, embedder: embedder)

srcs = config['sources']
collectors = [
  PicorubyTrunk::Collector.new(srcs['picoruby_trunk']),
  CrubyTrunk::Collector.new(srcs['cruby_trunk']),
  MrubyTrunk::Collector.new(srcs['mruby_trunk']),
]

since = ARGV[0]  # ISO8601 or nil
orchestrator = RubyKnowledgeDb::Orchestrator.new(store, collectors)
results = orchestrator.run(since: since)

puts "Done: stored=#{results[:stored]}, skipped=#{results[:skipped]}"
results[:errors].each { |e| warn "ERROR: #{e}" }

store.close
