# Merge Commit-Aware Diff Generation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `TrunkChangesCollector` が merge commit と直接 push を区別し、merge commit は PR 全体の変更を1記事としてまとめる。shallow clone 起因の巨大 diff 問題を根本解決する。

**Architecture:**
main ブランチの daily コミット一覧を取得後、各コミットを merge / non-merge に分類。
merge commit は `M^1..M` の diff（main 側親との差分 = PR 全体）を使い、含まれるコミット一覧も付与。
non-merge commit（直接 push / rebase）は従来通り個別に diff を取得。
shallow clone の深さを `-2 day` に拡大し、`M^1` が確実に取得できるようにする。

**Tech Stack:** Ruby 4.0.1, trunk_changes_diary gem, test-unit / minitest, git

---

## Context

### 解決する問題

1. **shallow boundary の merge commit** で `git show` が全ツリー展開 → 63-126MB の diff
2. `git diff parent..hash` の修正を入れたが、merge commit の `M^1` 自体が shallow で取得不可なケースが残る
3. merge commit の feature branch 側の個々のコミットを別々に解説しても冗長

### 設計判断

- **merge commit**: `git diff M^1..M --ignore-submodules` で PR 全体の変更を取得。`git log M^1..M --oneline` で含まれるコミット一覧を付与。1記事にまとめる
- **non-merge commit**: 従来通り `git diff parent..hash --ignore-submodules` で個別 diff
- **shallow-since**: `since_date - 2` に拡大（merge commit の M^1 が前日以前のケース対応）
- **submodule**: `--ignore-submodules` で除外（将来別コンテキストで対応予定）

### 影響ファイル

| ファイル | 変更内容 |
|---------|---------|
| `trunk-changes-diary/trunk_changes.rb` | `GitOps#show` → merge/non-merge 分岐、`GitOps#merge_log` 追加、shallow-since -2day |
| `trunk-changes-diary/test/test_trunk_changes.rb` | GitOps テスト追加・修正 |
| `trunk-changes-diary/trunk_changes.rb` | `ContentGenerator#build_daily_prompt` にマージ情報セクション追加 |
| `trunk-changes-diary/test/test_trunk_changes_collector.rb` | Collector テスト更新 |

---

## Task 1: GitOps#is_merge? と GitOps#merge_log を追加

**Files:**
- Modify: `trunk-changes-diary/trunk_changes.rb` (GitOps クラス)
- Test: `trunk-changes-diary/test/test_trunk_changes.rb` (TestGitOps)

- [ ] **Step 1: `is_merge?` のテストを書く**

`test/test_trunk_changes.rb` の `TestGitOps` クラスに追加:

```ruby
def test_is_merge_returns_true_for_merge_commit
  shell = ->(cmd) {
    cmd.include?("%P") ? "parent1 parent2" : ""
  }
  git = GitOps.new(@repo_path, shell: shell)
  assert git.is_merge?('abc123')
end

def test_is_merge_returns_false_for_regular_commit
  shell = ->(cmd) {
    cmd.include?("%P") ? "parent1" : ""
  }
  git = GitOps.new(@repo_path, shell: shell)
  refute git.is_merge?('abc123')
end
```

- [ ] **Step 2: テスト実行して fail 確認**

```bash
cd ~/dev/src/github.com/bash0C7/trunk-changes-diary
rake test
```

Expected: `NoMethodError: undefined method 'is_merge?'`

- [ ] **Step 3: `is_merge?` を実装**

`trunk_changes.rb` の `GitOps` クラスに追加（`show` メソッドの後）:

```ruby
def is_merge?(hash)
  parents = run("git log -1 --format='%P' #{hash}").strip.split
  parents.size > 1
end
```

- [ ] **Step 4: テスト実行して green 確認**

```bash
rake test
```

Expected: PASS

- [ ] **Step 5: `merge_log` のテストを書く**

