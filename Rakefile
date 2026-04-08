require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
end

task default: :test

# ---- per-collector update tasks ----
namespace :update do
  SOURCES_PATH  = File.expand_path('config/sources.yml', __dir__)
  LAST_RUN_PATH = File.expand_path('db/last_run.yml',    __dir__)

  def load_config = YAML.load_file(SOURCES_PATH)
  def load_last_run
    File.exist?(LAST_RUN_PATH) ? (YAML.load_file(LAST_RUN_PATH) || {}) : {}
  end
  def save_last_run(data)
    FileUtils.mkdir_p(File.dirname(LAST_RUN_PATH))
    File.write(LAST_RUN_PATH, data.to_yaml)
  end
  def build_store
    cfg = load_config
    db  = File.expand_path(cfg['db_path'], __dir__)
    RubyKnowledgeStore::Migrator.new(db, migrations_dir: RubyKnowledgeStore::MIGRATIONS_DIR).run
    RubyKnowledgeStore::Store.new(db, embedder: RubyKnowledgeStore::Embedder.new)
  end
  def run_collector(collector_key, klass_name, config_key)
    require 'bundler/setup'
    require 'yaml'
    require 'date'
    require 'fileutils'

    require 'ruby_knowledge_store'
    require 'picoruby_trunk_changes_generator'
    require 'cruby_trunk_changes_generator'
    require 'mruby_trunk_changes_generator'
    require 'rurema_collector'
    require 'picoruby_docs_collector'
    require_relative 'lib/ruby_knowledge_db/orchestrator'

    since  = ENV['SINCE']  or abort "SINCE required (e.g., SINCE=2026-04-08)"
    before = ENV['BEFORE'] or abort "BEFORE required (e.g., BEFORE=2026-04-09)"

    cfg       = load_config
    last_run  = load_last_run
    store     = build_store
    srcs      = cfg['sources']
    collector = Object.const_get(klass_name).new(srcs[config_key])
    orch      = RubyKnowledgeDb::Orchestrator.new(store, [collector])
    results   = orch.run(since: since, before: before)
    store.close

    puts "#{collector_key}: stored=#{results[:stored]}, skipped=#{results[:skipped]}"
    results[:errors].each { |e| warn "ERROR: #{e}" }

    if results[:errors].empty?
      last_run[klass_name] = before
      save_last_run(last_run)
    end
  end

  desc "Update picoruby trunk changes (SINCE=yyyy-mm-dd BEFORE=yyyy-mm-dd)"
  task :picoruby_trunk do
    run_collector(:picoruby_trunk, 'PicorubyTrunkChangesGenerator::Collector', 'picoruby_trunk')
  end

  desc "Update mruby trunk changes (SINCE=yyyy-mm-dd BEFORE=yyyy-mm-dd)"
  task :mruby_trunk do
    run_collector(:mruby_trunk, 'MrubyTrunkChangesGenerator::Collector', 'mruby_trunk')
  end

  desc "Update CRuby trunk changes (SINCE=yyyy-mm-dd BEFORE=yyyy-mm-dd)"
  task :cruby_trunk do
    run_collector(:cruby_trunk, 'CrubyTrunkChangesGenerator::Collector', 'cruby_trunk')
  end

  desc "Update rurema docs (SINCE=yyyy-mm-dd BEFORE=yyyy-mm-dd)"
  task :rurema do
    run_collector(:rurema, 'RuremaCollector::Collector', 'rurema')
  end

  desc "Update picoruby docs (SINCE=yyyy-mm-dd BEFORE=yyyy-mm-dd)"
  task :picoruby_docs do
    run_collector(:picoruby_docs, 'PicorubyDocsCollector::Collector', 'picoruby_docs')
  end
end
