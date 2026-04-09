# Full Clone + Submodule Article Generation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** diff 生成を full clone + 時系列前コミット方式に変更し、submodule 変更ごとに個別記事を生成する。

**Architecture:**
shallow clone を廃止し full clone（`/tmp` キャッシュ）に変更。diff は git parent ではなく main ブランチ上の時系列前コミットとの差分を常に使用。submodule は `--depth=1` で clone し、変更区間の log + stat を Claude CLI に渡して個別記事を生成。

**Tech Stack:** Ruby 4.0.1, trunk_changes_diary gem, minitest / test-unit, git

---

## File Structure

| ファイル | 変更 | 責務 |
|---------|------|------|
| `trunk-changes-diary/trunk_changes.rb` | modify | GitOps: full clone, diff(from,to), last_commit_before, submodule_updates 拡張, submodule_log, submodule_diff_stat |
| `trunk-changes-diary/trunk_changes.rb` | modify | TrunkChangesCollector: prev_hash 追跡, submodule 記事生成 |
| `trunk-changes-diary/trunk_changes.rb` | modify | ContentGenerator: submodule 記事用プロンプト |
| `trunk-changes-diary/test/test_trunk_changes.rb` | modify | GitOps テスト |
| `trunk-changes-diary/test/test_trunk_changes_collector.rb` | modify | Collector テスト |
| `ruby-knowledge-db/Rakefile` | modify | write_md: submodule 記事のファイル名対応 |
| `picoruby-trunk-changes-generator/test/test_*.rb` | modify | stub 更新 |
| `cruby-trunk-changes-generator/test/test_*.rb` | modify | stub 更新 |
| `mruby-trunk-changes-generator/test/test_*.rb` | modify | stub 更新 |

全変更は `~/dev/src/github.com/bash0C7/` 配下。trunk-changes-diary のテストは `rake test`（bundler 不要）、ruby-knowledge-db は `bundle exec rake test`。

---

## Task 1: GitOps#setup を full clone に変更

**Files:**
- Modify: `~/dev/src/github.com/bash0C7/trunk-changes-diary/trunk_changes.rb:15-31`
- Test: `~/dev/src/github.com/bash0C7/trunk-changes-diary/test/test_trunk_changes.rb`

- [ ] **Step 1: テストを書く**

`test/test_trunk_changes.rb` の `TestGitOps` 内の `test_setup_subtracts_2_days_from_since_date_for_shallow` を以下に書き換え:

```ruby
def test_setup_does_full_clone_without_shallow
  captured = []
  shell = ->(cmd) { captured << cmd; "" }
  git = GitOps.new(@repo_path, shell: shell)
  git.setup('https://example.com/repo.git', 'master', since_date: '2026-04-05')
  clone_cmd = captured.find { |c| c.include?('git clone') }
  assert_includes clone_cmd, '--no-single-branch'
  refute_includes clone_cmd, '--shallow-since'
  refute_includes clone_cmd, '--depth'
end

def test_setup_fetches_without_shallow_when_repo_exists
  captured = []
  shell = ->(cmd) { captured << cmd; "" }
  git = GitOps.new(@repo_path, shell: shell)
  FileUtils.mkdir_p(File.join(@repo_path, '.git'))
  git.setup('https://example.com/repo.git', 'master', since_date: '2026-04-05')
  fetch_cmd = captured.find { |c| c.include?('git fetch') }
  assert_equal 'git fetch origin', fetch_cmd
end

def test_setup_inits_submodules
  captured = []
  shell = ->(cmd) { captured << cmd; "" }
  git = GitOps.new(@repo_path, shell: shell)
  git.setup('https://example.com/repo.git', 'master')
  sub_cmd = captured.find { |c| c.include?('submodule') }
  assert_includes sub_cmd, 'git submodule update --init --depth=1'
end
```

- [ ] **Step 2: テスト実行して fail 確認**

```bash
cd ~/dev/src/github.com/bash0C7/trunk-changes-diary && rake test
```

- [ ] **Step 3: setup を書き換え**

