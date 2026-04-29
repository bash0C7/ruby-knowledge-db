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
        rescue Interrupt
          # User-initiated abort (Ctrl+C). Propagate so the whole pipeline stops.
          raise
        rescue Exception => e # rubocop:disable Lint/RescueException
          # Catch SystemExit too: tasks that call `abort` for missing ENV / DB
          # should be isolated like any other failure, not skip the iCloud copy.
          failures << Failure.new(task_name: task.name, error: e)
        end
      end
      failures
    end

    # Single-line summary by default; with verbose: true, appends a backtrace
    # tail (top 20 frames) so callers can opt into a debug dump without
    # paying the noise cost on every run.
    # @param failure [Failure]
    # @param verbose [Boolean]
    # @return [String]
    def format_failure(failure, verbose: false)
      base = "#{failure.task_name}: #{failure.error.class}: #{failure.error.message}"
      return base unless verbose

      bt = failure.error.backtrace
      return base if bt.nil? || bt.empty?

      ([base] + bt.first(20).map { |l| "    #{l}" }).join("\n")
    end
  end
end
