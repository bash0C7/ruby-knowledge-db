require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
end

task default: :test

# ---- 共通ヘルパー（遅延ロード、用途別） ----
def require_base
  require 'bundler/setup'
  require 'yaml'
  require 'date'
  require 'fileutils'
  require 'tmpdir'
  require_relative 'lib/ruby_knowledge_db/config'
end

def require_generate_deps
  require_base
  require 'picoruby_trunk_changes_generator'
  require 'cruby_trunk_changes_generator'
  require 'mruby_trunk_changes_generator'
end

def require_store_deps
  require_base
  require 'ruby_knowledge_store'
  require_relative 'lib/ruby_knowledge_db/orchestrator'
end

def require_import_deps
  require_store_deps
end

def require_esa_deps
  require_base
  require_relative 'lib/ruby_knowledge_db/esa_writer'
end

def require_update_deps
  require_store_deps
  require 'rurema_collector'
  require 'picoruby_docs_collector'
end

LAST_RUN_PATH = File.expand_path('db/last_run.yml', __dir__)

def load_last_run
  File.exist?(LAST_RUN_PATH) ? (YAML.load_file(LAST_RUN_PATH) || {}) : {}
end

def save_last_run(data)
  FileUtils.mkdir_p(File.dirname(LAST_RUN_PATH))
  File.write(LAST_RUN_PATH, data.to_yaml)
end

def build_store(cfg)
  db = File.expand_path(cfg['db_path'], __dir__)
  RubyKnowledgeStore::Migrator.new(db, migrations_dir: RubyKnowledgeStore::MIGRATIONS_DIR).run
  RubyKnowledgeStore::Store.new(db, embedder: RubyKnowledgeStore::Embedder.new)
end

# MD ファイルに YAML frontmatter 付きで保存
def write_md(dir, record)
  type    = record[:source].end_with?('/diff') ? 'diff' : 'article'
  date    = record[:date].to_s
  hash    = (record[:hash] || 'unknown')[0, 8]
  fname   = "#{date}-#{hash}-#{type}.md"
  content = <<~MD
    ---
    source: #{record[:source]}
    date: #{date}
    hash: #{record[:hash]}
    type: #{type}
    ---
    #{record[:content]}
  MD
  File.write(File.join(dir, fname), content)
end

# frontmatter を読み取って source + 本文を返す
def parse_md(path)
  raw = File.read(path, encoding: 'utf-8')
  return nil unless raw.start_with?('---')
  parts = raw.split(/^---\s*$/, 3)
  return nil if parts.length < 3
  fm      = YAML.safe_load(parts[1]) || {}
  content = parts[2].strip
  return nil if content.empty?
  { source: fm['source'], type: fm['type'], content: content }
end

