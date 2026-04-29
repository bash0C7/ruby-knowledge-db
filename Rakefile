require 'rake/testtask'
require_relative 'lib/ruby_knowledge_db/config'
require_relative 'lib/ruby_knowledge_db/trunk_bookmark'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
end

# default task = full pipeline (defined at bottom of this file).
# For tests: `bundle exec rake test`.

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
  require_relative 'lib/ruby_knowledge_db/update_runner'
  require 'rurema_collector'
  require 'picoruby_docs_collector'
  require 'ruby_rdoc_collector'
  require 'ruby_wasm_docs_collector'
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
  RubyKnowledgeDb::Config.ensure_write_host!
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


# ---- cache:prepare 共通ヘルパー ----
# 前提: working tree は常にクリーン、ローカルブランチは都度 origin から作り直し。
# 想定を満たすよう fetch → checkout -f -B → submodule recursive を実行し、
# いずれかが失敗したら例外を投げて daily を止める。silent success 禁止。
def sh_strict!(cmd, chdir: nil)
  out, status = Dir.chdir(chdir || Dir.pwd) { [`#{cmd} 2>&1`, $?] }
  unless status.success?
    abort "cache:prepare failed\n  cmd: #{cmd}\n  cwd: #{chdir || Dir.pwd}\n  exit: #{status.exitstatus}\n  output:\n#{out}"
  end
  out
end

def prepare_trunk_cache(key, source_cfg)
  repo_path = File.expand_path(source_cfg['repo_path'])
  clone_url = source_cfg['clone_url']
  branch    = source_cfg['branch']
  FileUtils.mkdir_p(File.dirname(repo_path))

  if !Dir.exist?(File.join(repo_path, '.git'))
    puts "[#{key}] cloning #{clone_url} → #{repo_path}"
    sh_strict!("git clone --no-single-branch #{clone_url} #{repo_path}")
  else
    # origin remote の URL を強制上書き（/tmp→~/.cache 移行後の健全性確保）
    remotes = Dir.chdir(repo_path) { `git remote 2>/dev/null` }.split
    if remotes.include?('origin')
      sh_strict!("git remote set-url origin #{clone_url}", chdir: repo_path)
    else
      sh_strict!("git remote add origin #{clone_url}", chdir: repo_path)
    end
  end

  puts "[#{key}] fetch origin #{branch}"
  sh_strict!("git fetch --prune origin #{branch}", chdir: repo_path)
  puts "[#{key}] checkout -f -B #{branch} origin/#{branch}"
  sh_strict!("git checkout -f -B #{branch} origin/#{branch}", chdir: repo_path)
  puts "[#{key}] submodule update --init --recursive --force"
  sh_strict!("git submodule update --init --recursive --force", chdir: repo_path)
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

# ---- cache:prepare: trunk-changes 系 repo キャッシュの事前健全化 ----
namespace :cache do
  desc "Prepare trunk-changes repo caches (fetch + checkout -f -B + submodule, fail hard on any error)"
  task :prepare do
    require_base
    cfg = RubyKnowledgeDb::Config.load
    cfg['sources'].each do |key, source_cfg|
      next unless key.end_with?('_trunk')
      prepare_trunk_cache(key, source_cfg)
    end
    puts "cache:prepare OK"
  end
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
      RubyKnowledgeDb::Config.ensure_write_host!
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

  desc "Update ruby.wasm docs (SINCE/BEFORE 必須だが collector 側は無視、content_hash で冪等)"
  task :ruby_wasm_docs do
    run_collector(:ruby_wasm_docs, 'RubyWasmDocsCollector::Collector', 'ruby_wasm_docs')
  end

  desc "Update ruby rdoc (streaming per-entity, source_hash differential, intermediate MD files)"
  task :ruby_rdoc do
    require_update_deps
    require 'time'

    cfg       = RubyKnowledgeDb::Config.load
    store     = build_store(cfg)
    klass_name = 'RubyRdocCollector::Collector'

    # APP_ENV 別に baseline を分離 — test/production の DB が別ファイルなのと対応させる
    app_env = ENV.fetch('APP_ENV', 'development')
    baseline_path = File.expand_path("~/.cache/ruby-rdoc-collector/source_hashes.#{app_env}.yml")
    baseline  = RubyRdocCollector::SourceHashBaseline.new(path: baseline_path)
    collector = Object.const_get(klass_name).new(cfg['sources']['ruby_rdoc'], baseline: baseline)

    stored = 0
    skipped = 0
    errors = 0

    begin
      collector.collect do |record|
        begin
          id = store.store(record[:content], source: record[:source])
          id ? (stored += 1) : (skipped += 1)
        rescue => e
          errors += 1
          warn "ERROR store #{record[:source]}: #{e.message}"
          raise # propagate so Collector treats as yield failure → no baseline update
        end
      end
    ensure
      store.close
    end

    puts "ruby_rdoc: stored=#{stored}, skipped=#{skipped}, errors=#{errors}"
    puts "intermediate MD files: #{collector.output_dir}"

    if errors == 0
      last_run = load_last_run
      last_run[klass_name] = Time.now.iso8601
      save_last_run(last_run)
    end
  end
