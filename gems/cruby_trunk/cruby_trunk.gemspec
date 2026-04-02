Gem::Specification.new do |spec|
  spec.name          = 'cruby_trunk'
  spec.version       = '0.1.0'
  spec.authors       = ['bash0C7']
  spec.summary       = 'Collector for ruby/ruby trunk changes'
  spec.files         = Dir['lib/**/*.rb']
  spec.require_paths = ['lib']
  spec.add_dependency 'trunk_changes_diary'
end
