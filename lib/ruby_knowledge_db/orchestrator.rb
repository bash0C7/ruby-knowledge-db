# frozen_string_literal: true

module RubyKnowledgeDb
  class Orchestrator
    def initialize(store, collectors)
      @store      = store
      @collectors = collectors
    end

    # @param since  [String, nil] ISO8601 — 収集開始時刻。nil なら全件
    # @param before [String, nil] ISO8601 — 収集終了時刻（排他）
    # @return [Hash] { stored: Integer, skipped: Integer, errors: Array<String> }
    def run(since:, before:)
      results = { stored: 0, skipped: 0, errors: [] }

      @collectors.each do |collector|
        begin
          records = collector.collect(since: since, before: before)
          records.each do |record|
            id = @store.store(record[:content], source: record[:source])
            if id
              results[:stored] += 1
            else
              results[:skipped] += 1
            end
          end
        rescue => e
          results[:errors] << "#{collector.class.name}: #{e.message}"
        end
      end

      results
    end
  end
end