end

# ---- plan: dry-run preflight (read-only, JSON output) ----
desc "Show pipeline plan as JSON: SINCE/BEFORE, bookmark status, esa conflicts, contradictions (read-only)"
task :plan do
  require_base
  require_relative 'lib/ruby_knowledge_db/pipeline_plan'
  require 'json'

  cfg     = RubyKnowledgeDb::Config.load
  bm_data = RubyKnowledgeDb::TrunkBookmark.load(LAST_RUN_PATH)
  plan    = RubyKnowledgeDb::PipelinePlan.new(
    cfg:           cfg,
    since:         ENV['SINCE'],
    before:        ENV['BEFORE'],
    bookmark_data: bm_data
  )
  puts JSON.pretty_generate(plan.to_h)
end

# ---- db:stats: DB 状態確認（sqlite_vec 経由必須） ----
namespace :db do
  desc "Re-embed all memories with enriched embedding text (source prefix + truncation)"
  task :reembed do
    require_store_deps
    RubyKnowledgeDb::Config.ensure_write_host!

    cfg = RubyKnowledgeDb::Config.load
    db_path = File.expand_path(cfg['db_path'], __dir__)
    abort "DB not found: #{db_path}" unless File.exist?(db_path)

    embedder = RubyKnowledgeStore::Embedder.new
    store = RubyKnowledgeStore::Store.new(db_path, embedder: embedder)

    db = SQLite3::Database.new(db_path)
    db.results_as_hash = true
    db.enable_load_extension(true)
    SqliteVec.load(db)
    db.enable_load_extension(false)

    rows = db.execute('SELECT id, content, source FROM memories ORDER BY id')
    puts "Re-embedding #{rows.size} records..."

    # Clear existing vec data
    db.execute('DELETE FROM memories_vec')

    embedded = skipped = 0
    rows.each_with_index do |row, i|
      content = row['content']
      source = row['source']
      memory_id = row['id']

      if content.length < RubyKnowledgeStore::Store::EMBEDDING_MIN_CONTENT_LENGTH
        skipped += 1
        next
      end

      embedding_text = store.send(:build_embedding_text, content, source)
      embedding = embedder.embed(embedding_text)
      blob = embedding.pack('f*')
      db.execute('INSERT INTO memories_vec(memory_id, embedding) VALUES (?, ?)', [memory_id, blob])
      embedded += 1

      print "\r  #{i + 1}/#{rows.size} (embedded=#{embedded}, skipped=#{skipped})" if (i + 1) % 50 == 0 || i + 1 == rows.size
    end
    puts "\nDone: embedded=#{embedded}, skipped=#{skipped}"

    db.close
    store.close
  end

  desc "Show DB stats (requires sqlite_vec for vec0 access)"
  task :stats do
    require_base
    require 'sqlite3'
    require 'sqlite_vec'

    cfg = RubyKnowledgeDb::Config.load
    db_path = File.expand_path(cfg['db_path'], __dir__)
    abort "DB not found: #{db_path}" unless File.exist?(db_path)

    db = SQLite3::Database.new(db_path, readonly: true)
    db.enable_load_extension(true)
    SqliteVec.load(db)
    db.enable_load_extension(false)

    total      = db.get_first_value("SELECT count(*) FROM memories")
    vec_total  = db.get_first_value("SELECT count(*) FROM memories_vec")
    fts_total  = db.get_first_value("SELECT count(*) FROM memories_fts")
    rurema     = db.get_first_value("SELECT count(*) FROM memories WHERE source LIKE 'rurema%'")
    with_emb   = db.get_first_value("SELECT count(*) FROM memories WHERE embedding IS NOT NULL")

    puts "=== DB Stats: #{db_path} ==="
    puts "memories total:     #{total}"
    puts "memories_vec total: #{vec_total}"
    puts "memories_fts total: #{fts_total}"
    puts "rurema total:       #{rurema}"
    puts "embedding in memories (expect 0): #{with_emb}"
    puts ""

    puts "--- source distribution (top 15) ---"
    db.execute("SELECT source, count(*) as cnt FROM memories GROUP BY source ORDER BY cnt DESC LIMIT 15").each do |row|
      puts "  #{row[1].to_s.rjust(5)}  #{row[0]}"
    end

    puts ""
    puts "--- consistency check ---"
    if total == vec_total
      puts "OK: memories (#{total}) == memories_vec (#{vec_total})"
    else
      puts "WARN: memories (#{total}) != memories_vec (#{vec_total})"
    end
    if total == fts_total
      puts "OK: memories (#{total}) == memories_fts (#{fts_total})"
    else
      puts "WARN: memories (#{total}) != memories_fts (#{fts_total})"
    end

    db.close
  end

  # ---- db:scan_pollution: 空メタ記事・重複候補の検出（read-only）----
  POLLUTION_MARKERS = [
    '%空やん%', '%空ピョン%', '%書く材料がない%',
    '%情報が渡されてへん%', '%情報が渡ってへん%',
    '%事実無根%', '%出力フォーマット%'
  ].freeze

  desc "Scan memories for empty-meta / duplicate trunk/article pollution (read-only)"
  task :scan_pollution do
    require_base
    require 'sqlite3'
    require 'sqlite_vec'

    cfg = RubyKnowledgeDb::Config.load
    db_path = File.expand_path(cfg['db_path'], __dir__)
    abort "DB not found: #{db_path}" unless File.exist?(db_path)

    db = SQLite3::Database.new(db_path, readonly: true)
    db.enable_load_extension(true); SqliteVec.load(db); db.enable_load_extension(false)
    db.results_as_hash = true

    meta_ids = []
    puts "=== empty-meta markers ==="
    POLLUTION_MARKERS.each do |m|
      rows = db.execute(
        "SELECT id, source, created_at, length(content) AS len, substr(content,1,120) AS head " \
        "FROM memories WHERE source LIKE '%trunk/article%' AND content LIKE ? ORDER BY created_at", m
      )
      rows.each do |r|
        meta_ids << r['id']
        puts "  [#{m}] id=#{r['id']} src=#{r['source']} len=#{r['len']} created=#{r['created_at']}"
        puts "    #{r['head'].gsub(/\s+/, ' ')}"
      end
    end
    puts "  (none)" if meta_ids.empty?

    puts ""
    puts "=== duplicate candidates (same source + same first 200 chars) ==="
    dup_rows = db.execute(
      "SELECT source, substr(content, 1, 200) AS sig, COUNT(*) AS n, GROUP_CONCAT(id) AS ids " \
      "FROM memories WHERE source LIKE '%trunk/article%' " \
      "GROUP BY source, sig HAVING n > 1 ORDER BY n DESC"
    )
    if dup_rows.empty?
      puts "  (none)"
    else
      dup_rows.each { |r| puts "  src=#{r['source']} count=#{r['n']} ids=#{r['ids']}" }
    end

    puts ""
    puts "=== summary ==="
    puts "  empty-meta ids: #{meta_ids.uniq.sort.join(',')}"
    puts "  duplicate groups: #{dup_rows.size}"
    puts "  次アクション: `APP_ENV=#{RubyKnowledgeDb::Config::APP_ENV} bundle exec rake db:delete_polluted IDS=#{meta_ids.uniq.sort.join(',')}`" unless meta_ids.empty?

    db.close
  end

  # ---- db:delete_polluted IDS=1,2,3 — 明示 ID による破壊的削除 ----
  desc "Delete memories by explicit IDS (IDS=1,2,3). Cleans memories_vec + memories (memories_fts auto via trigger)."
  task :delete_polluted do
    require_base
    require 'sqlite3'
    require 'sqlite_vec'
    RubyKnowledgeDb::Config.ensure_write_host!

    ids_raw = ENV['IDS'] or abort "IDS required (e.g., IDS=1866,1869)"
    ids = ids_raw.split(',').map { |s| Integer(s.strip) }
    abort "IDS empty" if ids.empty?

    cfg = RubyKnowledgeDb::Config.load
    db_path = File.expand_path(cfg['db_path'], __dir__)
    abort "DB not found: #{db_path}" unless File.exist?(db_path)

    db = SQLite3::Database.new(db_path)
    db.enable_load_extension(true); SqliteVec.load(db); db.enable_load_extension(false)

    before = db.get_first_value('SELECT count(*) FROM memories')
    puts "before: memories=#{before}"
    ids.each do |id|
      db.execute('DELETE FROM memories_vec WHERE memory_id=?', id)
      changes = db.changes
      db.execute('DELETE FROM memories WHERE id=?', id)
      puts "  deleted id=#{id} (memories_vec rows=#{changes}, memories rows=#{db.changes})"
    end
    after_m   = db.get_first_value('SELECT count(*) FROM memories')
    after_v   = db.get_first_value('SELECT count(*) FROM memories_vec')
    after_fts = db.get_first_value('SELECT count(*) FROM memories_fts')
    puts "after:  memories=#{after_m} memories_vec=#{after_v} memories_fts=#{after_fts}"
    if after_m == after_v && after_m == after_fts
      puts "OK: all three tables aligned"
    else
      warn "WARN: table counts diverged — investigate"
    end
    db.close
  end

  desc "Delete all rdoc rows (memories + memories_vec + memories_fts). WHERE source LIKE 'ruby/ruby:rdoc/trunk/%'"
  task :delete_rdoc do
    require_base
    require 'sqlite3'
    require 'sqlite_vec'
    RubyKnowledgeDb::Config.ensure_write_host!

    cfg = RubyKnowledgeDb::Config.load
    db_path = File.expand_path(cfg['db_path'], __dir__)
    abort "DB not found: #{db_path}" unless File.exist?(db_path)

    db = SQLite3::Database.new(db_path)
    db.enable_load_extension(true); SqliteVec.load(db); db.enable_load_extension(false)

    before_m = db.get_first_value('SELECT count(*) FROM memories')
    before_rdoc = db.get_first_value("SELECT count(*) FROM memories WHERE source LIKE 'ruby/ruby:rdoc/trunk/%'")
    puts "before: memories=#{before_m} (rdoc=#{before_rdoc})"

    ids = db.execute("SELECT id FROM memories WHERE source LIKE 'ruby/ruby:rdoc/trunk/%'").flatten
    ids.each do |id|
      db.execute('DELETE FROM memories_vec WHERE memory_id=?', id)
      db.execute('DELETE FROM memories WHERE id=?', id)
    end

    after_m   = db.get_first_value('SELECT count(*) FROM memories')
    after_v   = db.get_first_value('SELECT count(*) FROM memories_vec')
    after_fts = db.get_first_value('SELECT count(*) FROM memories_fts')
    puts "after:  memories=#{after_m} memories_vec=#{after_v} memories_fts=#{after_fts} (deleted=#{ids.size})"
    if after_m == after_v && after_m == after_fts
      puts "OK: all three tables aligned"
    else
      warn "WARN: table counts diverged — investigate"
    end
    db.close
  end
