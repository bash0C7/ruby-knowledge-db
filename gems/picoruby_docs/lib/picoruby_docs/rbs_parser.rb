module PicorubyDocs
  class RbsParser
    ParsedRbs = Struct.new(:class_name, :sidebar_tag, :constants, :instance_methods, :class_methods, :attributes, keyword_init: true) do
      def to_doc
        lines = ["## #{class_name}"]
        lines << "Category: #{sidebar_tag}" if sidebar_tag
        lines << ""

        unless constants.empty?
          lines << "### Constants"
          constants.each { |c| lines << "- `#{c}`" }
          lines << ""
        end

        unless attributes.empty?
          lines << "### Attributes"
          attributes.each { |a| lines << "- `#{a}`" }
          lines << ""
        end

        unless class_methods.empty?
          lines << "### Class Methods"
          class_methods.each { |m| lines << "- `#{m}`" }
          lines << ""
        end

        unless instance_methods.empty?
          lines << "### Instance Methods"
          instance_methods.each { |m| lines << "- `#{m}`" }
          lines << ""
        end

        lines.join("\n")
      end
    end

    # @param rbs_source [String]
    # @return [ParsedRbs]
    def parse(rbs_source)
      ParsedRbs.new(
        class_name:       extract_class_name(rbs_source),
        sidebar_tag:      extract_sidebar_tag(rbs_source),
        constants:        extract_constants(rbs_source),
        instance_methods: extract_instance_methods(rbs_source),
        class_methods:    extract_class_methods(rbs_source),
        attributes:       extract_attributes(rbs_source)
      )
    end

    private

    def extract_class_name(src)
      src.match(/^class\s+(\S+)/)&.captures&.first || '(unknown)'
    end

    def extract_sidebar_tag(src)
      src.match(/#\s*@sidebar\s+(\S+)/)&.captures&.first
    end

    def extract_constants(src)
      src.scan(/^\s{0,2}([A-Z][A-Z0-9_]+)\s*:/).flatten.uniq
    end

    def extract_class_methods(src)
      src.scan(/def self\.(\w+[\?!]?)\s*:\s*([^\n]+)/).map do |name, sig|
        "#{name}: #{sig.strip}"
      end
    end

    def extract_instance_methods(src)
      src.scan(/^\s+def (\w+[\?!]?)\s*:\s*([^\n]+)/).map do |name, sig|
        "#{name}: #{sig.strip}"
      end
    end

    def extract_attributes(src)
      src.scan(/attr_(?:reader|writer|accessor)\s+(\w+)\s*:\s*([^\n]+)/).map do |name, type|
        "#{name}: #{type.strip}"
      end
    end
  end
end
