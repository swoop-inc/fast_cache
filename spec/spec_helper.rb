require 'rspec/its'
require 'simplecov'
SimpleCov.start
SimpleCov.minimum_coverage 100

require 'pp'
require 'timecop'

require 'fast_cache'

Dir['spec/support/**/*.rb'].each { |f| require File.expand_path(f) }

RSpec.configure do |config|
  config.after do
    Timecop.return
  end
end
