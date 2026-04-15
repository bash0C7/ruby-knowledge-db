# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'time'

module RubyKnowledgeDb
  module TrunkBookmark
    module_function

    def load(path)
      return {} unless File.exist?(path)
      YAML.load_file(path) || {}
    end

    def save(path, data)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, data.to_yaml)
    end

    def mark_started(data, source_key, before:, at: Time.now)
      entry = data[source_key].is_a?(Hash) ? data[source_key].dup : {}
      entry['last_started_at']     = at.iso8601
      entry['last_started_before'] = before.to_s
      data[source_key] = entry
      data
    end
  end
end
