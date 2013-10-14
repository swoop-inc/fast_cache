# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fast_cache/version'

Gem::Specification.new do |spec|
  spec.name          = "fast_cache"
  spec.version       = FastCache::VERSION
  spec.authors       = ["Simeon Simeonov"]
  spec.email         = ["sim@swoop.com"]
  spec.description   = %q{Very fast LRU + TTL cache}
  spec.summary       = %q{FastCache is an in-process cache with both least-recently used (LRU) and time to live (TTL) expiration semantics. It is typically 5-100x faster than ActiveSupport::Cache::MemoryStore, depending on the cached data.}
  spec.homepage      = "https://github.com/swoop-inc/fast_cache"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "awesome_print"
  spec.add_development_dependency "timecop"
end