```ruby
def test_merge_log_returns_oneline_commits
  log_output = "abc1234 Add feature X\ndef5678 Fix bug Y\n"
  shell = ->(cmd) {
    if cmd.include?("git log") && cmd.include?("--oneline")
      log_output
    elsif cmd.include?("%P")
      "parent1 parent2"
    else
      ""
    end
  }
  git = GitOps.new(@repo_path, shell: shell)
  result = git.merge_log('merge_hash')
  assert_equal log_output.strip, result
end
```

- [ ] **Step 6: テスト実行して fail 確認**

```bash
rake test
```

Expected: `NoMethodError: undefined method 'merge_log'`

- [ ] **Step 7: `merge_log` を実装**

```ruby
def merge_log(hash)
  first_parent = run("git log -1 --format='%P' #{hash}").strip.split.first
  run("git log --oneline #{first_parent}..#{hash}").strip
end
```

- [ ] **Step 8: テスト実行して green 確認**

```bash
rake test
```

Expected: ALL PASS

- [ ] **Step 9: コミット**

```bash
cd ~/dev/src/github.com/bash0C7/trunk-changes-diary
git add trunk_changes.rb test/test_trunk_changes.rb
git commit -m "feat: add is_merge? and merge_log to GitOps"
```

---

## Task 2: GitOps#show を merge commit 対応に書き換え