# 記事 MD から esa タイトルを抽出（最初の # 見出し or 日付）
def extract_title(content, fallback)
  line = content.lines.find { |l| l.start_with?('# ') }
  line ? line.sub(/^# /, '').strip : fallback
end

# ---- Phase 1: generate ----
namespace :generate do
  def generate_trunk(klass_name, config_key)
    require_generate_deps
    since  = ENV['SINCE']  or abort "SINCE required (e.g., SINCE=2026-04-08)"
    before = ENV['BEFORE'] or abort "BEFORE required (e.g., BEFORE=2026-04-09)"

    cfg       = RubyKnowledgeDb::Config.load
    collector = Object.const_get(klass_name).new(cfg['sources'][config_key])
    records   = collector.collect(since: since, before: before)

    tmpdir = Dir.mktmpdir(["#{config_key}_", "_#{since}_#{before}"])
    records.each { |r| write_md(tmpdir, r) }

    puts "Generated #{records.size} records"
    puts "DIR=#{tmpdir}"
  end

  desc "Generate picoruby trunk changes to tmpdir (SINCE=yyyy-mm-dd BEFORE=yyyy-mm-dd)"
  task :picoruby_trunk do
    generate_trunk('PicorubyTrunkChangesGenerator::Collector', 'picoruby_trunk')
  end

  desc "Generate mruby trunk changes to tmpdir (SINCE=yyyy-mm-dd BEFORE=yyyy-mm-dd)"
  task :mruby_trunk do
    generate_trunk('MrubyTrunkChangesGenerator::Collector', 'mruby_trunk')
  end

  desc "Generate CRuby trunk changes to tmpdir (SINCE=yyyy-mm-dd BEFORE=yyyy-mm-dd)"
  task :cruby_trunk do
    generate_trunk('CrubyTrunkChangesGenerator::Collector', 'cruby_trunk')
  end
end

# ---- Phase 2a: import to SQLite ----
namespace :import do
  def import_trunk(config_key)
    require_import_deps
    dir = ENV['DIR'] or abort "DIR required (output of rake generate:#{config_key})"

    cfg   = RubyKnowledgeDb::Config.load
    store = build_store(cfg)

    files = Dir.glob(File.join(dir, '*.md')).sort
    stored = skipped = 0
    files.each do |path|
      rec = parse_md(path)
      next unless rec
      id = store.store(rec[:content], source: rec[:source])
      id ? (stored += 1) : (skipped += 1)
    end

    store.close
    puts "import #{config_key}: stored=#{stored}, skipped=#{skipped}"
  end

  desc "Import picoruby trunk changes from tmpdir to SQLite (DIR=path)"
  task :picoruby_trunk do
    import_trunk('picoruby_trunk')
  end

  desc "Import mruby trunk changes from tmpdir to SQLite (DIR=path)"
  task :mruby_trunk do
    import_trunk('mruby_trunk')
  end

  desc "Import CRuby trunk changes from tmpdir to SQLite (DIR=path)"
  task :cruby_trunk do
    import_trunk('cruby_trunk')
  end
end

# ---- Phase 2b: post to esa ----
namespace :esa do
  def post_trunk(config_key)
    require_esa_deps
    dir = ENV['DIR'] or abort "DIR required (output of rake generate:#{config_key})"

    cfg      = RubyKnowledgeDb::Config.load
    esa_cfg  = cfg['esa']                                  or abort "esa config missing"
    category = esa_cfg.dig('sources', config_key, 'category') or
               abort "esa.sources.#{config_key}.category missing"
    writer   = RubyKnowledgeDb::EsaWriter.new(
      team:     esa_cfg['team'],
      category: category,
      wip:      esa_cfg['wip']
    )

    files = Dir.glob(File.join(dir, '*-article.md')).sort
    posted = 0
    files.each do |path|
      rec   = parse_md(path)
      next unless rec
      fname = File.basename(path, '.md')
      title = extract_title(rec[:content], fname)
      res   = writer.post(name: title, body_md: rec[:content])
      if res['number']
        puts "Posted: ##{res['number']} #{res['full_name']}"
        posted += 1
      else
        warn "ERROR posting #{path}: #{res.inspect}"
      end
    end

    puts "esa #{config_key}: posted=#{posted}"
  end

  desc "Post picoruby trunk changes from tmpdir to esa (DIR=path)"
  task :picoruby_trunk do
    post_trunk('picoruby_trunk')
  end

  desc "Post mruby trunk changes from tmpdir to esa (DIR=path)"
  task :mruby_trunk do
    post_trunk('mruby_trunk')
  end

  desc "Post CRuby trunk changes from tmpdir to esa (DIR=path)"
  task :cruby_trunk do
    post_trunk('cruby_trunk')
  end
end

# ---- update: SQLite 直接書き込み（rurema/picoruby_docs 向け） ----
namespace :update do
  def run_collector(collector_key, klass_name, config_key)
    require_update_deps
    since  = ENV['SINCE']  or abort "SINCE required (e.g., SINCE=2026-04-08)"
    before = ENV['BEFORE'] or abort "BEFORE required (e.g., BEFORE=2026-04-09)"

    cfg       = RubyKnowledgeDb::Config.load
    store     = build_store(cfg)
    collector = Object.const_get(klass_name).new(cfg['sources'][config_key])
    orch      = RubyKnowledgeDb::Orchestrator.new(store, [collector])
    results   = orch.run(since: since, before: before)
    store.close

    puts "#{collector_key}: stored=#{results[:stored]}, skipped=#{results[:skipped]}"
    results[:errors].each { |e| warn "ERROR: #{e}" }

    if results[:errors].empty?
      last_run = load_last_run
      last_run[klass_name] = before
      save_last_run(last_run)
    end
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
