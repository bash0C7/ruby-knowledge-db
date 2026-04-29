# frozen_string_literal: true

require 'date'
require_relative 'trunk_bookmark'
require_relative 'esa_preflight'

module RubyKnowledgeDb
  # Single source of truth for "what should the next pipeline run look like?"
  # Both `rake plan` (read-only inspection) and the `default` task's contradiction
  # guard consume this — keeps SINCE/BEFORE resolution and the contradiction
  # checklist in one place rather than scattered across Rakefile + subagent prompts.
  class PipelinePlan
    def initialize(cfg:, bookmark_data:, since: nil, before: nil, today: nil, esa_searcher: nil)
      @cfg             = cfg
      @bookmark_data   = bookmark_data
      @explicit_since  = since
      @explicit_before = before
      @today           = today || Date.today
      @esa_searcher    = esa_searcher || EsaPreflight::DefaultSearcher.new
    end

    def to_h
      @plan_hash ||= build_plan
    end

    def consistent?
      to_h['consistent']
    end

    def contradiction_reasons
      to_h['contradiction_reasons']
    end

    private

    def build_plan
      keys      = trunk_keys
      bm_status = TrunkBookmark.status(@bookmark_data, keys)
      floor     = TrunkBookmark.recommended_since_floor(@bookmark_data, keys)

      before_str        = @explicit_before || @today.to_s
      before_d          = Date.parse(before_str)
      since_str, source = resolve_since(floor)
      since_d           = Date.parse(since_str)

      wip_sources         = bm_status.select { |_, s| s[:wip] }.keys
      no_bookmark_sources = bm_status.select { |_, s| s[:last_started_before].nil? && s[:last_completed_before].nil? }.keys
      multiple_wip        = wip_sources.size > 1
      before_is_future    = before_d > @today
      since_invalid       = since_d >= before_d

      esa_conflicts = compute_esa_conflicts(since_str, before_str)

      reasons = []
      reasons << "WIP 残骸あり (#{wip_sources.size}件): #{wip_sources.join(', ')}"          if wip_sources.any?
      reasons << "bookmark 欠落: #{no_bookmark_sources.join(', ')}"                         if no_bookmark_sources.any?
      reasons << "bookmark 不足（fallback_yesterday 採用）: trunk sources=#{keys.join(', ')}" if source == 'fallback_yesterday' && @explicit_since.nil?
      reasons << "esa 衝突: #{esa_conflicts.size} 件 [#{since_str}, #{before_str})"        if esa_conflicts.any?
      reasons << "SINCE(#{since_str}) >= BEFORE(#{before_str}) は不正な区間"                if since_invalid
      reasons << "BEFORE(#{before_str}) が未来日付（today=#{@today})"                       if before_is_future

      {
        'since'                  => since_str,
        'before'                 => before_str,
        'since_source'           => source,
        'app_env'                => RubyKnowledgeDb::Config::APP_ENV,
        'trunk_sources'          => trunk_sources_hash(keys, bm_status),
        'wip_sources'            => wip_sources,
        'no_bookmark_sources'    => no_bookmark_sources,
        'esa_conflicts'          => serialize_conflicts(esa_conflicts),
        'before_is_future'       => before_is_future,
        'multiple_wip'           => multiple_wip,
        'consistent'             => reasons.empty?,
        'contradiction_reasons'  => reasons
      }
    end

    def trunk_keys
      (@cfg['sources'] || {}).keys.select { |k| k.to_s.end_with?('_trunk') }
    end

    def resolve_since(floor)
      return [@explicit_since, 'explicit']    if @explicit_since
      return [floor,           'bookmark_floor'] if floor
      [(@today - 1).to_s,      'fallback_yesterday']
    end

    def trunk_sources_hash(keys, bm_status)
      keys.each_with_object({}) do |k, h|
        s = bm_status[k]
        h[k] = {
          'last_started_before'   => s[:last_started_before],
          'last_completed_before' => s[:last_completed_before],
          'wip'                   => s[:wip],
          'recommended_since'     => s[:recommended_since]
        }
      end
    end

    def serialize_conflicts(conflicts)
      conflicts.map do |c|
        {
          'key'      => c[:key],
          'date'     => c[:date],
          'title'    => c[:title],
          'category' => c[:category],
          'posts'    => c[:posts].map { |p| { 'number' => p['number'], 'name' => p['name'], 'full_name' => p['full_name'] } }
        }
      end
    end

    def compute_esa_conflicts(since, before)
      return [] unless @cfg['esa']
      EsaPreflight.conflicts(cfg: @cfg, since: since, before: before, searcher: @esa_searcher)
    end
  end
end
