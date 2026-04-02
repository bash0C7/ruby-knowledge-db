# frozen_string_literal: true

module RubyKnowledgeDb
  class Orchestrator
    def initialize(store, collectors)
      @store      = store
      @collectors = collectors
    end

    # @param since [String, nil] ISO8601 — 前回実行時刻。nil なら全件
    # @return [Hash] { stored: Integer, skipped: Integer, errors: Array<String> }
    def run(since: nil)
      results = { stored: 0, skipped: 0, errors: [] }

      @collectors.each do |collector|
        collector.collect(since: since).each do |chunk|
          id = @store.store(chunk[:content], source: chunk[:source])
          if id
            results[:stored] += 1
          else
            results[:skipped] += 1
          end
        end
      rescue => e
        results[:errors] << "#{collector.class}: #{e.message}"
      end

      results
    end
  end
end
