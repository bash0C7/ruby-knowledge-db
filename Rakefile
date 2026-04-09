require 'rake/testtask'
require_relative 'lib/ruby_knowledge_db/config'

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
end

def require_generate_deps
  require_base
  require 'trunk_changes'
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

# MD ファイルに YAML frontmatter 付きで保存（日単位: YYYY-MM-DD-{type}.md）
def write_md(dir, record)
  source = record[:source]
  date   = record[:date].to_s

  if source.end_with?('/diff')
    type  = 'diff'
    fname = "#{date}-diff.md"
  elsif source =~ %r{/article/(.+)$}
    type  = 'article'
    fname = "#{date}-article-#{$1}.md"
  else
    type  = 'article'
    fname = "#{date}-article.md"
  end
  content = <<~MD
    ---
    source: #{record[:source]}
    date: #{date}
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
  fm      = YAML.safe_load(parts[1], permitted_classes: [Date]) || {}
  content = parts[2].strip
  return nil if content.empty?
  { source: fm['source'], type: fm['type'], content: content }
end

# 記事 MD から esa タイトルを抽出（最初の # 見出し or 日付）
def extract_title(content, fallback)
  line = content.lines.find { |l| l.start_with?('# ') }
  line ? line.sub(/^# /, '').strip : fallback
end

# ---- trunk-changes 共通ヘルパー ----
def build_trunk_collector(source_cfg)
  repo_path = File.expand_path(source_cfg['repo_path'])
  git = GitOps.new(repo_path)
  git.setup(source_cfg['clone_url'], source_cfg['branch'], since_date: ENV['SINCE'])
  gen = ContentGenerator.new(
    repo: source_cfg['repo'],
    prompt_supplement: source_cfg['prompt_supplement']
  )
  TrunkChangesCollector.new(
    repo:              source_cfg['repo'],
    branch:            source_cfg['branch'],
    source_diff:       source_cfg['source_diff'],
    source_article:    source_cfg['source_article'],
    git_ops:           git,
    content_generator: gen
  )
end

# ---- Phase 1: generate（動的タスク生成） ----
namespace :generate do
  RubyKnowledgeDb::Config.load['sources'].each_key do |key|
    next unless key.end_with?('_trunk')

    desc "Generate #{key} changes (SINCE=yyyy-mm-dd BEFORE=yyyy-mm-dd)"
    task key.to_sym do
      require_generate_deps
      since  = ENV['SINCE']  or abort "SINCE required (e.g., SINCE=2026-04-08)"
      before = ENV['BEFORE'] or abort "BEFORE required (e.g., BEFORE=2026-04-09)"
      cfg    = RubyKnowledgeDb::Config.load
      source = cfg['sources'][key]

      collector = build_trunk_collector(source)
      records   = collector.collect(since: since, before: before)

      tmpdir = Dir.mktmpdir(["#{key}_", "_#{since}_#{before}"])
      records.each { |r| write_md(tmpdir, r) }
      puts "Generated #{records.size} records"
      puts "DIR=#{tmpdir}"
    end
  end
end

# ---- Phase 2a: import to SQLite（動的タスク生成） ----
namespace :import do
  RubyKnowledgeDb::Config.load['sources'].each_key do |key|
    next unless key.end_with?('_trunk')

    desc "Import #{key} changes from tmpdir to SQLite (DIR=path)"
    task key.to_sym do
      require_import_deps
      dir = ENV['DIR'] or abort "DIR required (output of rake generate:#{key})"

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
      puts "import #{key}: stored=#{stored}, skipped=#{skipped}"
    end
  end
end

# ---- Phase 2b: post to esa（動的タスク生成） ----
namespace :esa do
  RubyKnowledgeDb::Config.load['sources'].each_key do |key|
    next unless key.end_with?('_trunk')

    desc "Post #{key} changes from tmpdir to esa (DIR=path)"
    task key.to_sym do
      require_esa_deps
      dir = ENV['DIR'] or abort "DIR required (output of rake generate:#{key})"

      cfg      = RubyKnowledgeDb::Config.load
      esa_cfg  = cfg['esa']                                  or abort "esa config missing"
      category = esa_cfg.dig('sources', key, 'category')     or abort "esa.sources.#{key}.category missing"
      writer   = RubyKnowledgeDb::EsaWriter.new(
        team:     esa_cfg['team'],
        category: category,
        wip:      esa_cfg['wip']
      )

      # key から短縮名を導出（picoruby_trunk → picoruby）
      short_name = key.sub(/_trunk$/, '')

      files = Dir.glob(File.join(dir, '*-article.md')).sort
      posted = 0
      files.each do |path|
        rec   = parse_md(path)
        next unless rec
        # ファイル名から日付を抽出（YYYY-MM-DD-article.md）
        date = File.basename(path)[/\A(\d{4}-\d{2}-\d{2})/, 1]
        next unless date
        y, m, d = date.split('-')
        date_category = "#{category}/#{y}/#{m}/#{d}"
        title = "#{date}-#{short_name}-trunk-changes"

        date_writer = RubyKnowledgeDb::EsaWriter.new(
          team: esa_cfg['team'], category: date_category, wip: esa_cfg['wip']
        )
        res = date_writer.post(name: title, body_md: rec[:content])
        if res['number']
          puts "Posted: ##{res['number']} #{res['full_name']}"
          posted += 1
        else
          warn "ERROR posting #{path}: #{res.inspect}"
        end
      end

      puts "esa #{key}: posted=#{posted}"
    end
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

# ---- daily: 昨日分の全ソース一括処理 ----
desc "Run daily pipeline: generate → import → esa for all trunk sources (SINCE/BEFORE auto-set to yesterday/today)"
task :daily do
  require_generate_deps
  require_import_deps
  require_esa_deps

  since  = ENV['SINCE']  || (Date.today - 1).to_s
  before = ENV['BEFORE'] || Date.today.to_s
  puts "=== daily: #{since} → #{before} ==="

  cfg     = RubyKnowledgeDb::Config.load
  esa_cfg = cfg['esa']
  store   = build_store(cfg)

  cfg['sources'].each do |key, source_cfg|
    next unless key.end_with?('_trunk')
    short_name = key.sub(/_trunk$/, '')
    puts "\n--- #{key} ---"

    # Phase 1: generate
    ENV['SINCE']  = since
    ENV['BEFORE'] = before
    collector = build_trunk_collector(source_cfg)
    records   = collector.collect(since: since, before: before)

    tmpdir = Dir.mktmpdir(["#{key}_", "_#{since}_#{before}"])
    records.each { |r| write_md(tmpdir, r) }
    puts "generate: #{records.size} records → #{tmpdir}"

    next if records.empty?

    # Phase 2a: import to SQLite
    files = Dir.glob(File.join(tmpdir, '*.md')).sort
    stored = skipped = 0
    files.each do |path|
      rec = parse_md(path)
      next unless rec
      id = store.store(rec[:content], source: rec[:source])
      id ? (stored += 1) : (skipped += 1)
    end
    puts "import: stored=#{stored}, skipped=#{skipped}"

    # Phase 2b: post to esa
    next unless esa_cfg
    category = esa_cfg.dig('sources', key, 'category')
    next unless category

    article_files = Dir.glob(File.join(tmpdir, '*-article.md')).sort
    posted = 0
    article_files.each do |path|
      rec = parse_md(path)
      next unless rec
      date = File.basename(path)[/\A(\d{4}-\d{2}-\d{2})/, 1]
      next unless date
      y, m, d = date.split('-')
      date_category = "#{category}/#{y}/#{m}/#{d}"
      title = "#{date}-#{short_name}-trunk-changes"

      writer = RubyKnowledgeDb::EsaWriter.new(
        team: esa_cfg['team'], category: date_category, wip: esa_cfg['wip']
      )
      res = writer.post(name: title, body_md: rec[:content])
      if res['number']
        puts "esa: ##{res['number']} #{res['full_name']}"
        posted += 1
      else
        warn "ERROR posting #{path}: #{res.inspect}"
      end
    end
    puts "esa: posted=#{posted}"
  end

  store.close

  # DB を chiebukuro-mcp 参照先にコピー
  copy_to = cfg['db_copy_to']
  if copy_to
    src = File.expand_path(cfg['db_path'], __dir__)
    dst = File.expand_path(copy_to)
    FileUtils.mkdir_p(File.dirname(dst))
    FileUtils.cp(src, dst)
    puts "db: copied to #{dst}"
  end

  puts "\n=== daily complete ==="
end
