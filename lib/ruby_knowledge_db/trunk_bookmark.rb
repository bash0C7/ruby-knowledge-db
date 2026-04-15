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

    def mark_completed(data, source_key, before:, at: Time.now)
      entry = data[source_key].is_a?(Hash) ? data[source_key].dup : {}
      entry['last_completed_at']     = at.iso8601
      entry['last_completed_before'] = before.to_s
      data[source_key] = entry
      data
    end

    # Returns per-source bookmark snapshot (nil-safe). For a single SINCE floor
    # across all sources, use `recommended_since_floor` instead.
    # @return [Hash{String => Hash}] keyed by source_key, each with
    #   :last_started_at, :last_started_before, :last_completed_at,
    #   :last_completed_before, :wip, :recommended_since (per-source completed_before)
    def status(data, source_keys)
      source_keys.each_with_object({}) do |key, acc|
        entry     = data[key].is_a?(Hash) ? data[key] : {}
        started   = entry['last_started_before']
        completed = entry['last_completed_before']
        wip = !started.nil? && (completed.nil? || started > completed)
        acc[key] = {
          last_started_at:       entry['last_started_at'],
          last_started_before:   started,
          last_completed_at:     entry['last_completed_at'],
          last_completed_before: completed,
          wip:                   wip,
          recommended_since:     completed
        }
      end
    end

    # Returns the safest SINCE floor across all sources: min of last_completed_before.
    # Returns nil if any source has no last_completed_before (caller must decide fallback).
    # For per-source detail (WIP flag etc), use `status` instead.
    def recommended_since_floor(data, source_keys)
      completed = source_keys.map do |key|
        entry = data[key].is_a?(Hash) ? data[key] : {}
        entry['last_completed_before']
      end
      return nil if completed.any?(&:nil?)
      completed.min
    end
  end
end
