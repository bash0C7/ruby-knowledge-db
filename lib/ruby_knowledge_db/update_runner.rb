# frozen_string_literal: true

module RubyKnowledgeDb
  # Invokes a sequence of Rake-task-like objects, isolating each invocation
  # with rescue so a single failure does not abort the rest. Returns the
  # collected failures so the caller can surface them after subsequent steps
  # (e.g. iCloud copy) have completed.
  module UpdateRunner
    Failure = Struct.new(:task_name, :error, keyword_init: true)

    module_function

    # @param tasks [Array<#name, #invoke>]
    # @yield [task] called immediately before each task.invoke (progress hook)
    # @return [Array<Failure>] failures (empty array = all succeeded)
    def run(tasks)
      failures = []
      tasks.each do |task|
        yield task if block_given?
        begin
          task.invoke
        rescue => e
          failures << Failure.new(task_name: task.name, error: e)
        end
      end
      failures
    end
  end
end
