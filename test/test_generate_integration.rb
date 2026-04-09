require 'test/unit'
require 'date'
require_relative '../lib/ruby_knowledge_db/config'

# trunk_changes_diary は遅延ロード（Rakefile と同じ）
require 'trunk_changes'

class TestGenerateIntegration < Test::Unit::TestCase
  # sources.yml から picoruby_trunk 設定を読み込んで TrunkChangesCollector を構築できることを検証
  def setup
    @cfg = RubyKnowledgeDb::Config.load
    @source = @cfg['sources']['picoruby_trunk']
  end

  def test_sources_yml_has_required_keys
    %w[repo branch clone_url repo_path source_diff source_article].each do |key|
      assert_not_nil @source[key], "picoruby_trunk should have '#{key}' in sources.yml"
    end
  end

  def test_prompt_supplement_is_loaded
    assert_not_nil @source['prompt_supplement']
    assert_include @source['prompt_supplement'], 'PicoRuby'
  end

  # merge commit パターン（Apr 4: #381, #380, #382）
  def test_collect_merge_commit_pattern
    git = build_stub_git(
      commits: { Date.new(2026, 4, 4) => ['merge1', 'regular1'] },
      merges: ['merge1']
    )
    collector = build_collector(git)
    records = collector.collect(since: '2026-04-04', before: '2026-04-05')

    assert_equal 2, records.size
    assert_equal 'picoruby/picoruby:trunk/diff', records[0][:source]
    assert_equal 'picoruby/picoruby:trunk/article', records[1][:source]
  end

  # 直 push パターン（通常コミット）
  def test_collect_direct_push_pattern
    git = build_stub_git(
      commits: { Date.new(2026, 4, 5) => ['hash1', 'hash2', 'hash3'] },
      merges: []
    )
    collector = build_collector(git)
    records = collector.collect(since: '2026-04-05', before: '2026-04-06')

    assert_equal 2, records.size
    diff_content = records[0][:content]
    assert_include diff_content, 'hash1'
    assert_include diff_content, 'hash3'
  end

  # submodule パターン（Apr 8: funicular upgrade）
  def test_collect_submodule_pattern
    git = build_stub_git(
      commits: { Date.new(2026, 4, 8) => ['sub_commit'] },
      merges: [],
      submodules: { 'sub_commit' => [{ path: 'mrbgems/picoruby-funicular', old_sha: 'aaa', new_sha: 'bbb' }] }
    )
    collector = build_collector(git)
    records = collector.collect(since: '2026-04-08', before: '2026-04-09')

    assert_equal 3, records.size
    assert_equal 'picoruby/picoruby:trunk/diff', records[0][:source]
    assert_equal 'picoruby/picoruby:trunk/article', records[1][:source]
    assert_equal 'picoruby/picoruby:trunk/article/picoruby-funicular', records[2][:source]
  end

  # prompt_supplement が ContentGenerator に渡されることを検証
  def test_prompt_supplement_passed_to_generator
    captured = []
    runner = ->(p) { captured << p; "article" }
    gen = ContentGenerator.new(
      repo: @source['repo'],
      runner: runner,
      wait: false,
      prompt_supplement: @source['prompt_supplement']
    )

    git = build_stub_git(commits: { Date.new(2026, 4, 5) => ['hash1'] })
    collector = TrunkChangesCollector.new(
      repo: @source['repo'], branch: @source['branch'],
      source_diff: @source['source_diff'], source_article: @source['source_article'],
      git_ops: git, content_generator: gen
    )
    collector.collect(since: '2026-04-05', before: '2026-04-06')

    assert_not_empty captured
    assert_include captured.first, 'PicoRuby'
  end

  private

  def build_stub_git(commits: {}, merges: [], submodules: {})
    git = Object.new
    git.define_singleton_method(:commits_for_date) do |date, branch|
      commits[date] || []
    end
    git.define_singleton_method(:commit_metadata) do |hash|
      { author: 'dev', datetime: '2026-04-05 10:00:00 +0900', message: "commit #{hash}" }
    end
    git.define_singleton_method(:is_merge?) { |hash| merges.include?(hash) }
    git.define_singleton_method(:merge_log) { |hash| merges.include?(hash) ? "abc Fix\ndef Update" : nil }
    git.define_singleton_method(:last_commit_before) { |date, branch| 'prev_hash' }
    git.define_singleton_method(:diff) { |from, to| "diff --git a/foo.rb\n+line" }
    git.define_singleton_method(:submodule_changes) do |hash|
      submodules[hash] || []
    end
    git.define_singleton_method(:submodule_log) { |path, old_sha, new_sha| "ccc Fix" }
    git.define_singleton_method(:submodule_diff_stat) { |path, old_sha, new_sha| " foo.c | 5 +++--" }
    git
  end

  def build_collector(git)
    gen = Object.new
    def gen.call(context:) = "generated article"

    TrunkChangesCollector.new(
      repo: @source['repo'], branch: @source['branch'],
      source_diff: @source['source_diff'], source_article: @source['source_article'],
      git_ops: git, content_generator: gen
    )
  end
end
