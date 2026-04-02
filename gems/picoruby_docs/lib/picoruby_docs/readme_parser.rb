module PicorubyDocs
  class ReadmeParser
    # @param readme_source [String]
    # @return [String, nil]
    def parse(readme_source)
      stripped = readme_source.strip
      return nil if stripped.empty?
      stripped
    end
  end
end
