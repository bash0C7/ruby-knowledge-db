# frozen_string_literal: true

require 'yaml'

module RubyKnowledgeDb
  module Config
    APP_ENV = ENV.fetch('APP_ENV', 'development')

    CONFIG_DIR = File.expand_path('../../../config', __FILE__)

    def self.load
      sources   = YAML.load_file(File.join(CONFIG_DIR, 'sources.yml'))
      env_file  = File.join(CONFIG_DIR, 'environments', "#{APP_ENV}.yml")
      abort "Unknown APP_ENV: #{APP_ENV} (no file: #{env_file})" unless File.exist?(env_file)
      env_cfg   = YAML.load_file(env_file)
      sources.merge(env_cfg)
    end
  end
end
