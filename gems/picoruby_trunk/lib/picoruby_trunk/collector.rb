require 'trunk_changes'
require 'date'

module PicorubyTrunk
  class Collector
    REPO           = 'picoruby/picoruby'
    SOURCE_DIFF    = 'picoruby/picoruby:trunk/diff'
    SOURCE_ARTICLE = 'picoruby/picoruby:trunk/article'
    DEFAULT_DAYS   = 30

    def initialize(config, git_ops: nil, content_generator: nil)
      repo_path  = File.expand_path(config['repo_path'])
      @git       = git_ops           || GitOps.new(repo_path)
      @generator = content_generator || ContentGenerator.new(repo: REPO, wait: false)
      @branch    = config.fetch('branch', 'master')
    end

    # @param since [String, nil] ISO8601
    # @return [Array<{content: String, source: String}>]
    def collect(since: nil)
      commits = fetch_commits(since)
      results = []
      commits.each do |hash|
        diff    = @git.show(hash)
        article = @generator.call(context: build_context(hash))
        results << { content: diff,    source: SOURCE_DIFF }
        results << { content: article, source: SOURCE_ARTICLE }
      end
      results
    end

    private

    def fetch_commits(since)
      start_date = since ? Date.parse(since) : Date.today - DEFAULT_DAYS
      end_date   = Date.today
      commits = []
      (start_date..end_date).each do |date|
        commits.concat(@git.commits_for_date(date, @branch))
      end
      commits
    end

    def build_context(hash)
      metadata = @git.commit_metadata(hash)
      {
        hash:               hash,
        metadata:           metadata,
        show_output:        @git.show(hash),
        changed_files:      [],
        dependency_files:   [],
        project_meta_files: [],
        issue_contexts:     []
      }
    end
  end
end