```ruby
def setup(clone_url, branch, since_date: nil)
  if Dir.exist?(File.join(@repo_path, '.git'))
    run("git fetch origin")
    run("git rebase origin/#{branch}")
  else
    FileUtils.mkdir_p(File.dirname(@repo_path))
    @shell.call("git clone --no-single-branch #{clone_url} #{@repo_path}")
  end
  run("git submodule update --init --depth=1")
end
```

- [ ] **Step 4: テスト実行して green 確認**

```bash
rake test
```

- [ ] **Step 5: コミット**

```bash
git add trunk_changes.rb test/test_trunk_changes.rb
git commit -m "feat: switch to full clone with submodule init, remove shallow hacks"
```

---

## Task 2: GitOps#diff と GitOps#last_commit_before を追加

**Files:**
- Modify: `~/dev/src/github.com/bash0C7/trunk-changes-diary/trunk_changes.rb`
- Test: `~/dev/src/github.com/bash0C7/trunk-changes-diary/test/test_trunk_changes.rb`

- [ ] **Step 1: テストを書く**

`test/test_trunk_changes.rb` の `TestGitOps` に追加:

```ruby
def test_diff_returns_diff_between_two_commits
  diff_output = "diff --git a/foo.rb b/foo.rb\n+new line\n"
  shell = ->(cmd) {
    cmd.include?("git diff") ? diff_output : ""
  }
  git = GitOps.new(@repo_path, shell: shell)
  result = git.diff('aaa', 'bbb')
  assert_equal diff_output, result
end

def test_diff_includes_ignore_submodules
  captured = []
  shell = ->(cmd) { captured << cmd; "" }
  git = GitOps.new(@repo_path, shell: shell)
  git.diff('aaa', 'bbb')
  assert_includes captured.first, '--ignore-submodules'
  assert_includes captured.first, 'aaa..bbb'
end

def test_last_commit_before_returns_hash
  shell = ->(cmd) {
    cmd.include?("git log") ? "abc123def456\n" : ""
  }
  git = GitOps.new(@repo_path, shell: shell)
  result = git.last_commit_before(Date.new(2026, 4, 5), 'master')
  assert_equal 'abc123def456', result
end

def test_last_commit_before_returns_empty_when_none
  shell = ->(cmd) { "" }
  git = GitOps.new(@repo_path, shell: shell)
  result = git.last_commit_before(Date.new(2026, 4, 5), 'master')
  assert_equal '', result
end
```

- [ ] **Step 2: テスト実行して fail 確認**

```bash
rake test
```

- [ ] **Step 3: 実装**

`trunk_changes.rb` の `GitOps` クラスに追加（`show` メソッドの後）:

```ruby
def diff(from, to)
  run("git diff --ignore-submodules #{from}..#{to}")
end

def last_commit_before(date, branch)
  before = "#{date.strftime('%Y-%m-%d')} 00:00:00 +0900"
  run("git log #{branch} --before=\"#{before}\" -1 --format='%H'").strip
end
```

- [ ] **Step 4: テスト実行して green 確認**

```bash
rake test
```

- [ ] **Step 5: コミット**

```bash
git add trunk_changes.rb test/test_trunk_changes.rb
git commit -m "feat: add GitOps#diff and #last_commit_before"
```

---

## Task 3: TrunkChangesCollector を時系列 diff に変更

**Files:**
- Modify: `~/dev/src/github.com/bash0C7/trunk-changes-diary/trunk_changes.rb:510-563`
- Test: `~/dev/src/github.com/bash0C7/trunk-changes-diary/test/test_trunk_changes_collector.rb`

- [ ] **Step 1: テストを書く**

`test/test_trunk_changes_collector.rb` に追加:

