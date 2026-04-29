# frozen_string_literal: true

module RubyKnowledgeDb
  class PipelinePlan
    def initialize(cfg:, since: nil, before: nil, bookmark_data:, today: nil, esa_searcher: nil)
    end

    def to_h
      {}
    end

    def consistent?
      false
    end

    def contradiction_reasons
      []
    end
  end
end
