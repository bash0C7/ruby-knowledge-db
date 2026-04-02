require_relative 'gem_doc_collector'

module PicorubyDocs
  class Collector
    SOURCE_PREFIX = 'picoruby/picoruby:docs'

    def initialize(config, gem_doc_collector_class: nil)
      @repo_path               = File.expand_path(config['repo_path'])
      @gem_doc_collector_class = gem_doc_collector_class || GemDocCollector
    end

    # since: は無視（常に全件収集。content_hash で冪等性を担保）
    # @param since [String, nil]
    # @return [Array<{content: String, source: String}>]
    def collect(since: nil)
      results = []
      mrbgem_dirs.each do |gem_dir|
        gem_name  = File.basename(gem_dir)
        source    = "#{SOURCE_PREFIX}/#{gem_name}"
        collector = @gem_doc_collector_class.new(gem_dir)
        collector.collect.each do |content|
          results << { content: content, source: source }
        end
      end
      results
    end

    private

    def mrbgem_dirs
      Dir.glob(File.join(@repo_path, 'mrbgems', 'picoruby-*'))
         .select { |d| File.directory?(d) }
         .sort
    end
  end
end
