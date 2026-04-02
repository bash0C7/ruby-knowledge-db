require_relative 'rbs_parser'
require_relative 'readme_parser'

module PicorubyDocs
  class GemDocCollector
    def initialize(gem_dir, rbs_parser: nil, readme_parser: nil)
      @gem_dir       = gem_dir
      @rbs_parser    = rbs_parser    || RbsParser.new
      @readme_parser = readme_parser || ReadmeParser.new
    end

    # @return [Array<String>]
    def collect
      results = []

      rbs_content = collect_rbs
      results << rbs_content if rbs_content && !rbs_content.strip.empty?

      readme_content = collect_readme
      results << readme_content if readme_content && !readme_content.strip.empty?

      results
    end

    private

    def collect_rbs
      rbs_files = Dir.glob(File.join(@gem_dir, 'sig', '*.rbs')).sort
      return nil if rbs_files.empty?

      sections = rbs_files.filter_map do |rbs_file|
        @rbs_parser.parse(File.read(rbs_file)).to_doc
      rescue => e
        warn "PicorubyDocs: RBS parse failed: #{rbs_file} (#{e.message})"
        nil
      end

      sections.empty? ? nil : sections.join("\n\n")
    end

    def collect_readme
      readme_path = File.join(@gem_dir, 'README.md')
      return nil unless File.exist?(readme_path)

      @readme_parser.parse(File.read(readme_path))
    rescue => e
      warn "PicorubyDocs: README parse failed: #{readme_path} (#{e.message})"
      nil
    end
  end
end