```ruby
def test_collect_uses_diff_with_previous_commit
  captured_diffs = []
  git = Object.new
  def git.commits_for_date(date, branch) = ['hash1', 'hash2']
  def git.commit_metadata(hash)
    { author: 'dev', datetime: '2026-04-05 10:00:00 +0900', message: 'fix' }
  end
  def git.is_merge?(hash) = false
  def git.merge_log(hash) = nil
  def git.last_commit_before(date, branch) = 'prev_hash'
  def git.submodule_changes(hash) = []

  git.define_singleton_method(:diff) do |from, to|
    captured_diffs << [from, to]
    "diff --git a/foo.rb\n+line"
  end

  gen = Object.new
  def gen.call(context:) = "article"

  collector = TrunkChangesCollector.new(
    repo: 'picoruby/picoruby', branch: 'master',
    source_diff: 'test/diff', source_article: 'test/article',
    git_ops: git, content_generator: gen
  )
  collector.collect(since: '2026-04-05', before: '2026-04-06')

  assert_equal ['prev_hash', 'hash1'], captured_diffs[0]
  assert_equal ['hash1', 'hash2'], captured_diffs[1]
end
```

- [ ] **Step 2: テスト実行して fail 確認**

```bash
rake test
```

- [ ] **Step 3: 既存テストの stub を更新**

`test/test_trunk_changes_collector.rb` の `setup` メソッド内の `@git` stub に追加:

```ruby
def @git.last_commit_before(date, branch) = ''
def @git.diff(from, to) = "diff --git a/foo.rb ...\n+added line"
def @git.submodule_changes(hash) = []
```

既存の `def @git.show(hash)` 行を削除（もう使わない）。

- [ ] **Step 4: TrunkChangesCollector を書き換え**

```ruby
class TrunkChangesCollector
  def initialize(repo:, branch:, source_diff:, source_article:,
                 git_ops:, content_generator:)
    @branch           = branch
    @source_diff      = source_diff
    @source_article   = source_article
    @git              = git_ops
    @generator        = content_generator
  end

  def collect(since:, before:)
    prev_hash = @git.last_commit_before(Date.parse(since), @branch)

    date_range(since, before).flat_map do |date|
      hashes = @git.commits_for_date(date, @branch)
      next [] if hashes.empty?

      contexts = hashes.map do |hash|
        ctx = build_context(hash, prev_hash)
        prev_hash = hash
        ctx
      end

      combined  = contexts.map { |ctx| ctx[:show_output] }.join("\n\n---\n\n")
      daily_ctx = { date: date, commits: contexts }
      article   = @generator.call(context: daily_ctx)

      [
        { content: combined, source: @source_diff,    date: date },
        { content: article,  source: @source_article, date: date }
      ]
    end
  end

  private

  def date_range(since, before)
    start_date = Date.parse(since)
    end_date   = Date.parse(before) - 1
    (start_date..end_date).to_a
  end

  def build_context(hash, prev_hash)
    metadata  = @git.commit_metadata(hash)
    is_merge  = @git.is_merge?(hash)
    merge_log = is_merge ? @git.merge_log(hash) : nil

    diff_output = if prev_hash && !prev_hash.empty?
                    header = "commit #{hash}\nAuthor: #{metadata[:author]}\nDate:   #{metadata[:datetime]}\n\n    #{metadata[:message]}\n"
                    "#{header}\n#{@git.diff(prev_hash, hash)}"
                  else
                    "commit #{hash}\n(no previous commit available)\n"
                  end

    {
      hash:               hash,
      metadata:           metadata,
      show_output:        diff_output,
      is_merge:           is_merge,
      merge_log:          merge_log,
      submodule_changes:  @git.submodule_changes(hash),
    }
  end
end
```

- [ ] **Step 5: テスト実行して green 確認**

```bash
rake test
```

- [ ] **Step 6: コミット**

```bash
git add trunk_changes.rb test/test_trunk_changes_collector.rb
git commit -m "feat: switch TrunkChangesCollector to time-series diff with prev_hash tracking"
```

---

## Task 4: GitOps#submodule_changes を追加（submodule_updates を置き換え）

**Files:**
- Modify: `~/dev/src/github.com/bash0C7/trunk-changes-diary/trunk_changes.rb:123-129`
- Test: `~/dev/src/github.com/bash0C7/trunk-changes-diary/test/test_trunk_changes.rb`

- [ ] **Step 1: テストを書く**

`test/test_trunk_changes.rb` の `TestGitOpsDependencies` 内の submodule テスト3つを以下に書き換え:

