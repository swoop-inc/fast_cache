require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'yard'

desc 'Default: run the specs'
task :default do
  system("bundle exec rspec")
end

desc 'Run the specs'
task :spec => :default

YARD::Rake::YardocTask.new do |t|
end