**Files:**
- Modify: `trunk-changes-diary/trunk_changes.rb` (GitOps#show)
- Test: `trunk-changes-diary/test/test_trunk_changes.rb` (TestGitOps)

- [ ] **Step 1: merge commit 用の show テストを書く**

`test/test_trunk_changes.rb` の `TestGitOps` に追加:

```ruby
def test_show_uses_first_parent_diff_for_merge_commit
  header = "commit merge123\nAuthor: dev <dev@example.com>\nDate:   2026-04-04\n\n    Merge pull request #382\n"
  diff   = "diff --git a/hal.c b/hal.c\n+new code\n"
  shell  = ->(cmd) {
    if cmd.include?("git log -1 --format") && cmd.include?("%P")
      "parent1 parent2"
    elsif cmd.include?("git log -1 --format")
      header
    elsif cmd.include?("git diff") && cmd.include?("parent1..merge123")
      diff
    else
      ""
    end
  }
  git    = GitOps.new(@repo_path, shell: shell)
  result = git.show('merge123')
  assert_includes result, "Merge pull request #382"
  assert_includes result, "diff --git a/hal.c"
end

def test_show_falls_back_to_diff_tree_when_parent_missing
  header = "commit orphan1\nAuthor: dev <dev@example.com>\nDate: 2026-04-04\n\n    Init\n"
  stat   = " hal.c | 10 +++++++---\n 1 file changed, 7 insertions(+), 3 deletions(-)\n"
  shell  = ->(cmd) {
    if cmd.include?("git log -1 --format") && cmd.include?("%P")
      ""
    elsif cmd.include?("git log -1 --format")
      header
    elsif cmd.include?("git diff-tree") && cmd.include?("--stat")
      stat
    else
      ""
    end
  }
  git    = GitOps.new(@repo_path, shell: shell)
  result = git.show('orphan1')
  assert_includes result, "Init"
  assert_includes result, "hal.c"
end
```

- [ ] **Step 2: テスト実行して fail 確認**

```bash
rake test
```

Expected: merge commit のテストが fail（現行の show は M^1 を正しく使えてない）

- [ ] **Step 3: `show` メソッドを書き換え**

`trunk_changes.rb` の `GitOps#show` を以下に置き換え:

```ruby
def show(hash)
  header  = run("git log -1 --format='commit %H%nAuthor: %an <%ae>%nDate:   %ci%n%n    %s%n' #{hash}")
  parents = run("git log -1 --format='%P' #{hash}").strip.split

  diff = if parents.empty?
           # orphan or shallow boundary with no parent — stat only
           run("git diff-tree --stat --ignore-submodules #{hash}")
         else
           first_parent = parents.first
           run("git diff --ignore-submodules #{first_parent}..#{hash}")
         end

  "#{header}\n#{diff}"
end
```

ポイント:
- merge commit でも non-merge でも `parents.first` を使う（`M^1` = main 側親）
- 親が取得不可（空文字列）の場合は `--stat` のみで安全にフォールバック
- `--ignore-submodules` で submodule diff を除外

- [ ] **Step 4: テスト実行して green 確認**

```bash
rake test
```

Expected: ALL PASS（既存テスト `test_show_returns_header_and_diff` も含めて全 green）

- [ ] **Step 5: コミット**

```bash
git add trunk_changes.rb test/test_trunk_changes.rb
git commit -m "fix: show uses first-parent diff, stat-only fallback for orphan commits"
```

---

## Task 3: shallow-since を -2 day に拡大

**Files:**
- Modify: `trunk-changes-diary/trunk_changes.rb` (GitOps#setup)
- Test: `trunk-changes-diary/test/test_trunk_changes.rb`

- [ ] **Step 1: テストを書く**

`test/test_trunk_changes.rb` の `TestGitOps` に追加:

```ruby
def test_setup_subtracts_2_days_from_since_date_for_shallow
  captured = []
  shell = ->(cmd) { captured << cmd; "" }
  git = GitOps.new(@repo_path, shell: shell)
  FileUtils.mkdir_p(File.join(@repo_path, '.git'))
  git.setup('https://example.com/repo.git', 'master', since_date: '2026-04-05')
  fetch_cmd = captured.find { |c| c.include?('git fetch') }
  assert_includes fetch_cmd, '--shallow-since=2026-04-03',
    "Expected since_date - 2 days (2026-04-03), got: #{fetch_cmd}"
end
```

- [ ] **Step 2: テスト実行して fail 確認**

```bash
rake test
```

Expected: FAIL（現行は -1 day で `2026-04-04` になる）

- [ ] **Step 3: `setup` の shallow 日数を変更**

`trunk_changes.rb` line 18 を変更:

```ruby
# 変更前
shallow_date = (Date.parse(since_date) - 1).strftime('%Y-%m-%d')
# 変更後
shallow_date = (Date.parse(since_date) - 2).strftime('%Y-%m-%d')
```

- [ ] **Step 4: テスト実行して green 確認**

```bash
rake test
```

Expected: ALL PASS

- [ ] **Step 5: コミット**

```bash
git add trunk_changes.rb test/test_trunk_changes.rb
git commit -m "fix: extend shallow-since margin to -2 days for merge commit parent availability"
```

---

## Task 4: TrunkChangesCollector#build_context に merge 情報を追加

**Files:**
- Modify: `trunk-changes-diary/trunk_changes.rb` (TrunkChangesCollector#build_context)
- Test: `trunk-changes-diary/test/test_trunk_changes_collector.rb`

- [ ] **Step 1: テストを書く**

`test/test_trunk_changes_collector.rb` に追加:

```ruby
def test_build_context_includes_merge_info_for_merge_commit
  git = Object.new
  def git.commits_for_date(date, branch) = ['merge1']
  def git.show(hash) = "diff --git a/foo.rb ...\n+line"
  def git.commit_metadata(hash)
    { author: 'dev', datetime: '2026-04-04 10:00:00 +0900', message: 'Merge pull request #382' }
  end
  def git.is_merge?(hash) = true
  def git.merge_log(hash) = "abc1234 Add feature\ndef5678 Fix bug"

  gen = Object.new
  def gen.call(context:) = "article content"

  collector = TrunkChangesCollector.new(
    repo: 'picoruby/picoruby', branch: 'master',
    source_diff: 'picoruby/picoruby:trunk/diff',
    source_article: 'picoruby/picoruby:trunk/article',
    git_ops: git, content_generator: gen
  )
  results = collector.collect(since: '2026-04-04', before: '2026-04-05')
  diff_content = results[0][:content]
  assert_includes diff_content, "diff --git a/foo.rb"
end

def test_build_context_includes_merge_log_in_context
  captured_ctx = nil
  git = Object.new
  def git.commits_for_date(date, branch) = ['merge1']
  def git.show(hash) = "diff output"
  def git.commit_metadata(hash)
    { author: 'dev', datetime: '2026-04-04 10:00:00 +0900', message: 'Merge pull request #382' }
  end
  def git.is_merge?(hash) = true
  def git.merge_log(hash) = "abc1234 Add feature\ndef5678 Fix bug"

  gen = Object.new
  define_method_on = gen
  captured_ctx_ref = []
  gen.define_singleton_method(:call) do |context:|
    captured_ctx_ref[0] = context
    "article"
  end

  collector = TrunkChangesCollector.new(
    repo: 'picoruby/picoruby', branch: 'master',
    source_diff: 'picoruby/picoruby:trunk/diff',
    source_article: 'picoruby/picoruby:trunk/article',
    git_ops: git, content_generator: gen
  )
  collector.collect(since: '2026-04-04', before: '2026-04-05')
  ctx = captured_ctx_ref[0]
  commit_ctx = ctx[:commits].first
  assert_equal true, commit_ctx[:is_merge]
  assert_includes commit_ctx[:merge_log], "abc1234 Add feature"
end
```

- [ ] **Step 2: テスト実行して fail 確認**

```bash
rake test
```

Expected: FAIL（`is_merge` / `merge_log` キーが context に含まれてない）

- [ ] **Step 3: `build_context` を修正**

`trunk_changes.rb` の `TrunkChangesCollector#build_context`（line 521-526）を変更:

```ruby
def build_context(hash)
  metadata  = @git.commit_metadata(hash)
  is_merge  = @git.is_merge?(hash)
  merge_log = is_merge ? @git.merge_log(hash) : nil
  {
    hash:               hash,
    metadata:           metadata,
    show_output:        @git.show(hash),
    is_merge:           is_merge,
    merge_log:          merge_log,
    changed_files:      [],
    dependency_files:   [],
    project_meta_files: [],
    issue_contexts:     [],
    submodule_updates:  []
  }
end
```

- [ ] **Step 4: テスト実行して green 確認**

```bash
rake test
```

Expected: ALL PASS

- [ ] **Step 5: コミット**

```bash
git add trunk_changes.rb test/test_trunk_changes_collector.rb
git commit -m "feat: include is_merge and merge_log in TrunkChangesCollector context"
```

---

## Task 5: ContentGenerator#build_daily_prompt にマージ情報セクションを追加

**Files:**
- Modify: `trunk-changes-diary/trunk_changes.rb` (ContentGenerator#build_daily_prompt)
- Test: `trunk-changes-diary/test/test_trunk_changes.rb` (TestContentGenerator)

- [ ] **Step 1: テストを書く**

`test/test_trunk_changes.rb` の `TestContentGenerator` に追加:

```ruby
def test_daily_prompt_includes_merge_info_when_merge_commit
  captured = nil
  runner = ->(p) { captured = p; "article content" }
  gen = ContentGenerator.new(repo: 'owner/repo', runner: runner, wait: false)

  ctx = {
    date: Date.new(2026, 4, 4),
    commits: [{
      hash: 'merge123',
      metadata: { author: 'hasumikin', datetime: '2026-04-04 10:00:00 +0900',
                  message: 'Merge pull request #382 from yuuu/fix/hal-getchar' },
      show_output: "diff --git a/hal.c ...\n+code",
      is_merge: true,
      merge_log: "abc1234 Add ring buffer\ndef5678 Fix signal handling",
      changed_files: [], dependency_files: [], project_meta_files: [],
      issue_contexts: [], submodule_updates: []
    }]
  }
  gen.call(context: ctx)
  assert_includes captured, 'マージコミット'
  assert_includes captured, 'abc1234 Add ring buffer'
  assert_includes captured, 'def5678 Fix signal handling'
  assert_includes captured, 'PR 全体の変更をまとめて'
end

def test_daily_prompt_no_merge_section_for_regular_commit
  captured = nil
  runner = ->(p) { captured = p; "article content" }
  gen = ContentGenerator.new(repo: 'owner/repo', runner: runner, wait: false)

  ctx = {
    date: Date.new(2026, 4, 5),
    commits: [{
      hash: 'regular1',
      metadata: { author: 'yuuu', datetime: '2026-04-05 07:00:00 +0900',
                  message: 'Fix typo in README' },
      show_output: "diff --git a/README.md ...\n+fix",
      is_merge: false,
      merge_log: nil,
      changed_files: [], dependency_files: [], project_meta_files: [],
      issue_contexts: [], submodule_updates: []
    }]
  }
  gen.call(context: ctx)
  refute_includes captured, 'マージコミット'
end
```

- [ ] **Step 2: テスト実行して fail 確認**

```bash
rake test
```

Expected: FAIL（`is_merge` キーがプロンプトに反映されてない）

- [ ] **Step 3: `build_daily_prompt` を修正**

`trunk_changes.rb` の `ContentGenerator#build_daily_prompt`（line 236 あたりのループ内）を変更:

```ruby
commits.each_with_index do |c, i|
  meta = c[:metadata]
  parts << "## コミット #{i + 1}/#{commits.size}: #{c[:hash]}"
  parts << "- 著者: #{meta[:author]}"
  parts << "- 日時: #{meta[:datetime]}"
  parts << "- メッセージ: #{meta[:message]}"
  parts << ""

  if c[:is_merge]
    parts << "### マージコミット（PR 全体の変更をまとめて解説すること）"
    parts << "このコミットは PR のマージです。以下は含まれるコミット一覧:"
    parts << "```"
    parts << c[:merge_log]
    parts << "```"
    parts << "個々のコミットを逐一解説するのではなく、PR 全体として何が変わったかをまとめてください。"
    parts << ""
  end

  parts << "### git diff 出力（差分）"
  parts << c[:show_output]
  parts << ""
end
```

- [ ] **Step 4: テスト実行して green 確認**

```bash
rake test
```

Expected: ALL PASS

- [ ] **Step 5: コミット**

```bash
git add trunk_changes.rb test/test_trunk_changes.rb
git commit -m "feat: add merge commit context to daily article prompt"
```

---

## Task 6: E2E 再検証（Apr 4-5 複数日テスト）

**Files:** ruby-knowledge-db 側の実行

- [ ] **Step 1: repos/picoruby を削除して再クローン**

```bash
rm -rf ~/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator/repos/picoruby
```

- [ ] **Step 2: Phase 1 実行（2日分）**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-knowledge-db
APP_ENV=test SINCE=2026-04-04 BEFORE=2026-04-06 bundle exec rake generate:picoruby_trunk
```

Expected:
```
Generated 4 records
DIR=...
```

- [ ] **Step 3: diff サイズ確認**

```bash
ls -lh $DIR
```

Expected:
- `2026-04-04-diff.md`: 数十KB以下（63MB ではないこと）
- `2026-04-04-article.md`: 正常な技術記事
- `2026-04-05-diff.md`: 14KB 前後
- `2026-04-05-article.md`: 正常な技術記事

- [ ] **Step 4: article 内容確認（Apr 4 = merge commit）**

```bash
head -30 $DIR/2026-04-04-article.md
```

Expected: PR #382 の全体変更をまとめた記事（個々のコミットの逐一解説ではないこと）

- [ ] **Step 5: Phase 2a import 実行**

```bash
APP_ENV=test DIR=$DIR bundle exec rake import:picoruby_trunk
```

Expected: `stored=4, skipped=0`（前回の Apr 5 分 2 件 + Apr 4 分 2 件 = 4。ただし Apr 5 の前回分が残っていれば stored=2, skipped=2）

- [ ] **Step 6: 問題があれば修正してコミット**

---

## Task 7: 全リポジトリ commit & push

全タスク完了後、変更のあるリポジトリをコミット・push。

- [ ] **Step 1: trunk-changes-diary**

```bash
cd ~/dev/src/github.com/bash0C7/trunk-changes-diary
git status
git push  # Task 1-5 の各コミットが push 済みのはず
```

- [ ] **Step 2: ruby-knowledge-db**

```bash
cd ~/dev/src/github.com/bash0C7/ruby-knowledge-db
git add -A
git status
# 変更があれば commit & push
```

- [ ] **Step 3: picoruby-trunk-changes-generator**

```bash
cd ~/dev/src/github.com/bash0C7/picoruby-trunk-changes-generator
git status
# 変更があれば commit & push
```
