require 'informers'

module RubyKnowledgeStore
  class Embedder
    VECTOR_SIZE = 768
    MODEL_NAME  = 'mochiya98/ruri-v3-310m-onnx'

    def initialize
      @model = Informers.pipeline('feature-extraction', MODEL_NAME)
    end

    def embed(text)
      result = @model.(text, model_output: 'sentence_embedding', normalize: true)
      result.flatten
    end
  end
end
