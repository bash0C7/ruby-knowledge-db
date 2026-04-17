# frozen_string_literal: true

require 'date'
require 'net/http'
require 'uri'
require 'json'

module RubyKnowledgeDb
  module EsaPreflight
    module_function

    # Returns Array<Hash> of conflicts: [{key:, date:, title:, category:, posts: [...]}, ...]
    def conflicts(cfg:, since:, before:, searcher:)
      esa_cfg = cfg['esa']
      return [] unless esa_cfg

      results = []
      sources = cfg['sources'] || {}
      sources.each_key do |key|
        next unless key.to_s.end_with?('_trunk')
        category = esa_cfg.dig('sources', key, 'category')
        next unless category

        short_name = key.sub(/_trunk$/, '')
        date = Date.parse(since)
        stop = Date.parse(before)
        while date < stop
          title = "#{date}-#{short_name}-trunk-changes"
          y, m, d = date.to_s.split('-')
          date_category = "#{category}/#{y}/#{m}/#{d}"

          posts = searcher.search(team: esa_cfg['team'], category: date_category, name: title)
          matching = posts.select do |p|
            base = p['name'].to_s.sub(/\s*\(\d+\)\s*$/, '')
            base == title
          end

          if matching.any?
            results << {
              key: key, date: date.to_s, title: title,
              category: date_category, posts: matching
            }
          end
          date = date.next_day
        end
      end
      results
    end

    def check_conflicts!(cfg:, since:, before:, searcher: DefaultSearcher.new)
      found = conflicts(cfg: cfg, since: since, before: before, searcher: searcher)
      return if found.empty?

      lines = ["esa preflight: existing posts detected in [#{since}, #{before}) — aborting to avoid duplicates"]
      found.each do |c|
        c[:posts].each do |p|
          lines << "  #{c[:key]} #{c[:date]}: ##{p['number']} #{p['full_name']}"
        end
      end
      lines << "Clean up esa side manually (e.g., `rake esa:find_duplicates DATE=#{found.first[:date]}` and `rake esa:delete IDS=...`), then re-run."
      abort lines.join("\n")
    end

    class DefaultSearcher
      def search(team:, category:, name:)
        token = fetch_token
        q = "category:#{category} name:#{name}"
        uri = URI("https://api.esa.io/v1/teams/#{team}/posts?q=#{URI.encode_www_form_component(q)}&per_page=100")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        req = Net::HTTP::Get.new(uri.request_uri)
        req['Authorization'] = "Bearer #{token}"
        body = JSON.parse(http.request(req).body)
        body['posts'] || []
      end

      private

      def fetch_token
        token = `/usr/bin/security find-generic-password -s 'esa-mcp-token' -w 2>/dev/null`.strip
        abort "ESA token not found in keychain (key: esa-mcp-token)" if token.empty?
        token
      end
    end
  end
end
