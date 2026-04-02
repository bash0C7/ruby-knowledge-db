require_relative '../../../test/test_helper'
require_relative '../lib/picoruby_trunk/collector'

class TestPicorubyTrunkCollector < Test::Unit::TestCase
  def setup
    # GitOps stub
    @fake_git = Object.new
    def @fake_git.commits_for_date(date, branch)
      date == Date.today ? ['abc123'] : []
    end
    def @fake_git.show(hash) = "diff --git a/foo.rb ..."
    def @fake_git.commit_metadata(hash)
      { author: 'test', datetime: '2024-01-01', message: 'test commit' }
    end

    # ContentGenerator stub
    @fake_gen = Object.new
    def @fake_gen.call(context:) = "# Article for #{context[:hash]}"

    @collector = PicorubyTrunk::Collector.new(
      { 'repo_path' => '/tmp/fake_repo', 'branch' => 'master' },
      git_ops: @fake_git,
      content_generator: @fake_gen
    )
  end

  def test_collect_returns_diff_and_article
    results = @collector.collect
    assert_equal 2, results.size
    assert_equal 'picoruby/picoruby:trunk/diff',    results[0][:source]
    assert_equal 'picoruby/picoruby:trunk/article', results[1][:source]
  end

  def test_collect_with_since
    results = @collector.collect(since: Date.today.iso8601)
    assert_equal 2, results.size  # today's 1 commit -> 2 records
  end

  def test_collect_empty_when_no_commits
    def @fake_git.commits_for_date(date, branch) = []
    results = @collector.collect
    assert_empty results
  end
end
