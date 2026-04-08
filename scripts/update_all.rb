#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'yaml'
require 'time'
require 'date'
require 'fileutils'

require 'ruby_knowledge_store'
require 'picoruby_trunk_changes_generator'
require 'cruby_trunk_changes_generator'
require 'mruby_trunk_changes_generator'
require 'rurema_collector'
require 'picoruby_docs_collector'
require_relative '../lib/ruby_knowledge_db/orchestrator'

config   = YAML.load_file(File.join(__dir__, '../config/sources.yml'))
db_path  = File.expand_path(config['db_path'], File.join(__dir__, '..'))

# DB マイグレーション
RubyKnowledgeStore::Migrator.new(db_path, migrations_dir: RubyKnowledgeStore::MIGRATIONS_DIR).run

embedder = RubyKnowledgeStore::Embedder.new
store    = RubyKnowledgeStore::Store.new(db_path, embedder: embedder)

srcs = config['sources']
collectors = [
  srcs['picoruby_trunk'] && PicorubyTrunkChangesGenerator::Collector.new(srcs['picoruby_trunk']),
  srcs['cruby_trunk']    && CrubyTrunkChangesGenerator::Collector.new(srcs['cruby_trunk']),
  srcs['mruby_trunk']    && MrubyTrunkChangesGenerator::Collector.new(srcs['mruby_trunk']),
  srcs['rurema']         && RuremaCollector::Collector.new(srcs['rurema']),
  srcs['picoruby_docs']  && PicorubyDocsCollector::Collector.new(srcs['picoruby_docs']),
].compact

last_run_path = File.expand_path('../db/last_run.yml', __dir__)
last_run      = File.exist?(last_run_path) ? YAML.load_file(last_run_path) || {} : {}
manual_since  = ARGV[0]
before        = (Date.today + 1).iso8601  # [since, before) → today's commits inclusive

results_all = { stored: 0, skipped: 0, errors: [] }
collectors.each do |collector|
  key   = collector.class.name
  since = manual_since || last_run[key]

  unless since
    warn "SKIP #{key}: no since recorded. Run with ARGV[0] to set initial since."
    next
  end

  orch    = RubyKnowledgeDb::Orchestrator.new(store, [collector])
  results = orch.run(since: since, before: before)

  results_all[:stored]  += results[:stored]
  results_all[:skipped] += results[:skipped]
  results_all[:errors].concat(results[:errors])

  last_run[key] = before if results[:errors].empty?
end

FileUtils.mkdir_p(File.dirname(last_run_path))
File.write(last_run_path, last_run.to_yaml)

puts "Done: stored=#{results_all[:stored]}, skipped=#{results_all[:skipped]}"
results_all[:errors].each { |e| warn "ERROR: #{e}" }

store.close
