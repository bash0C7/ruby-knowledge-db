# test/test_helper.rb
require 'test/unit'

class StubEmbedder
  VECTOR_SIZE = 768

  def embed(_text)
    Array.new(VECTOR_SIZE, 0.0)
  end
end

# Shared esa.io searcher stub for EsaPreflight / PipelinePlan tests.
# Records calls so callers can assert how many times the searcher was hit.
class StubEsaSearcher
  def initialize(posts_by_key = {})
    @posts_by_key = posts_by_key
    @calls = []
  end

  attr_reader :calls

  def search(team:, category:, name:)
    @calls << { team: team, category: category, name: name }
    @posts_by_key.fetch([team, category, name], [])
  end
end