```ruby
def test_submodule_changes_returns_empty_for_non_submodule_commit
  diff = "diff --git a/lib/foo.rb b/lib/foo.rb\n+added line\n"
  shell = fake_shell('git show' => diff)
  git   = GitOps.new(@repo_path, shell: shell)
  assert_equal [], git.submodule_changes('abc123')
end

def test_submodule_changes_returns_path_and_sha_range
  diff = <<~DIFF
    diff --git a/mruby b/mruby
    index abc1234..def5678 160000
    Submodule mruby abc1234...def5678:
      > Add feature X
  DIFF
  shell = fake_shell('git show' => diff)
  git   = GitOps.new(@repo_path, shell: shell)
  result = git.submodule_changes('abc123')
  assert_equal 1, result.size
  assert_equal 'mruby', result[0][:path]
  assert_equal 'abc1234', result[0][:old_sha]
  assert_equal 'def5678', result[0][:new_sha]
end

def test_submodule_changes_returns_multiple
  diff = <<~DIFF
    Submodule mruby abc1234...def5678:
      > fix
    Submodule lib/mrubyc aaa1111...bbb2222:
      > update
  DIFF
  shell = fake_shell('git show' => diff)
  git   = GitOps.new(@repo_path, shell: shell)
  result = git.submodule_changes('abc123')
  assert_equal 2, result.size
  assert_equal 'mruby', result[0][:path]
  assert_equal 'lib/mrubyc', result[1][:path]
end
```

- [ ] **Step 2: テスト実行して fail 確認**

```bash
rake test
```

- [ ] **Step 3: 実装**

`trunk_changes.rb` の `submodule_updates` を `submodule_changes` に置き換え:

```ruby
def submodule_changes(hash)
  changes = []
  run("git show --submodule=short --ignore-all-space #{hash}").each_line do |line|
    if line =~ /^Submodule (\S+) ([0-9a-f]+)\.\.\.?([0-9a-f]+)/
      changes << { path: $1, old_sha: $2, new_sha: $3 }
    end
  end
  changes
end
```

旧 `submodule_updates` メソッドを削除。

- [ ] **Step 4: テスト実行して green 確認**

```bash
rake test
```

- [ ] **Step 5: コミット**

```bash
git add trunk_changes.rb test/test_trunk_changes.rb
git commit -m "feat: replace submodule_updates with submodule_changes (returns SHA ranges)"
```

---

## Task 5: GitOps#submodule_log と submodule_diff_stat を追加

**Files:**
- Modify: `~/dev/src/github.com/bash0C7/trunk-changes-diary/trunk_changes.rb`
- Test: `~/dev/src/github.com/bash0C7/trunk-changes-diary/test/test_trunk_changes.rb`

- [ ] **Step 1: テストを書く**

`test/test_trunk_changes.rb` の `TestGitOpsDependencies` に追加:

```ruby
def test_submodule_log_returns_oneline_log
  log = "abc1234 Add feature\ndef5678 Fix bug\n"
  shell = ->(cmd) {
    cmd.include?("git log --oneline") ? log : ""
  }
  git = GitOps.new(@repo_path, shell: shell)
  # submodule_log uses Dir.chdir to submodule path, mock via shell
  FileUtils.mkdir_p(File.join(@repo_path, 'mruby'))
  result = git.submodule_log('mruby', 'aaa', 'bbb')
  assert_equal log.strip, result.strip
end

def test_submodule_diff_stat_returns_stat
  stat = " foo.c | 10 ++++---\n 1 file changed\n"
  shell = ->(cmd) {
    cmd.include?("git diff --stat") ? stat : ""
  }
  git = GitOps.new(@repo_path, shell: shell)
  FileUtils.mkdir_p(File.join(@repo_path, 'mruby'))
  result = git.submodule_diff_stat('mruby', 'aaa', 'bbb')
  assert_includes result, 'foo.c'
end
```

- [ ] **Step 2: テスト実行して fail 確認**

```bash
rake test
```

- [ ] **Step 3: 実装**

`trunk_changes.rb` の `GitOps` に追加:

