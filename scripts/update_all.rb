#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'yaml'
require 'time'
require 'fileutils'

require 'ruby_knowledge_store'
require 'picoruby_trunk'
require 'cruby_trunk'
require 'mruby_trunk'
require 'rurema'
require 'picoruby_docs'
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
  srcs['picoruby_trunk'] && PicorubyTrunk::Collector.new(srcs['picoruby_trunk']),
  srcs['cruby_trunk']    && CrubyTrunk::Collector.new(srcs['cruby_trunk']),
  srcs['mruby_trunk']    && MrubyTrunk::Collector.new(srcs['mruby_trunk']),
  srcs['rurema']         && Rurema::Collector.new(srcs['rurema']),
  srcs['picoruby_docs']  && PicorubyDocs::Collector.new(srcs['picoruby_docs']),
].compact

last_run_path = File.expand_path('../db/last_run.yml', __dir__)
last_run      = File.exist?(last_run_path) ? YAML.load_file(last_run_path) || {} : {}
manual_since  = ARGV[0]
run_at        = Time.now.iso8601

results_all = { stored: 0, skipped: 0, errors: [] }
collectors.each do |collector|
  key   = collector.class.name
  since = manual_since || last_run[key]

  orch    = RubyKnowledgeDb::Orchestrator.new(store, [collector])
  results = orch.run(since: since)

  results_all[:stored]  += results[:stored]
  results_all[:skipped] += results[:skipped]
  results_all[:errors].concat(results[:errors])

  last_run[key] = run_at if results[:errors].empty?
end

FileUtils.mkdir_p(File.dirname(last_run_path))
File.write(last_run_path, last_run.to_yaml)

puts "Done: stored=#{results_all[:stored]}, skipped=#{results_all[:skipped]}"
results_all[:errors].each { |e| warn "ERROR: #{e}" }

store.close