end

# ---- esa:find_duplicates / esa:delete ----
namespace :esa do
  def esa_token
    t = `/usr/bin/security find-generic-password -s 'esa-mcp-token' -w 2>/dev/null`.strip
    abort "ESA token not found in keychain (key: esa-mcp-token)" if t.empty?
    t
  end

  def esa_http_get(team, path)
    require 'net/http'; require 'uri'; require 'json'
    uri = URI("https://api.esa.io/v1/teams/#{team}#{path}")
    http = Net::HTTP.new(uri.host, uri.port); http.use_ssl = true
    req  = Net::HTTP::Get.new(uri.request_uri)
    req['Authorization'] = "Bearer #{esa_token}"
    JSON.parse(http.request(req).body)
  end

  desc "Find duplicate trunk-changes esa posts (optional DATE=YYYY-MM-DD filter)"
  task :find_duplicates do
    require_base
    require 'net/http'; require 'uri'; require 'json'
    cfg = RubyKnowledgeDb::Config.load
    esa_cfg = cfg['esa'] or abort "esa config missing"
    team = esa_cfg['team']
    date_filter = ENV['DATE']

    all_posts = []
    page = 1
    loop do
      q = "category:production"
      q += " name:#{date_filter}" if date_filter
      body = esa_http_get(team, "/posts?q=#{URI.encode_www_form_component(q)}&per_page=100&page=#{page}")
      all_posts.concat(body['posts'] || [])
      break unless body['next_page']
      page = body['next_page']
    end
    puts "=== scanned #{all_posts.size} posts on team=#{team} (DATE=#{date_filter || 'all'}) ==="

    # Group by (category + base name with " (N)" suffix stripped)
    groups = all_posts.group_by do |p|
      base = p['name'].to_s.sub(/\s*\(\d+\)\s*$/, '')
      [p['category'], base]
    end
    dups = groups.select { |_, posts| posts.size > 1 }

    if dups.empty?
      puts "  (no duplicates)"
    else
      dups.each do |(cat, base), posts|
        puts "---- #{cat} / #{base} (#{posts.size} posts) ----"
        posts.sort_by { |p| p['number'] }.each do |p|
          head = p['body_md'].to_s[0, 80].gsub(/\s+/, ' ')
          puts "  ##{p['number']} name='#{p['name']}' updated=#{p['updated_at']} len=#{p['body_md'].to_s.length} head=#{head}"
        end
      end
      all_ids = dups.values.flatten.map { |p| p['number'] }
      puts ""
      puts "候補 ID 全列挙: #{all_ids.join(',')}"
      puts "削除は: `APP_ENV=#{RubyKnowledgeDb::Config::APP_ENV} bundle exec rake esa:delete IDS=<残すものを除いた ID>`"
    end
  end

  desc "Delete esa posts by explicit IDS (IDS=104,110). Hard delete via HTTP DELETE."
  task :delete do
    require_base
    require 'net/http'; require 'uri'
    RubyKnowledgeDb::Config.ensure_write_host!

    ids_raw = ENV['IDS'] or abort "IDS required (e.g., IDS=104)"
    ids = ids_raw.split(',').map { |s| Integer(s.strip) }
    abort "IDS empty" if ids.empty?

    cfg = RubyKnowledgeDb::Config.load
    team = cfg.dig('esa', 'team') or abort "esa.team missing"

    token = esa_token
    ids.each do |id|
      uri = URI("https://api.esa.io/v1/teams/#{team}/posts/#{id}")
      http = Net::HTTP.new(uri.host, uri.port); http.use_ssl = true
      req  = Net::HTTP::Delete.new(uri.request_uri)
      req['Authorization'] = "Bearer #{token}"
      res = http.request(req)
      puts "DELETE ##{id}: #{res.code}"
      sleep 2  # esa API rate limit
    end
  end