```ruby
def submodule_log(path, old_sha, new_sha)
  sub_path = File.join(@repo_path, path)
  Dir.chdir(sub_path) { @shell.call("git log --oneline #{old_sha}..#{new_sha}") }.strip
end

def submodule_diff_stat(path, old_sha, new_sha)
  sub_path = File.join(@repo_path, path)
  Dir.chdir(sub_path) { @shell.call("git diff --stat #{old_sha}..#{new_sha}") }.strip
end
```

- [ ] **Step 4: テスト実行して green 確認**

```bash
rake test
```

- [ ] **Step 5: コミット**

```bash
git add trunk_changes.rb test/test_trunk_changes.rb
git commit -m "feat: add GitOps#submodule_log and #submodule_diff_stat"
```

---

## Task 6: TrunkChangesCollector に submodule 記事生成を追加

**Files:**
- Modify: `~/dev/src/github.com/bash0C7/trunk-changes-diary/trunk_changes.rb` (TrunkChangesCollector#collect)
- Test: `~/dev/src/github.com/bash0C7/trunk-changes-diary/test/test_trunk_changes_collector.rb`

- [ ] **Step 1: テストを書く**

`test/test_trunk_changes_collector.rb` に追加:

```ruby
def test_collect_generates_submodule_articles
  git = Object.new
  def git.commits_for_date(date, branch) = ['merge1']
  def git.commit_metadata(hash)
    { author: 'dev', datetime: '2026-04-04 10:00:00 +0900', message: 'Merge PR #382' }
  end
  def git.is_merge?(hash) = true
  def git.merge_log(hash) = "abc Add feature"
  def git.last_commit_before(date, branch) = 'prev1'
  def git.diff(from, to) = "diff output"
  def git.submodule_changes(hash)
    [{ path: 'mrbgems/picoruby-mruby/lib/mruby', old_sha: 'aaa', new_sha: 'bbb' }]
  end
  def git.submodule_log(path, old_sha, new_sha) = "ccc Fix\nddd Update"
  def git.submodule_diff_stat(path, old_sha, new_sha) = " foo.c | 5 +++--"

  captured_contexts = []
  gen = Object.new
  gen.define_singleton_method(:call) do |context:|
    captured_contexts << context
    "generated article"
  end

  collector = TrunkChangesCollector.new(
    repo: 'picoruby/picoruby', branch: 'master',
    source_diff: 'picoruby/picoruby:trunk/diff',
    source_article: 'picoruby/picoruby:trunk/article',
    git_ops: git, content_generator: gen
  )
  results = collector.collect(since: '2026-04-04', before: '2026-04-05')

  # 3 records: diff + main article + submodule article
  assert_equal 3, results.size
  assert_equal 'picoruby/picoruby:trunk/diff', results[0][:source]
  assert_equal 'picoruby/picoruby:trunk/article', results[1][:source]
  assert_equal 'picoruby/picoruby:trunk/article/mruby', results[2][:source]
end

def test_collect_no_submodule_records_when_no_changes
  git = Object.new
  def git.commits_for_date(date, branch) = ['hash1']
  def git.commit_metadata(hash)
    { author: 'dev', datetime: '2026-04-05 10:00:00 +0900', message: 'Fix' }
  end
  def git.is_merge?(hash) = false
  def git.merge_log(hash) = nil
  def git.last_commit_before(date, branch) = 'prev1'
  def git.diff(from, to) = "diff output"
  def git.submodule_changes(hash) = []

  gen = Object.new
  def gen.call(context:) = "article"

  collector = TrunkChangesCollector.new(
    repo: 'picoruby/picoruby', branch: 'master',
    source_diff: 'picoruby/picoruby:trunk/diff',
    source_article: 'picoruby/picoruby:trunk/article',
    git_ops: git, content_generator: gen
  )
  results = collector.collect(since: '2026-04-05', before: '2026-04-06')

  assert_equal 2, results.size  # diff + article only
end
```

- [ ] **Step 2: テスト実行して fail 確認**

```bash
rake test
```

- [ ] **Step 3: collect メソッドに submodule 記事生成を追加**

`TrunkChangesCollector#collect` の `flat_map` ブロック末尾を修正:

```ruby
def collect(since:, before:)
  prev_hash = @git.last_commit_before(Date.parse(since), @branch)

  date_range(since, before).flat_map do |date|
    hashes = @git.commits_for_date(date, @branch)
    next [] if hashes.empty?

    contexts = hashes.map do |hash|
      ctx = build_context(hash, prev_hash)
      prev_hash = hash
      ctx
    end

    combined  = contexts.map { |ctx| ctx[:show_output] }.join("\n\n---\n\n")
    daily_ctx = { date: date, commits: contexts }
    article   = @generator.call(context: daily_ctx)

    records = [
      { content: combined, source: @source_diff,    date: date },
      { content: article,  source: @source_article, date: date }
    ]

    # submodule articles
    contexts.each do |ctx|
      ctx[:submodule_changes].each do |sub|
        sub_ctx = build_submodule_context(sub)
        sub_article = @generator.call(context: sub_ctx)
        sub_name = File.basename(sub[:path])
        records << { content: sub_article, source: "#{@source_article}/#{sub_name}", date: date }
      end
    end

    records
  end
end
```

`build_submodule_context` を private に追加:

```ruby
def build_submodule_context(sub)
  log  = @git.submodule_log(sub[:path], sub[:old_sha], sub[:new_sha])
  stat = @git.submodule_diff_stat(sub[:path], sub[:old_sha], sub[:new_sha])
  {
    submodule:      true,
    submodule_path: sub[:path],
    submodule_name: File.basename(sub[:path]),
    show_output:    "## Commits\n#{log}\n\n## Changed files\n#{stat}",
  }
end
```

- [ ] **Step 4: テスト実行して green 確認**

```bash
rake test
```

- [ ] **Step 5: コミット**

```bash
git add trunk_changes.rb test/test_trunk_changes_collector.rb
git commit -m "feat: generate submodule articles in TrunkChangesCollector"
```

---

## Task 7: ContentGenerator に submodule 記事用プロンプトを追加

**Files:**
- Modify: `~/dev/src/github.com/bash0C7/trunk-changes-diary/trunk_changes.rb` (ContentGenerator#call, +build_submodule_prompt)
- Test: `~/dev/src/github.com/bash0C7/trunk-changes-diary/test/test_trunk_changes.rb`

- [ ] **Step 1: テストを書く**

`test/test_trunk_changes.rb` の `TestContentGenerator` に追加:

```ruby
def test_submodule_prompt_includes_path_and_log
  captured = nil
  runner = ->(p) { captured = p; "submodule article" }
  gen = ContentGenerator.new(repo: 'picoruby/picoruby', runner: runner, wait: false)

  ctx = {
    submodule: true,
    submodule_path: 'mrbgems/picoruby-mruby/lib/mruby',
    submodule_name: 'mruby',
    show_output: "## Commits\nabc Fix\ndef Update\n\n## Changed files\n foo.c | 5 +++--",
  }
  result = gen.call(context: ctx)
  assert_equal 'submodule article', result
  assert_includes captured, 'mruby'
  assert_includes captured, 'サブモジュール'
  assert_includes captured, 'abc Fix'
end
```

- [ ] **Step 2: テスト実行して fail 確認**

```bash
rake test
```

- [ ] **Step 3: ContentGenerator#call に分岐追加 + build_submodule_prompt 実装**

`ContentGenerator#call` の prompt 選択を修正:

```ruby
def call(context:)
  prompt = if context[:submodule]
             build_submodule_prompt(context)
           elsif context[:commits]
             build_daily_prompt(context)
           else
             build_prompt(context)
           end
  # ... 以下は既存のまま
```

`build_submodule_prompt` を private に追加:

```ruby
def build_submodule_prompt(ctx)
  name = ctx[:submodule_name]
  path = ctx[:submodule_path]
  parts = []
  parts << "以下のサブモジュール「#{name}」（パス: #{path}）の更新について、trunk-changes ブログ記事を日本語（ですます調）で執筆してください。"
  parts << "このサブモジュールは #{@repo} リポジトリの一部です。"
  if @prompt_supplement && !@prompt_supplement.to_s.strip.empty?
    parts << @prompt_supplement
  end
  parts << ""
  parts << ctx[:show_output]
  parts << ""
  parts << "## 出力フォーマット"
  parts << "Markdownのみ出力。前置き・後書き不要。"
  parts << "タイトルにサブモジュール名「#{name}」を含めること。"
  parts << "このサブモジュール更新が親リポジトリ（#{@repo}）にとって何を意味するか考察すること。"
  parts << "不要な太字などの装飾なし。"
  parts.join("\n")
end
```

- [ ] **Step 4: テスト実行して green 確認**

```bash
rake test
```

- [ ] **Step 5: コミット**

```bash
git add trunk_changes.rb test/test_trunk_changes.rb
git commit -m "feat: add submodule article prompt to ContentGenerator"
```

---

## Task 8: Rakefile の write_md を submodule 記事対応に変更

**Files:**
- Modify: `~/dev/src/github.com/bash0C7/ruby-knowledge-db/Rakefile:67-80`

- [ ] **Step 1: 現状の問題**

現在 `fname = "#{date}-#{type}.md"` なので、submodule 記事は main article と同じファイル名で上書きされる。source から submodule 名を抽出してファイル名に含める。

- [ ] **Step 2: write_md を修正**

```ruby
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
    source: #{source}
    date: #{date}
    type: #{type}
    ---
    #{record[:content]}
  MD
  File.write(File.join(dir, fname), content)
end
```

- [ ] **Step 3: ruby-knowledge-db テスト実行**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-knowledge-db && bundle exec rake test
```

- [ ] **Step 4: コミット**

```bash
git add Rakefile
git commit -m "feat: write_md supports submodule article filenames"
```

---

## Task 9: generator テストの stub 更新（3リポジトリ）

**Files:**
- Modify: `~/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator/test/test_picoruby_trunk_changes_generator.rb`
- Modify: `~/dev/src/github.com/bash0C7/cruby-trunk-changes-generator/test/test_cruby_trunk_changes_generator.rb`
- Modify: `~/dev/src/github.com/bash0C7/mruby-trunk-changes-generator/test/test_mruby_trunk_changes_generator.rb`

- [ ] **Step 1: picoruby stub 更新**

`@fake_git` の setup で、既存の `show`, `is_merge?`, `merge_log` を以下に置き換え:

```ruby
def @fake_git.last_commit_before(date, branch) = ''
def @fake_git.diff(from, to) = "diff --git a/foo.rb ...\n+line"
def @fake_git.is_merge?(hash) = false
def @fake_git.merge_log(hash) = nil
def @fake_git.submodule_changes(hash) = []
```

旧 `def @fake_git.show(hash)` 行を削除。

- [ ] **Step 2: cruby stub 更新**

同じ変更を適用。`show` → 削除、上記メソッド追加。

- [ ] **Step 3: mruby stub 更新**

同じ変更を適用。

- [ ] **Step 4: 各テスト実行**

```bash
cd ~/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator && bundle exec rake test
cd ~/dev/src/github.com/bash0C7/cruby-trunk-changes-generator && bundle exec rake test
cd ~/dev/src/github.com/bash0C7/mruby-trunk-changes-generator && bundle exec rake test
```

- [ ] **Step 5: 各リポジトリでコミット**

```bash
cd ~/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator
git add test/test_picoruby_trunk_changes_generator.rb
git commit -m "fix: update test stubs for time-series diff and submodule changes"

cd ~/dev/src/github.com/bash0C7/cruby-trunk-changes-generator
git add test/test_cruby_trunk_changes_generator.rb
git commit -m "fix: update test stubs for time-series diff and submodule changes"

cd ~/dev/src/github.com/bash0C7/mruby-trunk-changes-generator
git add test/test_mruby_trunk_changes_generator.rb
git commit -m "fix: update test stubs for time-series diff and submodule changes"
```

---

## Task 10: 旧コード削除（show の parent lookup、shallow 関連）

**Files:**
- Modify: `~/dev/src/github.com/bash0C7/trunk-changes-diary/trunk_changes.rb`
- Test: `~/dev/src/github.com/bash0C7/trunk-changes-diary/test/test_trunk_changes.rb`

- [ ] **Step 1: GitOps#show の parent lookup を簡素化**

`show` メソッドを単純なヘッダ表示のみに変更（`extract_file_snippets` が使うため残す）:

```ruby
def show(hash)
  run("git log -1 --format='commit %H%nAuthor: %an <%ae>%nDate:   %ci%n%n    %s%n%n' #{hash}") +
    run("git diff-tree -p --ignore-submodules #{hash}")
end
```

- [ ] **Step 2: 旧 show テストを更新**

`test_show_returns_header_and_diff`, `test_show_uses_first_parent_diff_for_merge_commit`, `test_show_falls_back_to_stat_when_no_parent` を削除し、シンプルなテストに置き換え:

```ruby
def test_show_returns_commit_info
  header = "commit abc123\nAuthor: dev <dev@example.com>\n"
  diff = "diff --git a/foo.rb b/foo.rb\n+line\n"
  shell = ->(cmd) {
    if cmd.include?("git log -1 --format")
      header
    elsif cmd.include?("git diff-tree")
      diff
    else
      ""
    end
  }
  git = GitOps.new(@repo_path, shell: shell)
  result = git.show('abc123')
  assert_includes result, "commit abc123"
  assert_includes result, "diff --git a/foo.rb"
end
```

- [ ] **Step 3: 旧 `submodule_updates` テストが `submodule_changes` に置き換わっていることを確認**

Task 4 で置き換え済み。残骸がないか grep:

```bash
grep -n 'submodule_updates' test/test_trunk_changes.rb test/test_trunk_changes_collector.rb
```

残っていたら削除。

- [ ] **Step 4: テスト実行して green 確認**

```bash
rake test
```

- [ ] **Step 5: コミット**

```bash
git add trunk_changes.rb test/test_trunk_changes.rb
git commit -m "refactor: simplify show method, remove shallow-related code"
```

---

## Task 11: E2E 検証

- [ ] **Step 1: /tmp の旧 clone を削除**

```bash
rm -rf /tmp/trunk-changes-repos/picoruby
```

- [ ] **Step 2: Phase 1 実行（2日分）**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-knowledge-db
APP_ENV=test SINCE=2026-04-04 BEFORE=2026-04-06 bundle exec rake generate:picoruby_trunk
```

Expected:
- `Generated N records`（N > 4: main diff + article + submodule articles）
- `DIR=...`

- [ ] **Step 3: ファイル確認**

```bash
ls -lh $DIR
```

Expected:
- `2026-04-04-diff.md` — 数KB（63MB ではない）
- `2026-04-04-article.md` — 正常な技術記事
- `2026-04-04-article-mruby.md` 等 — submodule 記事（あれば）
- `2026-04-05-*` — 同様

- [ ] **Step 4: article 内容確認**

```bash
head -15 $DIR/2026-04-04-article.md
head -15 $DIR/2026-04-04-article-*.md 2>/dev/null
```

- [ ] **Step 5: Phase 2a import**

```bash
APP_ENV=test DIR=$DIR bundle exec rake import:picoruby_trunk
```

- [ ] **Step 6: Phase 2b esa**

```bash
APP_ENV=test DIR=$DIR bundle exec rake esa:picoruby_trunk
```

- [ ] **Step 7: 問題があれば修正してコミット**

---

## Task 12: 全リポジトリ push

- [ ] **Step 1: trunk-changes-diary**

```bash
cd ~/dev/src/github.com/bash0C7/trunk-changes-diary && git push
```

- [ ] **Step 2: ruby-knowledge-db**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-knowledge-db && git push
```

- [ ] **Step 3: picoruby/cruby/mruby generators**

```bash
cd ~/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator && git push
cd ~/dev/src/github.com/bash0C7/cruby-trunk-changes-generator && git push
cd ~/dev/src/github.com/bash0C7/mruby-trunk-changes-generator && git push
```

- [ ] **Step 4: CLAUDE.md 更新**

`ruby-knowledge-db/CLAUDE.md` の merge commit / shallow 関連の記述を更新:
- shallow-since の記述を削除
- full clone + 時系列 diff の説明に変更
- submodule 記事の source 値規約を追加

```bash
cd ~/dev/src/github.com/bash0C7/ruby-knowledge-db
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for full clone and submodule article generation"
git push
```
