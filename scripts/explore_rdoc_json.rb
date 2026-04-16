#!/usr/bin/env ruby
# frozen_string_literal: true

# Findings:
#
# 1. `rdoc --format=json` does NOT exist. RDoc 7.2.0 has formatters: darkfish, ri, pot, aliki.
#    There is an RDoc::Generator::JsonIndex but it only produces a search index for darkfish HTML.
#
# 2. The correct approach is to use RDoc's programmatic API (RDoc::RDoc#document) with `--format=ri`
#    and then inspect the RDoc::Store object directly. This gives full access to parsed data.
#
# 3. Structure of RDoc objects (via RDoc::Store after parsing):
#
#    Class/Module entity (RDoc::NormalClass / RDoc::NormalModule):
#      - full_name        : String ("String", "Integer", "Array")
#      - comment          : RDoc::Comment (format: "rdoc")
#        - comment.text   : String — raw RDoc markup (NOT HTML, NOT Markdown)
#        - comment.format : "rdoc"
#        NOTE: class-level comment.text may be empty for classes defined in C files
#              (e.g., String from string.c has empty class comment; Array/Integer have content)
#      - method_list      : Array<RDoc::AnyMethod>
#      - includes         : Array<RDoc::Include> (.name for module name)
#      - constants        : Array<RDoc::Constant> (.name, .value, .comment)
#      - attributes       : Array<RDoc::Attr>
#      - class (Ruby)     : RDoc::NormalClass
#
#    Method entity (RDoc::AnyMethod):
#      - full_name        : String ("String#gsub", "Array::[]")
#      - name             : String ("gsub", "[]")
#      - call_seq          : String or nil — multi-line call signatures
#                           e.g. "gsub(pattern, replacement)   -> new_string\ngsub(pattern) {|match| ... } -> new_string"
#      - arglists         : String or nil — same as call_seq in most cases
#      - params           : String — C-style params e.g. "(*args)", "(p1)"
#      - comment          : RDoc::Comment
#        - comment.text   : String — raw RDoc markup description of the method
#      - type             : "instance" or "class"
#      - singleton        : true/false
#      - visibility       : :public / :protected / :private (Symbol)
#      - file_name        : String — source file path (absolute)
#
# 4. Description format: RDoc raw markup (not HTML, not Markdown).
#    Contains +code+, \Escaped, {links}[url], indented code blocks, etc.
#
# 5. Ruby::Box is NOT a public API class. It exists only as test fixtures in test/ruby/box/.
#
# 6. File info: method.file_name returns the absolute path of the source file.
#    There is no separate "files" array on the class entity via this API.
#
# 7. Recommended approach for ruby-rdoc-collector:
#    - Use RDoc::RDoc.new.document([...files...]) to parse
#    - Iterate store.all_classes_and_modules for class/module entities
#    - Access .method_list on each for methods
#    - Use .comment.text for descriptions and .call_seq for signatures
#    - Description text is RDoc markup — will need conversion for storage

# Probe `rdoc` programmatic API output shape.
# Usage: RUBY_REPO=~/.cache/trunk-changes-repos/ruby ruby scripts/explore_rdoc_json.rb

require 'json'
require 'tmpdir'
require 'rdoc'

repo    = ENV.fetch('RUBY_REPO', File.expand_path('~/.cache/trunk-changes-repos/ruby'))
targets = %w[String Integer Array]
source_files = %w[string.c numeric.c array.c].map { |f| File.join(repo, f) }

abort "repo not found: #{repo}" unless Dir.exist?(repo)
source_files.each { |f| abort "file not found: #{f}" unless File.exist?(f) }

Dir.mktmpdir('rdoc_probe') do |tmpdir|
  outdir = File.join(tmpdir, 'ri_output')
  puts "Parsing #{source_files.map { |f| File.basename(f) }.join(', ')} via RDoc API..."

  rdoc = RDoc::RDoc.new
  rdoc.document(["--format=ri", "--quiet", "--output=#{outdir}"] + source_files)
  store = rdoc.store

  all = store.all_classes_and_modules.sort_by(&:full_name)
  puts "All classes/modules found: #{all.map(&:full_name).join(', ')}"
  puts

  fixture = {}

  all.each do |cls|
    next unless targets.include?(cls.full_name)

    puts "=" * 60
    puts "=== #{cls.full_name} ==="
    puts "  Ruby class : #{cls.class}"
    puts "  comment fmt: #{cls.comment.format rescue '?'}"

    comment_text = cls.comment.text rescue cls.comment.to_s
    puts "  comment len: #{comment_text.length}"
    puts "  comment 300: #{comment_text[0, 300].inspect}" unless comment_text.empty?

    puts "  includes   : #{cls.includes.map(&:name)}"
    puts "  constants  : #{cls.constants.map(&:name).take(5)}"
    puts "  methods    : #{cls.method_list.size}"

    # Show 2 methods with content
    shown = 0
    cls.method_list.each do |m|
      ct = m.comment.text rescue m.comment.to_s
      next if ct.empty? && (m.call_seq.nil? || m.call_seq.empty?)
      puts "  --- #{m.full_name} ---"
      puts "    call_seq   : #{m.call_seq[0, 150].inspect}" if m.call_seq
      puts "    params     : #{m.params.inspect}"
      puts "    type       : #{m.type}"
      puts "    visibility : #{m.visibility}"
      puts "    singleton  : #{m.singleton}"
      puts "    comment 200: #{ct[0, 200].inspect}" unless ct.empty?
      shown += 1
      break if shown >= 2
    end

    # Build fixture
    fixture[cls.full_name] = {
      "full_name" => cls.full_name,
      "type" => cls.class.name,
      "comment_format" => (cls.comment.format rescue nil),
      "comment_text_excerpt" => (cls.comment.text[0, 500] rescue cls.comment.to_s[0, 500]),
      "method_count" => cls.method_list.size,
      "includes" => cls.includes.map(&:name),
      "constants" => cls.constants.map(&:name),
      "sample_methods" => cls.method_list.take(3).map { |m|
        {
          "full_name" => m.full_name,
          "name" => m.name,
          "call_seq" => m.call_seq,
          "params" => m.params,
          "type" => m.type,
          "visibility" => m.visibility.to_s,
          "singleton" => m.singleton,
          "comment_excerpt" => (m.comment.text[0, 300] rescue m.comment.to_s[0, 300])
        }
      }
    }
  end

  fixture_path = "/tmp/rdoc_probe_fixture.json"
  File.write(fixture_path, JSON.pretty_generate(fixture))
  puts
  puts "Fixture saved to #{fixture_path} (#{File.size(fixture_path)} bytes)"
end
