require 'bitclust/rrdparser'
require_relative 'doctree_manager'

module Rurema
  class Collector
    SOURCE_PREFIX = 'rurema/doctree'

    def initialize(config, doctree_manager: nil, rd_parser: nil)
      @version         = config.fetch('version', '3.3.0')
      @doctree_manager = doctree_manager || DoctreeManager.new(config.fetch('doctree_path'))
      @rd_parser       = rd_parser       || DefaultRDParser.new
    end

    # since: は無視（常に全件収集。content_hash で冪等性を担保）
    # @param since [String, nil]
    # @return [Array<{content: String, source: String}>]
    def collect(since: nil)
      @doctree_manager.sync
      results = []
      @doctree_manager.rd_files(@version).each do |path|
        parse_rd_file(path, results)
      end
      results
    end

    private

    def lib_source(lib_name)
      "#{SOURCE_PREFIX}:ruby#{version_label}/#{lib_name}"
    end

    def class_source(lib_name, class_name)
      "#{SOURCE_PREFIX}:ruby#{version_label}/#{lib_name}##{class_name}"
    end

    def version_label
      @version.split('.').first(2).join('.')
    end

    def parse_rd_file(path, results)
      library_entry = @rd_parser.parse(path, @version)
      return if library_entry.nil?

      lib_src = library_entry.source.to_s.strip
      unless lib_src.empty?
        results << { content: lib_src, source: lib_source(library_entry.name) }
      end

      library_entry.classes.each do |class_entry|
        cls_src = class_entry.source.to_s.strip
        next if cls_src.empty?
        results << { content: cls_src, source: class_source(library_entry.name, class_entry.name) }
      end
    rescue => e
      warn "[Rurema::Collector] skip #{path}: #{e.class}: #{e.message}"
    end

    class DefaultRDParser
      def parse(path, version)
        BitClust::RRDParser.parse_stdlib_file(path, { 'version' => version })
      rescue => e
        warn "[Rurema::DefaultRDParser] parse error #{path}: #{e.class}: #{e.message}"
        nil
      end
    end
  end
end