end

# ---- default: 昨日分の全ソース一括処理（trunk + update:* + iCloud copy）----
desc "Run full pipeline: trunk generate → import → esa + every update:* task + iCloud copy. SINCE auto-resolved from bookmark floor; aborts on contradictions (set RKDB_FORCE=1 to bypass)"
task default: :'cache:prepare' do
  require_generate_deps
  require_import_deps
  require_esa_deps
  require_update_deps
  require_relative 'lib/ruby_knowledge_db/pipeline_plan'
  RubyKnowledgeDb::Config.ensure_write_host!

  cfg     = RubyKnowledgeDb::Config.load
  bm_data = RubyKnowledgeDb::TrunkBookmark.load(LAST_RUN_PATH)
  plan    = RubyKnowledgeDb::PipelinePlan.new(
    cfg:           cfg,
    since:         ENV['SINCE'],
    before:        ENV['BEFORE'],
    bookmark_data: bm_data
  )

  # Single contradiction guard: SINCE/BEFORE resolution + WIP detection +
  # esa multi-execution check + future-date / inverted-range checks.
  # See lib/ruby_knowledge_db/pipeline_plan.rb for the full checklist.
  plan_h = plan.to_h
  unless plan.consistent? || ENV['RKDB_FORCE'] == '1'
    require 'json'
    abort "=== pipeline aborted: contradictions detected ===\n" \
          "#{JSON.pretty_generate(plan_h)}\n" \
          "Resolve the issues above (e.g. `rake esa:find_duplicates` + `rake esa:delete IDS=...` " \
          "for esa conflicts), or set RKDB_FORCE=1 to bypass."
  end

  since  = plan_h['since']
  before = plan_h['before']
  ENV['SINCE']  = since
  ENV['BEFORE'] = before
  puts "=== pipeline: #{since} → #{before} (since_source=#{plan_h['since_source']}) ==="

  # Re-check esa immediately before the write phase. PipelinePlan already
  # checked at construction time, but a concurrent run or manual post could
  # land between then and Phase 2b. Skip when explicitly forced.
  unless ENV['RKDB_FORCE'] == '1'
    RubyKnowledgeDb::EsaPreflight.check_conflicts!(cfg: cfg, since: since, before: before)
  end

  esa_cfg = cfg['esa']
  store   = build_store(cfg)

  begin
    cfg['sources'].each do |key, source_cfg|
      next unless key.end_with?('_trunk')
      short_name = key.sub(/_trunk$/, '')
      puts "\n--- #{key} ---"

      # Mark started (two-phase bookmark, Phase 1 of 2)
      bm = RubyKnowledgeDb::TrunkBookmark.load(LAST_RUN_PATH)
      bm = RubyKnowledgeDb::TrunkBookmark.mark_started(bm, key, before: before)
      RubyKnowledgeDb::TrunkBookmark.save(LAST_RUN_PATH, bm)

      source_ok = false
      begin
        # Phase 1: generate
        ENV['SINCE']  = since
        ENV['BEFORE'] = before
        collector = build_trunk_collector(source_cfg)
        records   = collector.collect(since: since, before: before)

        tmpdir = Dir.mktmpdir(["#{key}_", "_#{since}_#{before}"])
        begin
          records.each { |r| write_md(tmpdir, r) }
          puts "generate: #{records.size} records → #{tmpdir}"

          any_esa_error = false

          if records.any?
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
            if esa_cfg && (category = esa_cfg.dig('sources', key, 'category'))
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
                  any_esa_error = true
                end
              end
              puts "esa: posted=#{posted}"
            else
              warn "WARN #{key}: esa category not configured — articles not posted"
              any_esa_error = true
            end
          end

          source_ok = !any_esa_error
        ensure
          FileUtils.rm_rf(tmpdir)
        end
      rescue => e
        warn "ERROR in #{key}: #{e.class}: #{e.message}"
        source_ok = false
      end

      # Mark completed only on full success (Phase 2 of 2)
      if source_ok
        bm = RubyKnowledgeDb::TrunkBookmark.load(LAST_RUN_PATH)
        bm = RubyKnowledgeDb::TrunkBookmark.mark_completed(bm, key, before: before)
        RubyKnowledgeDb::TrunkBookmark.save(LAST_RUN_PATH, bm)
        puts "bookmark: #{key} completed before=#{before}"
      else
        warn "bookmark: #{key} NOT marked completed (errors or exception) — next run will re-process"
      end
    end
  ensure
    store.close
  end

  # Dynamically invoke every `update:*` task (update:ruby_rdoc / update:rurema /
  # update:picoruby_docs / any future additions). Adding a new data source =
  # defining a new `task :foo` under `namespace :update` — no edits here required.
  # UpdateRunner isolates each task with rescue so a single failure doesn't
  # kill the rest of the pipeline (notably the iCloud copy below).
  update_tasks = Rake.application.tasks
    .select { |t| t.name.start_with?('update:') }
    .sort_by(&:name)
  update_failures = RubyKnowledgeDb::UpdateRunner.run(update_tasks) do |t|
    puts "\n--- #{t.name} ---"
  end

  # DB を chiebukuro-mcp 参照先にコピー — update に失敗があっても部分進捗は sync する
  copy_to = cfg['db_copy_to']
  if copy_to
    src = File.expand_path(cfg['db_path'], __dir__)
    dst = File.expand_path(copy_to)
    FileUtils.mkdir_p(File.dirname(dst))
    FileUtils.cp(src, dst)
    puts "db: copied to #{dst}"
  end

  if update_failures.empty?
    puts "\n=== pipeline complete ==="
  else
    lines = ["=== pipeline finished with #{update_failures.size} update task failure(s) ==="]
    update_failures.each do |f|
      lines << "  - #{f.task_name}: #{f.error.class}: #{f.error.message}"
    end
    lines << "Re-run individual `rake update:<name>` for those."
    abort lines.join("\n")
  end
end
