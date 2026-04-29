# frozen_string_literal: true

require_relative '../test/test_helper'
require_relative '../lib/ruby_knowledge_db/update_runner'

class StubTask
  attr_reader :name, :invoked

  def initialize(name, &on_invoke)
    @name = name
    @invoked = false
    @on_invoke = on_invoke || proc {}
  end

  def invoke
    @invoked = true
    @on_invoke.call
  end
end

class TestUpdateRunner < Test::Unit::TestCase
  def test_all_tasks_succeed_returns_empty_failures
    tasks = [StubTask.new('update:rurema'), StubTask.new('update:picoruby_docs')]
    failures = RubyKnowledgeDb::UpdateRunner.run(tasks)
    assert_equal [], failures
    assert_true tasks.all?(&:invoked)
  end

  def test_middle_task_raises_but_subsequent_tasks_still_invoked
    order = []
    tasks = [
      StubTask.new('update:ok_first') { order << :first },
      StubTask.new('update:boom')     { order << :boom; raise 'middle boom' },
      StubTask.new('update:ok_last')  { order << :last }
    ]
    failures = RubyKnowledgeDb::UpdateRunner.run(tasks)

    assert_equal 1, failures.size
    assert_equal 'update:boom', failures.first.task_name
    assert_match(/middle boom/, failures.first.error.message)
    assert_equal %i[first boom last], order
  end

  def test_all_tasks_raise_returns_all_failures_in_order
    tasks = [
      StubTask.new('update:a') { raise 'err a' },
      StubTask.new('update:b') { raise 'err b' }
    ]
    failures = RubyKnowledgeDb::UpdateRunner.run(tasks)
    assert_equal %w[update:a update:b], failures.map(&:task_name)
    assert_equal ['err a', 'err b'], failures.map { |f| f.error.message }
  end

  def test_yields_each_task_before_invoke
    tasks = [StubTask.new('update:a'), StubTask.new('update:b')]
    yielded = []
    RubyKnowledgeDb::UpdateRunner.run(tasks) { |t| yielded << t.name }
    assert_equal %w[update:a update:b], yielded
  end

  def test_yield_runs_even_when_task_raises
    tasks = [StubTask.new('update:bad') { raise 'kaboom' }]
    yielded = []
    RubyKnowledgeDb::UpdateRunner.run(tasks) { |t| yielded << t.name }
    assert_equal %w[update:bad], yielded
  end

  def test_failure_struct_keyword_init
    f = RubyKnowledgeDb::UpdateRunner::Failure.new(task_name: 'x', error: RuntimeError.new('y'))
    assert_equal 'x', f.task_name
    assert_equal 'y', f.error.message
  end

  def test_systemexit_in_task_does_not_kill_subsequent_tasks
    order = []
    tasks = [
      StubTask.new('update:ok_first') { order << :first },
      StubTask.new('update:abort')    { order << :abort_called; raise SystemExit, 1 },
      StubTask.new('update:ok_last')  { order << :last }
    ]
    failures = nil
    assert_nothing_raised(SystemExit) do
      failures = RubyKnowledgeDb::UpdateRunner.run(tasks)
    end
    assert_equal %i[first abort_called last], order
    assert_equal 1, failures.size
    assert_equal 'update:abort', failures.first.task_name
    assert_kind_of SystemExit, failures.first.error
  end
end
